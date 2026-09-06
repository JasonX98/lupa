// Lupa 导出 — Anki .apkg（ganki）。
// 与 Python 版 src/lupa/export/apkg.py 对齐：固定 model/deck id、稳定 guid、6 字段模板。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ganki/ganki.dart';
import 'package:path/path.dart' as p;

import '../notebook/repo.dart' show listWords;

// 固定 id（随机但持久，保证多次导出在 Anki 中合并而非重复建 deck）
const int _modelId = 1607392319; // Lupa 单词卡模型
const int _deckId = 2059400110; // Lupa::生词本

const String _css = '''
.card {
    font-family: "Microsoft YaHei", sans-serif;
    font-size: 22px;
    text-align: center;
    color: #333;
    background-color: #fdfdfd;
}
.word { font-size: 40px; font-weight: bold; color: #1a1a2e; }
.phonetic { color: #666; font-size: 20px; margin-top: 8px; }
.answer-block { text-align: left; margin: 16px auto 0; max-width: 480px; }
.meaning { margin: 6px 0; line-height: 1.55; }
.en { color: #555; font-style: italic; font-size: 18px; }
.exchange { color: #8a4fbd; font-size: 17px; margin-top: 12px; }
''';

final Model _lupaModel = Model(
  modelId: _modelId,
  name: 'Lupa 单词卡',
  css: _css,
  fields: [
    {'name': 'Word'},
    {'name': 'Phonetic'},
    {'name': 'Translation'},
    {'name': 'Definition'},
    {'name': 'Exchange'},
    {'name': 'Tags'},
  ],
  templates: [
    {
      'name': '单词 -> 释义',
      'qfmt': '<div class="word">{{Word}}</div>',
      'afmt': '{{FrontSide}}<hr id="answer">'
          '<div class="answer-block">'
          '<div class="phonetic">{{Phonetic}}</div>'
          '<div class="meaning">{{Translation}}</div>'
          '<div class="en">{{Definition}}</div>'
          '<div class="exchange">{{Exchange}}</div>'
          '</div>',
    },
  ],
);

/// 导出结果统计。
class ExportReport {
  final int count;
  final String path;
  final int sizeBytes;
  const ExportReport(this.count, this.path, this.sizeBytes);

  @override
  String toString() => 'ExportReport(count: $count, path: $path, sizeBytes: $sizeBytes)';
}

/// 同词稳定 guid：Anki 重复导入时更新而非重复建卡（与 Python 版一致）。
String stableGuid(String word) =>
    sha1.convert(utf8.encode('lupa::$word')).toString().substring(0, 16);

/// 词形变化格式化：`d:xx/p:xx` -> 中文标签 + <br> 分行（与 Python `_fmt_exchange` 一致）。
String fmtExchange(String exchange) {
  if (exchange.isEmpty) return '';
  const labels = {
    'd': '过去式', 'p': '过去分词', 'i': '现在分词', '3': '三单',
    's': '复数', 'r': '比较级', 't': '最高级',
  };
  final parts = <String>[];
  for (final seg in exchange.split('/')) {
    final idx = seg.indexOf(':');
    if (idx < 0) continue;
    final key = seg.substring(0, idx);
    final value = seg.substring(idx + 1);
    if (value.isNotEmpty) parts.add('${labels[key] ?? key} $value');
  }
  return parts.join('<br>');
}

String _fmtPhonetic(String phonetic) => phonetic.trim().isEmpty ? '' : '/$phonetic/';

/// 导出生词本为 Anki .apkg（Legacy 2 格式，ganki）。
Future<ExportReport> exportApkg(
  String nbPath,
  String outPath, {
  int limit = 10000,
  String deckName = 'Lupa::生词本',
}) async {
  final entries = await listWords(nbPath, limit: limit, includeSuspended: true);
  final out = File(p.absolute(outPath));
  await out.parent.create(recursive: true);

  final deck = Deck(deckId: _deckId, name: deckName);
  for (final e in entries) {
    deck.addNote(Note(
      model: _lupaModel,
      fields: [
        e.word,
        _fmtPhonetic(e.phonetic),
        (e.translation).trim(),
        (e.definition).trim().replaceAll('\n', '<br>'),
        fmtExchange(e.exchange),
        e.tags,
      ],
      guid: stableGuid(e.word),
      tags: e.tags.isEmpty ? [] : e.tags.split(' '),
    ));
  }

  final pkg = Package(deck);
  await pkg.writeToFile(out.path);
  return ExportReport(entries.length, out.path, out.lengthSync());
}
