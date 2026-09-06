// Lupa 数据层 — notebook 库初始化与数据目录解析。
//
// 与 Python 版对齐：
// - 目录约定同 src/lupa/cli.py 的 data_home()：LUPA_HOME 环境变量优先，默认 ~/.lupa
// - ensureNotebook 同 src/lupa/notebook/repo.py 的 ensure_notebook()：库文件存在则跳过（幂等），否则执行 schema.sql 建表
// - schema.sql 复制自 src/lupa/notebook/schema.sql（两份必须保持同步；此处为 Dart 侧唯一执行源）
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 初始化 sqflite ffi（幂等：只在首次生效，重复调用不再重设全局工厂——
/// 否则 sqflite 每次都会打 "changing sqflite default factory" 告警）。
bool _dbFactoryInited = false;
void initDatabaseFactory() {
  if (_dbFactoryInited) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _dbFactoryInited = true;
}

/// 数据目录：LUPA_HOME 环境变量优先，默认 ~/.lupa。返回绝对路径（sqflite ffi 不接受相对路径）。
Directory dataHome() {
  final env = Platform.environment['LUPA_HOME'];
  if (env != null && env.isNotEmpty) return Directory(p.absolute(env));
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.';
  return Directory(p.absolute(p.join(home, '.lupa')));
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

/// 确保生词本库存在（幂等：已存在则跳过，与 Python 版一致）。给定库文件完整路径。
Future<String> ensureNotebookDb(String dbPath) async {
  initDatabaseFactory();
  final file = File(p.absolute(dbPath));
  await file.parent.create(recursive: true);
  if (file.existsSync()) return file.path;

  final sql = await loadSchemaSql();
  final db = await databaseFactory.openDatabase(file.path,
      options: OpenDatabaseOptions(singleInstance: false));
  try {
    await db.execute(sql);
  } finally {
    await db.close();
  }
  return file.path;
}

/// 确保默认数据目录下的生词本库存在。返回库路径。
Future<String> ensureNotebook([Directory? home]) async =>
    ensureNotebookDb(notebookDbPath(home));
