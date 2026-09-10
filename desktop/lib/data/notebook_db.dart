// Lupa 数据层 — notebook 库初始化与数据目录解析。
//
// 与 Python 版对齐：
// - 目录约定同 src/lupa/cli.py 的 data_home()：LUPA_HOME 环境变量优先，默认 <exe>/lupa_data
// - ensureNotebook 同 src/lupa/notebook/repo.py 的 ensure_notebook()：库文件存在则跳过（幂等），否则执行 schema.sql 建表
// - schema.sql 复制自 src/lupa/notebook/schema.sql（两份必须保持同步；此处为 Dart 侧唯一执行源）
// - 数据目录唯一解析见 lib/data/data_home.dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data_home.dart';

/// 初始化 sqflite ffi（幂等：只在首次生效，重复调用不再重设全局工厂——
/// 否则 sqflite 每次都会打 "changing sqflite default factory" 告警）。
bool _dbFactoryInited = false;
void initDatabaseFactory() {
  if (_dbFactoryInited) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _dbFactoryInited = true;
}

/// 词库文件路径（dict.sqlite，只读）。绝对路径（sqflite ffi 不接受相对路径）。
String dictDbPath([Directory? home]) =>
    p.absolute(p.join((home ?? dataHome()).path, 'dict.sqlite'));

/// 生词本文件路径（notebook.sqlite）。绝对路径。
String notebookDbPath([Directory? home]) =>
    p.absolute(p.join((home ?? dataHome()).path, 'notebook.sqlite'));

/// 读取 schema.sql：开发/验证期从仓库 `lib/data/schema.sql` 读；
/// 打包分发后从 exe 同目录 `data/schema.sql` 读（正式 asset 化在 UI 任务处理）。
Future<String> loadSchemaSql() async {
  final candidates = [
    File('lib/data/schema.sql'),
    File(p.join(p.dirname(Platform.resolvedExecutable), 'data', 'schema.sql')),
  ];
  for (final f in candidates) {
    if (f.existsSync()) return f.readAsString();
  }
  throw FileSystemException('schema.sql 未找到', candidates.map((e) => e.path).join('; '));
}

/// 已迁移（或新建）过的库绝对路径缓存：避免每次 ensureNotebookDb 都开库查版本。
final Set<String> _migrated = <String>{};

/// 短语表 DDL 区块标记（与 lib/data/schema.sql 中一致，勿改）。
const String _phraseBeginMarker = '-- >>> PHRASE_TABLES_V2 >>>';
const String _phraseEndMarker = '-- <<< PHRASE_TABLES_V2 <<<';

/// 从 schema.sql 提取短语三表 DDL 区块（旧库迁移用；schema.sql 为单一事实源）。
Future<String> loadPhraseSchemaSql() async {
  final sql = await loadSchemaSql();
  final begin = sql.indexOf(_phraseBeginMarker);
  final end = sql.indexOf(_phraseEndMarker);
  if (begin < 0 || end < 0 || end <= begin) {
    throw StateError('schema.sql 缺少短语表标记 $_phraseBeginMarker / $_phraseEndMarker');
  }
  return sql.substring(begin + _phraseBeginMarker.length, end);
}

/// 确保生词本库存在（幂等：已存在则跳过，与 Python 版一致）。给定库文件完整路径。
///
/// 旧库（schema_version < 2）在此补齐短语三表并升级版本号；迁移为增量、幂等
/// （CREATE TABLE IF NOT EXISTS），不影响单词 notes/cards/revlog。
Future<String> ensureNotebookDb(String dbPath) async {
  initDatabaseFactory();
  final file = File(p.absolute(dbPath));
  await file.parent.create(recursive: true);
  final abs = file.path;

  if (!file.existsSync()) {
    final sql = await loadSchemaSql();
    final db = await databaseFactory.openDatabase(abs,
        options: OpenDatabaseOptions(singleInstance: false));
    try {
      await db.execute(sql);
    } finally {
      await db.close();
    }
    _migrated.add(abs);
    return abs;
  }

  if (_migrated.contains(abs)) return abs;

  // 旧库：schema_version < 2 则补齐短语三表并升级版本号
  final db = await databaseFactory.openDatabase(abs,
      options: OpenDatabaseOptions(singleInstance: false));
  try {
    final rows = await db.rawQuery(
        "SELECT value FROM meta WHERE key = 'schema_version'");
    final version = rows.isEmpty
        ? 0
        : int.tryParse((rows.first['value'] as String?) ?? '') ?? 0;
    if (version < 2) {
      await db.execute(await loadPhraseSchemaSql());
      await db.rawInsert("INSERT OR REPLACE INTO meta (key, value) "
          "VALUES ('schema_version', '2')");
    }
  } finally {
    await db.close();
  }
  _migrated.add(abs);
  return abs;
}

/// 确保默认数据目录下的生词本库存在。返回库路径。
Future<String> ensureNotebook([Directory? home]) async =>
    ensureNotebookDb(notebookDbPath(home));

/// 打开生词本库（独立连接，函数内开、finally 关；与 repo._openNb 一致）。
Future<Database> _open(String dbPath) async {
  initDatabaseFactory();
  return databaseFactory.openDatabase(p.absolute(dbPath),
      options: OpenDatabaseOptions(singleInstance: false));
}

/// 媒体缓存统计（settings 发音组展示用）。音标表无 size_bytes，仅条数/命中。
class MediaCacheStats {
  final int audioCount;
  final int audioBytes;
  final int audioHits;
  final int phoneticCount;
  final int phoneticHits;
  const MediaCacheStats({
    required this.audioCount,
    required this.audioBytes,
    required this.audioHits,
    required this.phoneticCount,
    required this.phoneticHits,
  });
  int get totalCount => audioCount + phoneticCount;
  int get totalHits => audioHits + phoneticHits;
  int get totalBytes => audioBytes; // 目前仅音频表记录体积
}

/// 统计 media_cache（audio_cache + phonetic_cache）条数 / 体积 / 命中。
Future<MediaCacheStats> mediaCacheStats(String nbPath) async {
  await ensureNotebookDb(nbPath);
  final con = await _open(nbPath);
  try {
    final a = (await con.rawQuery(
        'SELECT COUNT(*) c, COALESCE(SUM(size_bytes),0) b, '
        'COALESCE(SUM(hit_count),0) h FROM audio_cache'))
        .first;
    final p = (await con.rawQuery(
        'SELECT COUNT(*) c, COALESCE(SUM(hit_count),0) h FROM phonetic_cache'))
        .first;
    return MediaCacheStats(
      audioCount: a['c'] as int,
      audioBytes: a['b'] as int,
      audioHits: a['h'] as int,
      phoneticCount: p['c'] as int,
      phoneticHits: p['h'] as int,
    );
  } finally {
    await con.close();
  }
}

/// 清空 media_cache（audio_cache + phonetic_cache）。返回删除总条数。
Future<int> clearMediaCache(String nbPath) async {
  await ensureNotebookDb(nbPath);
  final con = await _open(nbPath);
  try {
    final a = await con.rawDelete('DELETE FROM audio_cache');
    final p = await con.rawDelete('DELETE FROM phonetic_cache');
    return a + p;
  } finally {
    await con.close();
  }
}
