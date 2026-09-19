// Lupa 导出 — Anki .apkg（ganki）。
// 固定 model/deck id、稳定 guid、6 字段模板；重复导出在 Anki 中合并而非重复建卡。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ganki/ganki.dart';
import 'package:path/path.dart' as p;

import '../notebook/repo.dart' show NotebookEntry, listWords;

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
.ai { margin-top: 14px; }
.ai-group { margin-top: 10px; }
.ai-label { font-weight: bold; color: #1a5fb4; }
.ai-gloss { color: #444; }
.ai-ex { margin: 4px 0 0 8px; }
.ai-ex .zh { color: #777; font-size: 17px; }
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
    // v3 新增：AI 例句与搭配（见 specs/export 的「Anki apkg 导出」）
    {'name': 'Examples'},
    {'name': 'Collocations'},
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
          '<div class="ai">{{Examples}}{{Collocations}}</div>'
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

/// 同词稳定 guid：Anki 重复导入时更新而非重复建卡。
String stableGuid(String word) =>
    sha1.convert(utf8.encode('lupa::$word')).toString().substring(0, 16);

/// 词形变化格式化：`d:xx/p:xx` -> 中文标签 + <br> 分行。
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

/// HTML 转义（AI 例句里可能出现 `<`、`&` 等字符）。
String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// AI 例句渲染为 HTML 列表：按词性分组，每组一个 `<ul>`。
///
/// 降级补齐（label 为空的组）用「通用例句」标题 —— 与界面一致。
String fmtAiExamples(NotebookEntry e) {
  if (!e.hasAi) return '';
  final b = StringBuffer();
  final senses = e.aiSenses;
  final onlyPlain = senses.isNotEmpty && senses.every((g) => g.label.trim().isEmpty);
  if (senses.isNotEmpty) {
    b.write('<div class="ai-group">');
    if (onlyPlain) b.write('<div class="ai-label">通用例句</div>');
    for (final g in senses) {
      if (!onlyPlain) {
        b.write('<div class="ai-label">${_esc(g.label)}</div>');
      }
      if (g.gloss.trim().isNotEmpty) {
        b.write('<div class="ai-gloss">${_esc(g.gloss)}</div>');
      }
      b.write('<ul>');
      for (final x in g.examples) {
        b.write('<li><span class="en">${_esc(x.en)}</span>');
        if (x.zh.trim().isNotEmpty) {
          b.write('<div class="zh">${_esc(x.zh)}</div>');
        }
        b.write('</li>');
      }
      b.write('</ul>');
    }
    b.write('</div>');
  }
  return b.toString();
}

/// AI 搭配渲染为 HTML：搭配 + 释义 + 例句列表。
String fmtAiCollocations(NotebookEntry e) {
  final cols = e.aiCollocations;
  if (cols.isEmpty) return '';
  final b = StringBuffer('<div class="ai-group">');
  for (final g in cols) {
    b.write('<div class="ai-label">${_esc(g.label)}</div>');
    if (g.gloss.trim().isNotEmpty) {
      b.write('<div class="ai-gloss">${_esc(g.gloss)}</div>');
    }
    if (g.examples.isNotEmpty) {
      b.write('<ul>');
      for (final x in g.examples) {
        b.write('<li><span class="en">${_esc(x.en)}</span>');
        if (x.zh.trim().isNotEmpty) {
          b.write('<div class="zh">${_esc(x.zh)}</div>');
        }
        b.write('</li>');
      }
      b.write('</ul>');
    }
  }
  b.write('</div>');
  return b.toString();
}

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
        fmtAiExamples(e),
        fmtAiCollocations(e),
      ],
      guid: stableGuid(e.word),
      tags: e.tags.isEmpty ? [] : e.tags.split(' '),
    ));
  }

  final pkg = Package(deck);
  await pkg.writeToFile(out.path);
  return ExportReport(entries.length, out.path, out.lengthSync());
}
