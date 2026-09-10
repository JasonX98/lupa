// Lupa 生词本 CRUD — 纯数据层，无 UI。
//
// schema 见 lib/data/schema.sql（notes / cards / revlog / 3 缓存表 / meta）。
// 字段语义、id 生成、去重与错误行为是 Anki 兼容的唯一实现。
import 'package:crypto/crypto.dart';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/notebook_db.dart';
import 'scheduler.dart' show dueTimestamp;

// 调度 / 牌组常量
const int modelId = 1; // 默认笔记模型 id（v1 只有一种模型）
const int deckId = 1; // 默认牌组 id
const String fieldSep = '\x1f'; // Anki 字段分隔符

// 卡片状态常量（抄 Anki CardType/CardQueue）
const int cardNew = 0;
const int cardLearn = 1;
const int cardReview = 2;
const int queueNew = 0;
const int queueSuspended = -1;

/// 生词本条目（notes 行 + cards 调度状态 + 词库内容）。
class NotebookEntry {
  final int noteId;
  final int cardId;
  final String word;
  final String phonetic;
  final String translation;
  final String definition;
  final String exchange;
  final String tags;
  final int cardType; // 0=New 1=Learn 2=Review 3=Relearn
  final int queue;
  final int due;
  final int ivl;
  final int reps;
  final int lapses;
  final int addedAt;

  const NotebookEntry({
    required this.noteId,
    required this.cardId,
    required this.word,
    required this.phonetic,
    required this.translation,
    required this.definition,
    required this.exchange,
    required this.tags,
    required this.cardType,
    required this.queue,
    required this.due,
    required this.ivl,
    required this.reps,
    required this.lapses,
    required this.addedAt,
  });
}

/// 词不在词库中。
class WordNotInDictError implements Exception {
  final String word;
  const WordNotInDictError(this.word);
  @override
  String toString() => 'WordNotInDictError: $word';
}

/// 词已在生词本中。
class DuplicateWordError implements Exception {
  final String word;
  const DuplicateWordError(this.word);
  @override
  String toString() => 'DuplicateWordError: $word';
}

final _random = Random();

/// Anki 兼容 id（毫秒时间戳 ^ 随机低 16 位）。
int _genAnkiId() =>
    DateTime.now().millisecondsSinceEpoch ^ _random.nextInt(0x10000);

/// Anki csum：首字段 sha1 前 8 位十六进制转整数。
int _csum(String flds) {
  final first = flds.split(fieldSep).first.trim().toLowerCase();
  return int.parse(sha1.convert(first.codeUnits).toString().substring(0, 8),
      radix: 16);
}

/// 查词库确认词已收录，返回词条行；未收录抛 WordNotInDictError。
Future<Map<String, Object?>> _checkDictWord(String dictDb, String word) async {
  initDatabaseFactory();
  final con = await databaseFactory.openDatabase(dictDb,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
  try {
    final rows = await con.rawQuery(
      'SELECT * FROM dict WHERE word = ? COLLATE NOCASE',
      [word.trim()],
    );
    if (rows.isEmpty) throw WordNotInDictError(word);
    return rows.first;
  } finally {
    await con.close();
  }
}

/// 加入生词本。成功返回 note 内部 id。
///
/// Throws: [WordNotInDictError] 词不在词库; [DuplicateWordError] 词已在生词本。
Future<int> addWord(
  String nbPath,
  String dictDb,
  String word,
  String tags,
) async {
  final entry = await _checkDictWord(dictDb, word);
  await ensureNotebookDb(nbPath);

  final flds = [
    entry['word'] as String,
    entry['phonetic'] as String? ?? '',
    entry['translation'] as String? ?? '',
    entry['definition'] as String? ?? '',
    entry['exchange'] as String? ?? '',
  ].join(fieldSep);
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final w = word.trim();

  final con = await _openNb(nbPath);
  try {
    final dup = await con.rawQuery(
      'SELECT id FROM notes WHERE sfld = ? COLLATE NOCASE',
      [w],
    );
    if (dup.isNotEmpty) throw DuplicateWordError(word);

    final noteId = await con.rawInsert(
      'INSERT INTO notes (n_id, m_id, mod, usn, tags, flds, sfld, csum, flags, data) '
      'VALUES (?, ?, ?, 0, ?, ?, ?, ?, 0, \'\')',
      [
        _genAnkiId().toString(),
        modelId,
        now,
        tags.trim(),
        flds,
        w,
        _csum(flds),
      ],
    );

    await con.rawInsert(
      'INSERT INTO cards (c_id, n_id, did, ord, mod, usn, type, queue, due, '
      'ivl, factor, reps, lapses, left, odue, odid, flags, data) '
      'VALUES (?, ?, ?, 0, ?, 0, ?, ?, 0, 0, 0, 0, 0, 0, 0, 0, 0, \'\')',
      [
        _genAnkiId().toString(),
        noteId,
        deckId,
        now,
        cardNew,
        queueNew,
      ],
    );
    return noteId;
  } finally {
    await con.close();
  }
}

/// 删除生词（notes 级联删 cards，依赖 PRAGMA foreign_keys=ON）。
///
/// 同时清理这些卡片的复习历史：`revlog` 没有外键（只有 cid 索引），不显式删除
/// 就会留下孤儿行（清理前实测存量 2 行）。返回是否删除了。
Future<bool> removeWord(String nbPath, String word) async {
  final con = await _openNb(nbPath);
  try {
    return await con.transaction((txn) async {
      final cardRows = await txn.rawQuery(
        'SELECT c.id AS id FROM cards c JOIN notes n ON n.id = c.n_id '
        'WHERE n.sfld = ? COLLATE NOCASE',
        [word.trim()],
      );
      final n = await txn.rawDelete(
        'DELETE FROM notes WHERE sfld = ? COLLATE NOCASE',
        [word.trim()],
      );
      if (cardRows.isNotEmpty) {
        final ids = cardRows.map((r) => r['id'] as int).toList();
        final ph = List.filled(ids.length, '?').join(',');
        await txn.rawDelete('DELETE FROM revlog WHERE cid IN ($ph)', ids);
      }
      return n > 0;
    });
  } finally {
    await con.close();
  }
}

NotebookEntry _rowToEntry(Map<String, Object?> row) {
  final flds = ((row['flds'] as String?) ?? '').split(fieldSep);
  final padded = [...flds, '', '', '', '', ''].sublist(0, 5);
  return NotebookEntry(
    noteId: row['note_id'] as int,
    cardId: row['card_id'] as int,
    word: padded[0],
    phonetic: padded[1],
    translation: padded[2],
    definition: padded[3],
    exchange: padded[4],
    tags: (row['tags'] as String?) ?? '',
    cardType: row['type'] as int,
    queue: row['queue'] as int,
    due: row['due'] as int,
    ivl: row['ivl'] as int,
    reps: row['reps'] as int,
    lapses: row['lapses'] as int,
    addedAt: row['mod'] as int,
  );
}

const String _entrySelect = '''
  SELECT n.id AS note_id, n.flds, n.tags, n.mod,
         c.id AS card_id, c.type, c.queue, c.due, c.ivl,
         c.reps, c.lapses
  FROM notes n JOIN cards c ON c.n_id = n.id
''';

/// 列出生词（加入时间倒序）。
Future<List<NotebookEntry>> listWords(
  String nbPath, {
  int limit = 50,
  bool includeSuspended = false,
}) async {
  await ensureNotebookDb(nbPath);
  final con = await _openNb(nbPath);
  try {
    var sql = _entrySelect;
    if (!includeSuspended) sql += ' WHERE c.queue >= 0';
    sql += ' ORDER BY n.mod DESC LIMIT ?';
    final rows = await con.rawQuery(sql, [limit]);
    return rows.map(_rowToEntry).toList();
  } finally {
    await con.close();
  }
}

/// 今天到期待复习的词（due <= now，含新卡）。
Future<List<NotebookEntry>> dueWords(String nbPath, {int limit = 20}) async {
  await ensureNotebookDb(nbPath);
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final con = await _openNb(nbPath);
  try {
    final rows = await con.rawQuery(
      '$_entrySelect WHERE c.queue >= 0 AND (c.type = 0 OR c.due <= ?) '
      'ORDER BY c.type ASC, c.due ASC LIMIT ?',
      [now, limit],
    );
    return rows.map(_rowToEntry).toList();
  } finally {
    await con.close();
  }
}

/// 一次评分的回执：撤销所需的全部信息（历史行 id + 评分前快照 + 本次结果）。
///
/// 撤销必须按回执恢复「绝对值」，不能事后推断：`revlog` 里没有 `due`/`reps`，
/// `time` 恒为 0，`type` 也把 learn/review 压成了 0/1。
class AnswerReceipt {
  final int cardId;
  final int revlogId; // revlog 行 id：撤销时精确删除这一条
  final int ease; // 本次评分：界面据此回退「记得/忘了」计数
  final int prevType;
  final int prevDue;
  final int prevIvl;
  final int prevReps;
  final int prevLapses;
  final int nextIvl;
  final int nextDue;

  const AnswerReceipt({
    required this.cardId,
    required this.revlogId,
    required this.ease,
    required this.prevType,
    required this.prevDue,
    required this.prevIvl,
    required this.prevReps,
    required this.prevLapses,
    required this.nextIvl,
    required this.nextDue,
  });
}

/// 对一张卡打分（1-4），推进调度，返回回执。
///
/// 卡片更新与 revlog 追加在同一事务内完成：撤销以「两者都成功」为前提。
Future<AnswerReceipt> answerCard(String nbPath, int cardId, int ease) async {
  await ensureNotebookDb(nbPath);
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final con = await _openNb(nbPath);
  try {
    return await con.transaction((txn) async {
      final cardRows = await txn.rawQuery(
        'SELECT ivl, due, reps, lapses, type FROM cards WHERE id = ?',
        [cardId],
      );
      if (cardRows.isEmpty) {
        throw StateError('card 不存在: $cardId');
      }
      final card = cardRows.first;
      final lastIvl = card['ivl'] as int;
      final (nextIvl, nextDue) = dueTimestamp(lastIvl, ease, now: now);
      final newType = ease >= 2 ? cardReview : cardLearn;

      await txn.rawUpdate(
        'UPDATE cards SET ivl = ?, due = ?, type = ?, reps = reps + 1, '
        'lapses = lapses + ?, mod = ? WHERE id = ?',
        [nextIvl, nextDue, newType, ease < 2 ? 1 : 0, now, cardId],
      );
      final revlogId = await txn.rawInsert(
        'INSERT INTO revlog (r_id, cid, usn, ease, ivl, last_ivl, factor, time, type) '
        'VALUES (?, ?, 0, ?, ?, ?, 0, 0, ?)',
        [
          _genAnkiId(),
          cardId,
          ease,
          nextIvl,
          lastIvl,
          (card['type'] as int) == 0 ? 0 : 1,
        ],
      );
      return AnswerReceipt(
        cardId: cardId,
        revlogId: revlogId,
        ease: ease,
        prevType: card['type'] as int,
        prevDue: card['due'] as int,
        prevIvl: lastIvl,
        prevReps: card['reps'] as int,
        prevLapses: card['lapses'] as int,
        nextIvl: nextIvl,
        nextDue: nextDue,
      );
    });
  } finally {
    await con.close();
  }
}

/// 撤销一次评分：按回执恢复卡片状态并删除该次历史记录（单事务）。
///
/// 只允许撤销该卡**最新**一条历史：回执对应的行已不是最新时拒绝（返回 false），
/// 防止上层拿过期回执删掉中间记录。「只能撤一次」由界面单槽保证。
Future<bool> undoAnswerCard(String nbPath, AnswerReceipt r) async {
  await ensureNotebookDb(nbPath);
  final con = await _openNb(nbPath);
  try {
    return await con.transaction((txn) async {
      final cardRows =
          await txn.rawQuery('SELECT id FROM cards WHERE id = ?', [r.cardId]);
      if (cardRows.isEmpty) return false; // 卡已不存在：无副作用
      final latest = (await txn.rawQuery(
              'SELECT MAX(id) AS m FROM revlog WHERE cid = ?', [r.cardId]))
          .first['m'];
      if (latest is! int || latest != r.revlogId) return false; // 回执过期
      final deleted =
          await txn.rawDelete('DELETE FROM revlog WHERE id = ?', [r.revlogId]);
      if (deleted != 1) return false;
      final updated = await txn.rawUpdate(
        'UPDATE cards SET ivl = ?, due = ?, type = ?, reps = ?, lapses = ? '
        'WHERE id = ?',
        [r.prevIvl, r.prevDue, r.prevType, r.prevReps, r.prevLapses, r.cardId],
      );
      if (updated != 1) {
        throw StateError('撤回卡片失败: ${r.cardId}'); // 抛错→事务回滚，不留半成品
      }
      return true;
    });
  } finally {
    await con.close();
  }
}

// ---- 复习数据重置（按范围）----
// 用途：把被误评分推进过的卡打回新词，并清掉对应复习历史。
// 分层：纯函数（时间窗 / 命中判定）→ 计划（只读，dry-run 打印它）→ 应用（单事务）。

/// `r_id` 是「毫秒时间戳 ^ random(0x10000)」（见 [_genAnkiId]），低 16 位被随机化，
/// 因此只能还原出一个 65.536 秒宽的时间窗（毫秒，左闭右开）。
(int, int) ridTimeWindowMillis(int rId) {
  final base = rId & ~0xFFFF;
  return (base, base + 0x10000);
}

/// 命中明细（纯函数）：两个时间来源分别是否命中。
/// - `mod`：该卡**只有 1 条**历史时，`cards.mod` 精确等于那次评分时间
/// - `rid`：`r_id` 时间窗与目标区间**相交**（≈±65 秒精度）
({bool mod, bool rid}) resetHitDetail({
  required int historyCount,
  required int cardModSec,
  required Iterable<int> revlogRIds,
  int? sinceSec,
  int? untilSec,
}) {
  final int sinceMs = sinceSec == null ? -0x7FFFFFFFFFFFFFFF : sinceSec * 1000;
  final int untilMs = untilSec == null ? 0x7FFFFFFFFFFFFFFF : untilSec * 1000;
  final bool mod = historyCount == 1 &&
      (sinceSec == null || cardModSec >= sinceSec) &&
      (untilSec == null || cardModSec < untilSec);
  var rid = false;
  for (final r in revlogRIds) {
    if (r <= 0) continue;
    final (lo, hi) = ridTimeWindowMillis(r);
    if (lo < untilMs && hi > sinceMs) {
      rid = true;
      break;
    }
  }
  return (mod: mod, rid: rid);
}

/// 命中判定（纯函数，可单测）：该卡的复习历史是否落在 `[sinceSec, untilSec)` 内。
/// 两个来源取并集，任一命中即算命中；偏向多命中——重置幂等可重跑，
/// 漏清才会让用户反复执行仍清不干净。
bool hitsResetWindow({
  required int historyCount,
  required int cardModSec,
  required Iterable<int> revlogRIds,
  int? sinceSec,
  int? untilSec,
}) {
  if (sinceSec == null && untilSec == null) return true; // 不限窗口 = 全命中
  final d = resetHitDetail(
    historyCount: historyCount,
    cardModSec: cardModSec,
    revlogRIds: revlogRIds,
    sinceSec: sinceSec,
    untilSec: untilSec,
  );
  return d.mod || d.rid;
}

/// 命中依据文案（dry-run 报告用）。
String resetHitBasis({
  required int historyCount,
  required int cardModSec,
  required Iterable<int> revlogRIds,
  int? sinceSec,
  int? untilSec,
}) {
  final d = resetHitDetail(
    historyCount: historyCount,
    cardModSec: cardModSec,
    revlogRIds: revlogRIds,
    sinceSec: sinceSec,
    untilSec: untilSec,
  );
  if (d.mod && d.rid) return 'mod+r_id';
  if (d.mod) return 'mod';
  if (d.rid) return 'r_id';
  return '';
}

/// 重置计划：dry-run 打印它，[applyReviewReset] 也只吃它。
class ReviewResetPlan {
  final List<String> words; // 命中的词（按卡片 id 升序）
  final List<int> cardIds;
  final int revlogRows; // 将删除的历史行数
  final Map<int, String> basis; // cardId -> 命中依据

  const ReviewResetPlan({
    required this.words,
    required this.cardIds,
    required this.revlogRows,
    required this.basis,
  });

  bool get isEmpty => cardIds.isEmpty;
}

/// 生成重置计划（**只读**，不写库）。
/// 范围二选一：[words]（指定词，忽略时间窗）或 [sinceSec]/[untilSec]（时间窗），
/// 或 [all] = 全部卡片。
Future<ReviewResetPlan> planReviewReset(
  String nbPath, {
  Set<String>? words,
  int? sinceSec,
  int? untilSec,
  bool all = false,
}) async {
  await ensureNotebookDb(nbPath);
  final con = await _openNb(nbPath);
  try {
    final cardRows = await con.rawQuery(
      'SELECT c.id AS id, c.mod AS mod, n.sfld AS sfld FROM cards c '
      'JOIN notes n ON n.id = c.n_id ORDER BY c.id',
    );
    final logRows =
        await con.rawQuery('SELECT cid, r_id FROM revlog ORDER BY cid, id');
    final ridByCard = <int, List<int>>{};
    for (final r in logRows) {
      (ridByCard[r['cid'] as int] ??= []).add(r['r_id'] as int);
    }

    final want = words?.map((w) => w.trim().toLowerCase()).toSet();
    final ids = <int>[];
    final pickedWords = <String>[];
    final basis = <int, String>{};
    for (final row in cardRows) {
      final id = row['id'] as int;
      final word = (row['sfld'] as String?) ?? '';
      final rids = ridByCard[id] ?? const <int>[];
      if (want != null) {
        if (!want.contains(word.toLowerCase())) continue;
        basis[id] = 'word';
      } else if (all) {
        basis[id] = 'all';
      } else {
        final hit = hitsResetWindow(
          historyCount: rids.length,
          cardModSec: row['mod'] as int,
          revlogRIds: rids,
          sinceSec: sinceSec,
          untilSec: untilSec,
        );
        if (!hit) continue;
        basis[id] = resetHitBasis(
          historyCount: rids.length,
          cardModSec: row['mod'] as int,
          revlogRIds: rids,
          sinceSec: sinceSec,
          untilSec: untilSec,
        );
      }
      ids.add(id);
      pickedWords.add(word);
    }
    var rows = 0;
    for (final id in ids) {
      rows += ridByCard[id]?.length ?? 0;
    }
    return ReviewResetPlan(
      words: pickedWords,
      cardIds: ids,
      revlogRows: rows,
      basis: basis,
    );
  } finally {
    await con.close();
  }
}

/// 应用重置计划（单事务）：命中卡片打回新词 + 删除其复习历史。
/// 返回删除的历史行数；不追加任何新历史。
Future<int> applyReviewReset(String nbPath, ReviewResetPlan plan) async {
  if (plan.cardIds.isEmpty) return 0;
  await ensureNotebookDb(nbPath);
  final con = await _openNb(nbPath);
  try {
    return await con.transaction((txn) async {
      final ph = List.filled(plan.cardIds.length, '?').join(',');
      final deleted = await txn.rawDelete(
        'DELETE FROM revlog WHERE cid IN ($ph)',
        plan.cardIds,
      );
      await txn.rawUpdate(
        'UPDATE cards SET type = ?, queue = ?, due = 0, ivl = 0, factor = 0, '
        'reps = 0, lapses = 0, left = 0, mod = ? WHERE id IN ($ph)',
        [
          cardNew,
          queueNew,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          ...plan.cardIds,
        ],
      );
      return deleted;
    });
  } finally {
    await con.close();
  }
}

/// 孤儿复习历史（cid 已不在 cards 中）的行 id，升序。
Future<List<int>> planOrphanRevlog(String nbPath) async {
  await ensureNotebookDb(nbPath);
  final con = await _openNb(nbPath);
  try {
    final rows = await con.rawQuery(
      'SELECT id FROM revlog WHERE cid NOT IN (SELECT id FROM cards) ORDER BY id',
    );
    return rows.map((r) => r['id'] as int).toList();
  } finally {
    await con.close();
  }
}

/// 删除指定的孤儿历史行（单事务）。不触碰任何卡片状态；返回删除条数。
Future<int> applyOrphanRevlogCleanup(String nbPath, List<int> rowIds) async {
  if (rowIds.isEmpty) return 0;
  await ensureNotebookDb(nbPath);
  final con = await _openNb(nbPath);
  try {
    return await con.transaction((txn) async {
      final ph = List.filled(rowIds.length, '?').join(',');
      return await txn.rawDelete('DELETE FROM revlog WHERE id IN ($ph)', rowIds);
    });
  } finally {
    await con.close();
  }
}

/// 生词本统计。
Future<Map<String, int>> notebookStats(String nbPath) async {
  await ensureNotebookDb(nbPath);
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final con = await _openNb(nbPath);
  try {
    Future<int> count(String sql, [List<Object?> args = const []]) async =>
        (await con.rawQuery(sql, args)).first.values.first as int;
    return {
      'total': await count('SELECT COUNT(*) FROM notes'),
      'new': await count('SELECT COUNT(*) FROM cards WHERE type = 0'),
      'review': await count('SELECT COUNT(*) FROM cards WHERE type = 2'),
      'due': await count('SELECT COUNT(*) FROM cards WHERE queue >= 0 '
          'AND (type = 0 OR due <= ?)', [now]),
      'lapses': await count('SELECT COALESCE(SUM(lapses), 0) FROM cards'),
    };
  } finally {
    await con.close();
  }
}

/// 打开生词本连接（启用外键级联）。
/// singleInstance: false —— sqflite 默认同路径返回连接单例，A 函数 close
/// 会把 B 并发查询的连接关掉（database_closed）；独立连接才符合
/// 「函数内开、finally 关」的模型。
Future<Database> _openNb(String nbPath) async {
  final con = await databaseFactory.openDatabase(p.absolute(nbPath),
      options: OpenDatabaseOptions(singleInstance: false));
  await con.execute('PRAGMA foreign_keys = ON');
  return con;
}
