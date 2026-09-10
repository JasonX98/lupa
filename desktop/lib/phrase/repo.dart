// Lupa 短语集仓库 — 与单词生词本完全隔离（独立三表，纯数据层，无 UI）。
//
// schema 见 lib/data/schema.sql 的 PHRASE_TABLES_V2 区块：
//   phrases（主表 + 内联 SRS 状态） / phrase_examples（可变长例句） / phrase_review_log。
// 调度复用 notebook/scheduler.dart 的固定间隔纯函数（模型无关）。
// 业务规则全部为纯函数：不读 stdin / 不写 stdout。
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/notebook_db.dart';
import '../notebook/scheduler.dart' show dueTimestamp;

/// 卡片状态常量（与单词卡一致：0=new 1=learn 2=review）
const int phraseNew = 0;
const int phraseLearn = 1;
const int phraseReview = 2;

final _random = Random();

int _genId() =>
    DateTime.now().millisecondsSinceEpoch ^ _random.nextInt(0x1000000);

int _nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// 一条例句（输入 / 输出共用）。
class PhraseExample {
  final String en;
  final String zh;
  const PhraseExample({required this.en, this.zh = ''});
}

/// 短语集条目（phrases 行 + 例句列表）。
class PhraseEntry {
  final int id;
  final String pId;
  final String phrase;
  final String lit;
  final String meaning;
  final String origin;
  final String scene;
  final String sceneTag;
  final List<String> tags;
  final int addedAt;
  final int state; // 0=New 1=Learn 2=Review
  final int due;
  final int ivl;
  final int reps;
  final int lapses;
  final List<PhraseExample> examples;

  const PhraseEntry({
    required this.id,
    required this.pId,
    required this.phrase,
    required this.lit,
    required this.meaning,
    required this.origin,
    required this.scene,
    required this.sceneTag,
    required this.tags,
    required this.addedAt,
    required this.state,
    required this.due,
    required this.ivl,
    required this.reps,
    required this.lapses,
    required this.examples,
  });

  /// 例句条数（列表展示用）。
  int get exampleCount => examples.length;
}

/// 记录 / 编辑短语的输入。
class PhraseInput {
  final String phrase;
  final String meaning;
  final String lit;
  final String origin;
  final String scene;
  final String sceneTag;
  final String tags;
  final List<PhraseExample> examples;
  const PhraseInput({
    required this.phrase,
    required this.meaning,
    this.lit = '',
    this.origin = '',
    this.scene = '',
    this.sceneTag = '通用',
    this.tags = '',
    this.examples = const [],
  });
}

/// 短语文本或核心释义为空。
class PhraseValidationError implements Exception {
  final String message;
  const PhraseValidationError(this.message);
  @override
  String toString() => 'PhraseValidationError: $message';
}

/// 短语已存在（忽略大小写）。
class PhraseExistsError implements Exception {
  final String phrase;
  const PhraseExistsError(this.phrase);
  @override
  String toString() => 'PhraseExistsError: $phrase';
}

/// 短语未找到。
class PhraseNotFoundError implements Exception {
  final int id;
  const PhraseNotFoundError(this.id);
  @override
  String toString() => 'PhraseNotFoundError: $id';
}

/// tags 规范化：按中英文逗号切分、去空白、去空项、去重，逗号无空格连接。
/// 存 '口语,通用' 形式，便于 `',' || tags || ',' LIKE '%,' || ? || ',%'` 精确筛选。
String _normalizeTags(String raw) {
  final seen = <String>{};
  final out = <String>[];
  for (final part in raw.split(RegExp('[,，]'))) {
    final t = part.trim();
    if (t.isEmpty || !seen.add(t)) continue;
    out.add(t);
  }
  return out.join(',');
}

List<String> _splitTags(String stored) => stored
    .split(',')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

/// 打开短语库连接（独立连接，函数内开、finally 关；启用外键级联）。
Future<Database> _open(String nbPath) async {
  final con = await databaseFactory.openDatabase(p.absolute(nbPath),
      options: OpenDatabaseOptions(singleInstance: false));
  await con.execute('PRAGMA foreign_keys = ON');
  return con;
}

PhraseEntry _rowToEntry(Map<String, Object?> row, List<PhraseExample> examples) {
  return PhraseEntry(
    id: row['id'] as int,
    pId: (row['p_id'] as String?) ?? '',
    phrase: (row['phrase'] as String?) ?? '',
    lit: (row['lit'] as String?) ?? '',
    meaning: (row['meaning'] as String?) ?? '',
    origin: (row['origin'] as String?) ?? '',
    scene: (row['scene'] as String?) ?? '',
    sceneTag: (row['scene_tag'] as String?) ?? '通用',
    tags: _splitTags((row['tags'] as String?) ?? ''),
    addedAt: row['added_at'] as int,
    state: row['state'] as int,
    due: row['due'] as int,
    ivl: row['ivl'] as int,
    reps: row['reps'] as int,
    lapses: row['lapses'] as int,
    examples: examples,
  );
}

/// 批量取例句，按 phrase_id 分组（ordinal 升序）。
Future<Map<int, List<PhraseExample>>> _loadExamples(
    Database con, List<int> ids) async {
  if (ids.isEmpty) return {};
  final placeholders = List.filled(ids.length, '?').join(',');
  final rows = await con.rawQuery(
    'SELECT phrase_id, en, zh FROM phrase_examples '
    'WHERE phrase_id IN ($placeholders) ORDER BY phrase_id, ordinal, id',
    ids,
  );
  final map = <int, List<PhraseExample>>{};
  for (final r in rows) {
    final pid = r['phrase_id'] as int;
    (map[pid] ??= []).add(PhraseExample(
      en: (r['en'] as String?) ?? '',
      zh: (r['zh'] as String?) ?? '',
    ));
  }
  return map;
}

Future<List<PhraseEntry>> _entriesFromRows(
    Database con, List<Map<String, Object?>> rows) async {
  final ids = rows.map((r) => r['id'] as int).toList();
  final exMap = await _loadExamples(con, ids);
  return rows
      .map((r) => _rowToEntry(r, exMap[r['id'] as int] ?? const []))
      .toList();
}

/// 校验输入：短语与核心释义必填。
void _validate(PhraseInput input) {
  if (input.phrase.trim().isEmpty) {
    throw const PhraseValidationError('短语不能为空');
  }
  if (input.meaning.trim().isEmpty) {
    throw const PhraseValidationError('核心释义不能为空');
  }
}

/// 记录一条短语（新状态，无下次到期）。返回内部 id。
///
/// Throws: [PhraseValidationError] 短语/释义为空; [PhraseExistsError] 短语已存在。
Future<int> addPhrase(String nbPath, PhraseInput input) async {
  _validate(input);
  await ensureNotebookDb(nbPath);
  final phrase = input.phrase.trim();
  final con = await _open(nbPath);
  try {
    final dup = await con.rawQuery(
      'SELECT id FROM phrases WHERE phrase = ? COLLATE NOCASE',
      [phrase],
    );
    if (dup.isNotEmpty) throw PhraseExistsError(phrase);

    return await con.transaction((txn) async {
      final id = await txn.rawInsert(
        'INSERT INTO phrases (p_id, phrase, lit, meaning, origin, scene, '
        'scene_tag, tags, added_at, state, due, ivl, reps, lapses) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 0, 0)',
        [
          _genId().toString(),
          phrase,
          input.lit.trim(),
          input.meaning.trim(),
          input.origin.trim(),
          input.scene.trim(),
          input.sceneTag.trim().isEmpty ? '通用' : input.sceneTag.trim(),
          _normalizeTags(input.tags),
          _nowSec(),
          phraseNew,
        ],
      );
      await _insertExamples(txn, id, input.examples);
      return id;
    });
  } finally {
    await con.close();
  }
}

/// 编辑短语（替换例句；不影响复习状态）。id 不存在抛 [PhraseNotFoundError]。
Future<void> updatePhrase(String nbPath, int id, PhraseInput input) async {
  _validate(input);
  await ensureNotebookDb(nbPath);
  final con = await _open(nbPath);
  try {
    await con.transaction((txn) async {
      final exists = await txn.rawQuery('SELECT id FROM phrases WHERE id = ?', [id]);
      if (exists.isEmpty) throw PhraseNotFoundError(id);
      await txn.rawUpdate(
        'UPDATE phrases SET phrase = ?, lit = ?, meaning = ?, origin = ?, '
        'scene = ?, scene_tag = ?, tags = ? WHERE id = ?',
        [
          input.phrase.trim(),
          input.lit.trim(),
          input.meaning.trim(),
          input.origin.trim(),
          input.scene.trim(),
          input.sceneTag.trim().isEmpty ? '通用' : input.sceneTag.trim(),
          _normalizeTags(input.tags),
          id,
        ],
      );
      await txn.rawDelete('DELETE FROM phrase_examples WHERE phrase_id = ?', [id]);
      await _insertExamples(txn, id, input.examples);
    });
  } finally {
    await con.close();
  }
}

Future<void> _insertExamples(
    DatabaseExecutor txn, int phraseId, List<PhraseExample> examples) async {
  var ordinal = 0;
  for (final ex in examples) {
    final en = ex.en.trim();
    if (en.isEmpty) continue; // 空例句跳过
    await txn.rawInsert(
      'INSERT INTO phrase_examples (phrase_id, ordinal, en, zh) VALUES (?, ?, ?, ?)',
      [phraseId, ordinal++, en, ex.zh.trim()],
    );
  }
}

/// 移除短语（级联删例句与复习历史）。返回是否确实删除了。
Future<bool> removePhrase(String nbPath, int id) async {
  await ensureNotebookDb(nbPath);
  final con = await _open(nbPath);
  try {
    final n = await con.rawDelete('DELETE FROM phrases WHERE id = ?', [id]);
    return n > 0;
  } finally {
    await con.close();
  }
}

/// 列出短语（按加入时间倒序），可选按标签筛选。
Future<List<PhraseEntry>> listPhrases(
  String nbPath, {
  int limit = 500,
  String? tag,
}) async {
  await ensureNotebookDb(nbPath);
  final con = await _open(nbPath);
  try {
    var sql = 'SELECT * FROM phrases';
    final args = <Object?>[];
    final t = tag?.trim() ?? '';
    if (t.isNotEmpty) {
      sql += " WHERE ',' || tags || ',' LIKE ?";
      args.add('%,$t,%');
    }
    sql += ' ORDER BY added_at DESC, id DESC LIMIT ?';
    args.add(limit);
    final rows = await con.rawQuery(sql, args);
    return _entriesFromRows(con, rows);
  } finally {
    await con.close();
  }
}

/// 取单条短语（含例句）。不存在返回 null。
Future<PhraseEntry?> getPhrase(String nbPath, int id) async {
  await ensureNotebookDb(nbPath);
  final con = await _open(nbPath);
  try {
    final rows = await con.rawQuery('SELECT * FROM phrases WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final entries = await _entriesFromRows(con, rows);
    return entries.first;
  } finally {
    await con.close();
  }
}

/// 到期短语队列（新短语 + due <= now），与单词队列完全独立。
Future<List<PhraseEntry>> duePhrases(String nbPath, {int limit = 20}) async {
  await ensureNotebookDb(nbPath);
  final now = _nowSec();
  final con = await _open(nbPath);
  try {
    final rows = await con.rawQuery(
      'SELECT * FROM phrases WHERE state = ? OR (state >= ? AND due <= ?) '
      'ORDER BY state ASC, due ASC, id ASC LIMIT ?',
      [phraseNew, phraseLearn, now, limit],
    );
    return _entriesFromRows(con, rows);
  } finally {
    await con.close();
  }
}

/// 对一条短语评分（1-4），推进调度并写入 phrase_review_log。
/// 返回 (nextIvl, nextDue)。
/// 一次短语评分的回执：撤销所需的全部信息（历史行 id + 评分前快照 + 本次结果）。
class PhraseAnswerReceipt {
  final int phraseId;
  final int logId; // phrase_review_log 行 id：撤销时精确删除这一条
  final int ease; // 本次评分：界面据此回退「记得/忘了」计数
  final int prevState;
  final int prevDue;
  final int prevIvl;
  final int prevReps;
  final int prevLapses;
  final int nextIvl;
  final int nextDue;

  const PhraseAnswerReceipt({
    required this.phraseId,
    required this.logId,
    required this.ease,
    required this.prevState,
    required this.prevDue,
    required this.prevIvl,
    required this.prevReps,
    required this.prevLapses,
    required this.nextIvl,
    required this.nextDue,
  });
}

/// 对一条短语打分（1-4），推进调度，返回回执；状态与历史在同一事务内写入。
Future<PhraseAnswerReceipt> answerPhrase(String nbPath, int id, int ease) async {
  await ensureNotebookDb(nbPath);
  final now = _nowSec();
  final con = await _open(nbPath);
  try {
    return await con.transaction((txn) async {
      final rows = await txn.rawQuery(
        'SELECT state, due, ivl, reps, lapses FROM phrases WHERE id = ?',
        [id],
      );
      if (rows.isEmpty) throw PhraseNotFoundError(id);
      final row = rows.first;
      final lastIvl = row['ivl'] as int;
      final (nextIvl, nextDue) = dueTimestamp(lastIvl, ease, now: now);
      final newState = ease >= 2 ? phraseReview : phraseLearn;

      await txn.rawUpdate(
        'UPDATE phrases SET ivl = ?, due = ?, state = ?, reps = reps + 1, '
        'lapses = lapses + ? WHERE id = ?',
        [nextIvl, nextDue, newState, ease < 2 ? 1 : 0, id],
      );
      final logId = await txn.rawInsert(
        'INSERT INTO phrase_review_log (phrase_id, ease, ivl, last_ivl, time, ts) '
        'VALUES (?, ?, ?, ?, 0, ?)',
        [id, ease, nextIvl, lastIvl, now],
      );
      return PhraseAnswerReceipt(
        phraseId: id,
        logId: logId,
        ease: ease,
        prevState: row['state'] as int,
        prevDue: row['due'] as int,
        prevIvl: lastIvl,
        prevReps: row['reps'] as int,
        prevLapses: row['lapses'] as int,
        nextIvl: nextIvl,
        nextDue: nextDue,
      );
    });
  } finally {
    await con.close();
  }
}

/// 撤销一次短语评分：按回执恢复状态并删除该次历史记录（单事务）。
///
/// 只允许撤销该短语**最新**一条历史；回执过期时返回 false 且无副作用。
Future<bool> undoAnswerPhrase(String nbPath, PhraseAnswerReceipt r) async {
  await ensureNotebookDb(nbPath);
  final con = await _open(nbPath);
  try {
    return await con.transaction((txn) async {
      final rows =
          await txn.rawQuery('SELECT id FROM phrases WHERE id = ?', [r.phraseId]);
      if (rows.isEmpty) return false; // 短语已不存在：无副作用
      final latest = (await txn.rawQuery(
              'SELECT MAX(id) AS m FROM phrase_review_log WHERE phrase_id = ?',
              [r.phraseId]))
          .first['m'];
      if (latest is! int || latest != r.logId) return false; // 回执过期
      final deleted = await txn
          .rawDelete('DELETE FROM phrase_review_log WHERE id = ?', [r.logId]);
      if (deleted != 1) return false;
      final updated = await txn.rawUpdate(
        'UPDATE phrases SET ivl = ?, due = ?, state = ?, reps = ?, lapses = ? '
        'WHERE id = ?',
        [
          r.prevIvl,
          r.prevDue,
          r.prevState,
          r.prevReps,
          r.prevLapses,
          r.phraseId,
        ],
      );
      if (updated != 1) {
        throw StateError('撤回短语失败: ${r.phraseId}'); // 抛错→事务回滚
      }
      return true;
    });
  } finally {
    await con.close();
  }
}

/// 短语统计：总数 / 新短语 / 复习中 / 今日到期 / 累计忘记。
Future<Map<String, int>> phraseStats(String nbPath) async {
  await ensureNotebookDb(nbPath);
  final now = _nowSec();
  final con = await _open(nbPath);
  try {
    Future<int> count(String sql, [List<Object?> args = const []]) async =>
        (await con.rawQuery(sql, args)).first.values.first as int;
    return {
      'total': await count('SELECT COUNT(*) FROM phrases'),
      'new': await count('SELECT COUNT(*) FROM phrases WHERE state = ?', [phraseNew]),
      'review': await count('SELECT COUNT(*) FROM phrases WHERE state = ?', [phraseReview]),
      'due': await count(
          'SELECT COUNT(*) FROM phrases WHERE state = ? OR (state >= ? AND due <= ?)',
          [phraseNew, phraseLearn, now]),
      'lapses': await count('SELECT COALESCE(SUM(lapses), 0) FROM phrases'),
    };
  } finally {
    await con.close();
  }
}

/// 现有短语的全部标签（去重、稳定排序），供筛选 chips 使用。
Future<List<String>> phraseTags(String nbPath) async {
  await ensureNotebookDb(nbPath);
  final con = await _open(nbPath);
  try {
    final rows = await con.rawQuery('SELECT tags FROM phrases');
    final set = <String>{};
    for (final r in rows) {
      set.addAll(_splitTags((r['tags'] as String?) ?? ''));
    }
    final list = set.toList()..sort();
    return list;
  } finally {
    await con.close();
  }
}
