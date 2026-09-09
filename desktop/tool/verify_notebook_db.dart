// 验证 2.2：sqflite_common_ffi 执行现有 schema.sql，检查表结构创建成功。
// 用法: dart run tool/verify_notebook_db.dart [临时目录]
import 'dart:io';

import 'package:lupa/data/notebook_db.dart';
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
      'ai_cache', 'audio_cache', 'cards', 'meta', 'notes', 'phonetic_cache', 'revlog',
    ];
    final missing = expected.where((t) => !names.contains(t)).toList();
    stdout.writeln('期望 7 表齐全: ${missing.isEmpty ? "PASS" : "FAIL 缺 $missing"}');

    final notesCols = (await db.rawQuery('PRAGMA table_info(notes)'))
        .map((r) => r['name'] as String)
        .toList();
    stdout.writeln('notes 列: $notesCols');

    final meta = await db.query('meta');
    final metaMap = {for (final r in meta) r['key'] as String: r['value']};
    stdout.writeln('meta: $metaMap');

    final okMeta = metaMap['schema_version'] == '1' && metaMap['lupa_version'] == '0.2.0';
    stdout.writeln('meta 校验: ${okMeta ? "PASS" : "FAIL"}');

    // 幂等性：再次调用 ensureNotebook 不重建（与 Python 版一致）
    final dbPath2 = await ensureNotebook(home);
    stdout.writeln('幂等 ensureNotebook: ${dbPath2 == dbPath ? "PASS" : "FAIL"}');
  } finally {
    await db.close();
  }
  if (args.isEmpty) await home.delete(recursive: true);
  stdout.writeln('DONE');
}
