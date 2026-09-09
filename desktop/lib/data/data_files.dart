// Lupa 数据文件操作 — 备份生词本 / 复制数据目录（settings 数据组，头less 可测）。
// 纯 Dart IO，不读 stdin / 不写 stdout。
import 'dart:io';

import 'package:path/path.dart' as p;

/// 备份生词本：把 notebook.sqlite 复制为带时间戳的备份文件（默认存同一数据目录）。
/// 返回备份文件路径。
Future<String> backupNotebook(String nbPath) async {
  final src = File(p.absolute(nbPath));
  if (!src.existsSync()) {
    throw FileSystemException('生词本库不存在', src.path);
  }
  final dir = src.parent;
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${now.year}${two(now.month)}${two(now.day)}'
      '-${two(now.hour)}${two(now.minute)}${two(now.second)}';
  final dst = File(p.join(dir.path, 'lupa-backup-$stamp.sqlite'));
  await File(src.path).copy(dst.path);
  return dst.path;
}

/// 复制数据目录：把 notebook.sqlite + dict.sqlite + exports/ 复制到 dst。
/// 只复制已存在的项；目标目录按需创建。用于"复制现有数据"式切换。
Future<void> copyDataDir(String src, String dst) async {
  final srcDir = Directory(p.absolute(src));
  final dstDir = Directory(p.absolute(dst));
  dstDir.createSync(recursive: true);
  if (!srcDir.existsSync()) {
    throw FileSystemException('源数据目录不存在', srcDir.path);
  }

  _copyFileIfExists(p.join(srcDir.path, 'notebook.sqlite'),
      p.join(dstDir.path, 'notebook.sqlite'));
  _copyFileIfExists(
      p.join(srcDir.path, 'dict.sqlite'), p.join(dstDir.path, 'dict.sqlite'));

  final srcExports = Directory(p.join(srcDir.path, 'exports'));
  if (srcExports.existsSync()) {
    final dstExports = Directory(p.join(dstDir.path, 'exports'));
    dstExports.createSync(recursive: true);
    await _copyTree(srcExports, dstExports);
  }
}

void _copyFileIfExists(String src, String dst) {
  final f = File(src);
  if (f.existsSync()) f.copySync(dst);
}

Future<void> _copyTree(Directory src, Directory dst) async {
  for (final entity in src.listSync(recursive: true)) {
    if (entity is File) {
      final rel = p.relative(entity.path, from: src.path);
      final target = File(p.join(dst.path, rel));
      target.parent.createSync(recursive: true);
      await entity.copy(target.path);
    }
  }
}
