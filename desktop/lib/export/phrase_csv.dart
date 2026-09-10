// Lupa 导出 — 短语集 CSV（UTF-8 带 BOM，Excel 直接打开不乱码）。
// 与单词 CSV 完全分离：独立列集合，含全部短语字段与例句。
import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;

import '../phrase/repo.dart' show PhraseEntry, listPhrases;

const List<String> phraseCsvHeader = [
  'phrase', 'lit', 'meaning', 'origin', 'scene', 'scene_tag', 'tags',
  'added_at', 'examples',
];

/// 导出结果统计。
class PhraseCsvExportReport {
  final int count;
  final String path;
  final int sizeBytes;
  const PhraseCsvExportReport(this.count, this.path, this.sizeBytes);

  @override
  String toString() =>
      'PhraseCsvExportReport(count: $count, path: $path, sizeBytes: $sizeBytes)';
}

/// 例句拼成单列：每条 `en — zh`，多条以换行分隔（CSV 会正确加引号）。
String _fmtExamples(PhraseEntry e) {
  final lines = <String>[];
  for (final ex in e.examples) {
    final en = ex.en.trim();
    if (en.isEmpty) continue;
    final zh = ex.zh.trim();
    lines.add(zh.isEmpty ? en : '$en — $zh');
  }
  return lines.join('\n');
}

/// 导出短语集为 UTF-8（带 BOM）CSV。
Future<PhraseCsvExportReport> exportPhraseCsv(
  String nbPath,
  String outPath, {
  int limit = 10000,
}) async {
  final entries = await listPhrases(nbPath, limit: limit);
  final out = File(p.absolute(outPath));
  await out.parent.create(recursive: true);

  final csv = Csv(addBom: true);
  final rows = <List<Object?>>[phraseCsvHeader];
  for (final e in entries) {
    rows.add([
      e.phrase,
      e.lit,
      e.meaning,
      e.origin,
      e.scene,
      e.sceneTag,
      e.tags.join(', '),
      e.addedAt,
      _fmtExamples(e),
    ]);
  }
  await out.writeAsBytes(utf8.encode(csv.encode(rows)));
  return PhraseCsvExportReport(entries.length, out.path, out.lengthSync());
}
