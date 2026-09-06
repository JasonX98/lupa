// Lupa 导出 — CSV（UTF-8 带 BOM，Excel 直接打开不乱码）。
// 与 Python 版 src/lupa/export/csv.py 对齐：表头 7 列；exchange 的 \x1f 分隔替换为 " | "。
import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;

import '../notebook/repo.dart' show fieldSep, listWords;

const List<String> csvHeader = [
  'word', 'phonetic', 'translation', 'definition', 'exchange', 'tags', 'added_at',
];

/// 导出结果统计。
class CsvExportReport {
  final int count;
  final String path;
  final int sizeBytes;
  const CsvExportReport(this.count, this.path, this.sizeBytes);

  @override
  String toString() => 'CsvExportReport(count: $count, path: $path, sizeBytes: $sizeBytes)';
}

/// 导出生词本为 UTF-8（带 BOM）CSV。
Future<CsvExportReport> exportCsv(
  String nbPath,
  String outPath, {
  int limit = 10000,
}) async {
  final entries = await listWords(nbPath, limit: limit, includeSuspended: true);
  final out = File(p.absolute(outPath));
  await out.parent.create(recursive: true);

  // utf-8-sig：csv 包 addBom 写 UTF-8 BOM（Excel 直接打开不乱码）
  final csv = Csv(addBom: true);
  final rows = <List<Object?>>[csvHeader];
  for (final e in entries) {
    rows.add([
      e.word,
      e.phonetic,
      e.translation,
      e.definition,
      e.exchange.replaceAll(fieldSep, ' | '),
      e.tags,
      e.addedAt,
    ]);
  }
  await out.writeAsBytes(utf8.encode(csv.encode(rows)));
  return CsvExportReport(entries.length, out.path, out.lengthSync());
}
