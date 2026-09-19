// 验证 2.2 / v3：sqflite_common_ffi 执行现有 schema.sql，检查表结构创建成功。
// 用法: dart run tool/verify_notebook_db.dart [临时目录]
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/version.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  final home = args.isNotEmpty ? Directory(args[0]) : await Directory.systemTemp.createTemp('lupa_verify_');
  final dbPath = await ensureNotebook(home);
  stdout.writeln('库文件: $dbPath');
  stdout.writeln('已存在? ${File(dbPath).existsSync()}');

  final db = await databaseFactory.openDatabase(dbPath);
  try {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name");
    final names = tables.map((r) => r['name'] as String).toList();
    stdout.writeln('表: $names');

    const expected = [
      'ai_cache', 'audio_cache', 'cards', 'meta', 'notes', 'phonetic_cache',
      'phrase_examples', 'phrase_review_log', 'phrases', 'revlog',
      'word_ai_examples', 'word_ai_groups',
    ];
    final missing = expected.where((t) => !names.contains(t)).toList();
    stdout.writeln('期望 12 表齐全: ${missing.isEmpty ? "PASS" : "FAIL 缺 $missing"}');

    final notesCols = (await db.rawQuery('PRAGMA table_info(notes)'))
        .map((r) => r['name'] as String)
        .toList();
    stdout.writeln('notes 列: $notesCols');

    // ---- ai_cache 的 v3 列（new-DB 路径）----
    final aiCols = (await db.rawQuery('PRAGMA table_info(ai_cache)'))
        .map((r) => r['name'] as String)
        .toList();
    stdout.writeln('ai_cache 列: $aiCols');
    const wantAiCols = [
      'model', 'prompt_tokens', 'completion_tokens', 'cache_hit_tokens',
    ];
    final missAi = wantAiCols.where((c) => !aiCols.contains(c)).toList();
    stdout.writeln('ai_cache v3 列齐全: ${missAi.isEmpty ? "PASS" : "FAIL 缺 $missAi"}');

    final meta = await db.query('meta');
    final metaMap = {for (final r in meta) r['key'] as String: r['value']};
    stdout.writeln('meta: $metaMap');

    // lupa_version 是「最后写入该库的应用版本」，值必须跟随 pubspec 的唯一事实源
    final okMeta = metaMap['schema_version'] == '3' &&
        metaMap['lupa_version'] == lupaVersion;
    stdout.writeln('meta 校验: ${okMeta ? "PASS" : "FAIL"}');

    // ---- AI 缓存统计与清理（空库应全 0）----
    final stats0 = await aiCacheStats(dbPath);
    final okStats0 = stats0.count == 0 &&
        stats0.hits == 0 &&
        stats0.totalTokens == 0 &&
        stats0.invalidCount == 0;
    stdout.writeln('空库 aiCacheStats 全 0: ${okStats0 ? "PASS" : "FAIL"}');

    // 写一条缓存再统计：token 累加、invalid 靠 payload 的 "valid":false 识别
    await db.rawInsert(
        'INSERT INTO ai_cache (cache_key, word, provider, feature, '
        'prompt_version, payload, fetched_at, hit_count, model, '
        'prompt_tokens, completion_tokens, cache_hit_tokens) '
        "VALUES ('deepseek/deepseek-flash:abandon:enrich', 'abandon', "
        "'deepseek/deepseek-flash', 'enrich', 1, ?, 0, 3, "
        "'deepseek-flash', 100, 40, 60)",
        ['{"valid":true,"card":{},"raw":"","model":"deepseek-flash"}']);
    await db.rawInsert(
        'INSERT INTO ai_cache (cache_key, word, provider, feature, '
        'prompt_version, payload, fetched_at, hit_count, model, '
        'prompt_tokens, completion_tokens, cache_hit_tokens) '
        "VALUES ('deepseek/deepseek-flash:record:enrich', 'record', "
        "'deepseek/deepseek-flash', 'enrich', 1, ?, 0, 0, "
        "'deepseek-flash', 200, 10, 0)",
        ['{"valid":false,"reason":"L2","card":{},"raw":"","model":"x"}']);
    final stats1 = await aiCacheStats(dbPath);
    final okStats1 = stats1.count == 2 &&
        stats1.hits == 3 &&
        stats1.promptTokens == 300 &&
        stats1.completionTokens == 50 &&
        stats1.totalTokens == 350 &&
        stats1.invalidCount == 1;
    stdout.writeln(
        'aiCacheStats 计数/命中/token/不合格: ${okStats1 ? "PASS" : "FAIL"}  ($stats1)');

    final cleared = await clearAiCache(dbPath);
    final stats2 = await aiCacheStats(dbPath);
    stdout.writeln('clearAiCache 删 2 条并归零: '
        '${cleared == 2 && stats2.count == 0 ? "PASS" : "FAIL"}');

    // 幂等性：再次调用 ensureNotebook 不重建
    final dbPath2 = await ensureNotebook(home);
    stdout.writeln('幂等 ensureNotebook: ${dbPath2 == dbPath ? "PASS" : "FAIL"}');
  } finally {
    await db.close();
  }

  // ---- ALTER 守卫：列已补但版本号仍为 2 ----
  // 这是 SQLite 没有 ADD COLUMN IF NOT EXISTS 的真实风险面：若迁移中途失败而
  // 版本号未抬，重跑必须能安全跳过已有列，而不是抛 duplicate column name。
  final guard = await Directory.systemTemp.createTemp('lupa_v3guard_');
  final guardPath = p.join(guard.path, 'notebook.sqlite');
  final g = await databaseFactory.openDatabase(guardPath,
      options: OpenDatabaseOptions(singleInstance: false));
  await g.execute(await loadSchemaSql()); // 全量 v3 建库：列都在
  await g.rawInsert(
      "INSERT OR REPLACE INTO meta (key, value) VALUES ('schema_version', '2')");
  await g.close();

  var guardOk = true;
  try {
    await ensureNotebookDb(guardPath); // 重跑 v3 分支
  } catch (e) {
    guardOk = false;
    stdout.writeln('  重跑抛错: $e');
  }
  final gv = await databaseFactory.openDatabase(guardPath,
      options: OpenDatabaseOptions(singleInstance: false));
  final gver =
      (await gv.rawQuery("SELECT value FROM meta WHERE key = 'schema_version'"))
          .first['value'];
  await gv.close();
  stdout.writeln('ALTER 守卫（列已补 + 版本 2，重跑不抛且升到 3）: '
      '${guardOk && gver == '3' ? "PASS" : "FAIL"}');
  await guard.delete(recursive: true);

  if (args.isEmpty) await home.delete(recursive: true);
  stdout.writeln('DONE');
}
