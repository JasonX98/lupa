// Lupa 数据目录解析 — 唯一来源（portable-data-dir change）。
//
// 解析顺序：
//   1. LUPA_HOME 环境变量（若设置且非空）→ 用它（与 Python CLI 共享数据）
//   2. 否则 → <可执行文件所在目录>/lupa_data（便携默认，解压即用）
//
// 不再回退到 ~/.lupa。schema.sql 是独立模板，不走本目录（见 notebook_db.dart loadSchemaSql）。
import 'dart:io';

import 'package:path/path.dart' as p;

/// 数据目录。返回绝对路径（sqflite ffi 不接受相对路径）。
Directory dataHome() {
  final env = Platform.environment['LUPA_HOME'];
  if (env != null && env.isNotEmpty) return Directory(p.absolute(env));
  final exeDir = p.dirname(Platform.resolvedExecutable);
  return Directory(p.absolute(p.join(exeDir, 'lupa_data')));
}
