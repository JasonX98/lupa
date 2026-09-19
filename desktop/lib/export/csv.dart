// Lupa 导出 — CSV（UTF-8 带 BOM，Excel 直接打开不乱码）。
// 表头 7 列；exchange 的 \x1f 分隔替换为 " | "。
import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;

import '../notebook/repo.dart' show NotebookEntry, fieldSep, listWords;

const List<String> csvHeader = [
  'word', 'phonetic', 'translation', 'definition', 'exchange', 'tags', 'added_at',
  // v3 新增：AI 例句与搭配。**追加在末尾**，前 7 列的位置与含义不变
  //（已有下游脚本依赖列序，见 specs/export 的「AI 列追加在末尾」）。
  'examples', 'collocations',
];

/// AI 例句的单元格文本：按词性分组，en 与 zh 之间用**换行 + 缩进**。
///
/// 不用 `\t` 或 `|` 之类的可见分隔符：例句正文里真的可能出现它们，而换行是
/// 现成的先例（`definition` 本身就是多行文本，`csv` 包会自动加引号）。
/// 零分隔符字符 = 零转义风险。
String fmtExamplesCell(NotebookEntry e) {
  if (!e.hasAi) return '';
  final lines = <String>[];
  final senses = e.aiSenses;
  final onlyPlain =
      senses.isNotEmpty && senses.every((g) => g.label.trim().isEmpty);
  for (final g in senses) {
    if (!onlyPlain && g.label.trim().isNotEmpty) {
      lines.add(g.label.trim());
    } else if (onlyPlain && lines.isEmpty) {
      lines.add('通用例句');
    }
    for (final x in g.examples) {
      lines.add('    ${x.en}');
      if (x.zh.trim().isNotEmpty) lines.add('        ${x.zh}');
    }
  }
  return lines.join('\n');
}

/// AI 搭配的单元格文本：搭配 | 释义 + 缩进例句。
String fmtCollocationsCell(NotebookEntry e) {
  final cols = e.aiCollocations;
  if (cols.isEmpty) return '';
  final lines = <String>[];
  for (final g in cols) {
    final head = g.gloss.trim().isEmpty
        ? g.label.trim()
        : '${g.label.trim()} | ${g.gloss.trim()}';
    lines.add(head);
    for (final x in g.examples) {
      lines.add('    ${x.en}');
      if (x.zh.trim().isNotEmpty) lines.add('        ${x.zh}');
    }
  }
  return lines.join('\n');
}

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
      fmtExamplesCell(e),
      fmtCollocationsCell(e),
    ]);
  }
  await out.writeAsBytes(utf8.encode(csv.encode(rows)));
  return CsvExportReport(entries.length, out.path, out.lengthSync());
}
