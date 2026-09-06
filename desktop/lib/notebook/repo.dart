// Lupa 生词本 CRUD — 与 Python 版 src/lupa/notebook/repo.py 行为对齐（纯数据层，无 UI）。
//
// schema 见 lib/data/schema.sql（notes / cards / revlog / 3 缓存表 / meta）。
// 字段语义、id 生成、去重与错误行为均与 Python 版保持一致。
import 'package:crypto/crypto.dart';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/notebook_db.dart';
import 'scheduler.dart' show dueTimestamp;

// 与 Python 版对齐的常量
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

/// Anki 兼容 id（毫秒时间戳 ^ 随机低 16 位，与 Python 版 _gen_anki_id 一致）。
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

/// 删除生词（notes 级联删 cards，依赖 PRAGMA foreign_keys=ON）。返回是否删除了。
Future<bool> removeWord(String nbPath, String word) async {
  final con = await _openNb(nbPath);
  try {
    final n = await con.rawDelete(
      'DELETE FROM notes WHERE sfld = ? COLLATE NOCASE',
      [word.trim()],
    );
    return n > 0;
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

/// 对一张卡打分（1-4），推进调度。返回 (nextIvl, nextDue)。同时写入 revlog。
Future<(int, int)> answerCard(String nbPath, int cardId, int ease) async {
  await ensureNotebookDb(nbPath);
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final con = await _openNb(nbPath);
  try {
    final cardRows = await con.rawQuery(
      'SELECT ivl, reps, type FROM cards WHERE id = ?',
      [cardId],
    );
    if (cardRows.isEmpty) {
      throw StateError('card 不存在: $cardId');
    }
    final card = cardRows.first;
    final lastIvl = card['ivl'] as int;
    final (nextIvl, nextDue) = dueTimestamp(lastIvl, ease, now: now);
    final newType = ease >= 2 ? cardReview : cardLearn;

    await con.rawUpdate(
      'UPDATE cards SET ivl = ?, due = ?, type = ?, reps = reps + 1, '
      'lapses = lapses + ?, mod = ? WHERE id = ?',
      [
        nextIvl,
        nextDue,
        newType,
        ease < 2 ? 1 : 0,
        now,
        cardId,
      ],
    );
    await con.rawInsert(
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
    return (nextIvl, nextDue);
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

/// 打开生词本连接（启用外键级联，与 Python 版 _connect 一致）。
/// singleInstance: false —— sqflite 默认同路径返回连接单例，A 函数 close
/// 会把 B 并发查询的连接关掉（database_closed）；独立连接才符合
/// 「函数内开、finally 关」的模型。
Future<Database> _openNb(String nbPath) async {
  final con = await databaseFactory.openDatabase(p.absolute(nbPath),
      options: OpenDatabaseOptions(singleInstance: false));
  await con.execute('PRAGMA foreign_keys = ON');
  return con;
}
