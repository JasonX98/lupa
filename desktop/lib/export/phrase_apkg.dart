// Lupa 导出 — 短语集 Anki .apkg（ganki）。与单词导出完全隔离：
// 独立 model / deck / guid，不与生词本混用（guid 前缀 lupa::phrase::）。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ganki/ganki.dart';
import 'package:path/path.dart' as p;

import '../phrase/repo.dart' show PhraseEntry, listPhrases;

// 固定 id（与单词卡 model/deck 不同，保证两类导出在 Anki 中互不干扰）
const int _modelId = 1607392320; // Lupa 短语卡模型
const int _deckId = 2059400111; // Lupa::短语集

const String _css = '''
.card {
    font-family: "Microsoft YaHei", sans-serif;
    font-size: 20px;
    text-align: center;
    color: #333;
    background-color: #fdfdfd;
}
.phrase { font-size: 34px; font-weight: bold; color: #1a1a2e; }
.lit { color: #8a8a8a; font-size: 16px; margin-top: 4px; }
.block { text-align: left; margin: 12px auto 0; max-width: 520px; line-height: 1.55; }
.label { color: #0f766e; font-weight: 600; font-size: 14px; }
.meaning { font-size: 18px; }
.origin { color: #555; font-size: 15px; }
.scene { color: #555; font-size: 15px; }
.ex-item { margin-top: 8px; }
.ex-en { font-size: 16px; }
.ex-zh { color: #777; font-size: 14px; }
''';

final Model _phraseModel = Model(
  modelId: _modelId,
  name: 'Lupa 短语卡',
  css: _css,
  fields: [
    {'name': 'Phrase'},
    {'name': 'Literal'},
    {'name': 'Meaning'},
    {'name': 'Origin'},
    {'name': 'Scene'},
    {'name': 'Tags'},
    {'name': 'Examples'},
  ],
  templates: [
    {
      'name': '短语 -> 释义/典故/例句',
      'qfmt': '<div class="phrase">{{Phrase}}</div>'
          '<div class="lit">{{Literal}}</div>',
      'afmt': '{{FrontSide}}<hr id="answer">'
          '<div class="block">'
          '<div class="meaning">{{Meaning}}</div>'
          '<div class="origin">{{Origin}}</div>'
          '<div class="scene">{{Scene}}</div>'
          '<div class="ex">{{Examples}}</div>'
          '</div>',
    },
  ],
);

/// 导出结果统计。
class PhraseExportReport {
  final int count;
  final String path;
  final int sizeBytes;
  const PhraseExportReport(this.count, this.path, this.sizeBytes);

  @override
  String toString() =>
      'PhraseExportReport(count: $count, path: $path, sizeBytes: $sizeBytes)';
}

/// 同短语稳定 guid（与单词 `lupa::<word>` 前缀不同，Anki 重复导入更新而非新建）。
String phraseStableGuid(String phrase) =>
    sha1.convert(utf8.encode('lupa::phrase::$phrase')).toString().substring(0, 16);

/// 例句格式化：每条 `en<br><span class="ex-zh">zh</span>`，块间空行。
String fmtExamples(PhraseEntry e) {
  final parts = <String>[];
  for (final ex in e.examples) {
    final en = ex.en.trim();
    if (en.isEmpty) continue;
    final zh = ex.zh.trim();
    parts.add('<div class="ex-item"><div class="ex-en">$en</div>'
        '${zh.isEmpty ? '' : '<div class="ex-zh">$zh</div>'}</div>');
  }
  return parts.join('');
}

String _block(String label, String value) =>
    value.trim().isEmpty ? '' : '<div><span class="label">$label</span> ${value.trim()}</div>';

/// 导出短语集为 Anki .apkg（Legacy 2 格式，ganki）。
Future<PhraseExportReport> exportPhraseApkg(
  String nbPath,
  String outPath, {
  int limit = 10000,
  String deckName = 'Lupa::短语集',
}) async {
  final entries = await listPhrases(nbPath, limit: limit);
  final out = File(p.absolute(outPath));
  await out.parent.create(recursive: true);

  final deck = Deck(deckId: _deckId, name: deckName);
  for (final e in entries) {
    deck.addNote(Note(
      model: _phraseModel,
      fields: [
        e.phrase,
        e.lit.trim(),
        e.meaning.trim(),
        _block('典故', e.origin),
        _block('场景', e.scene),
        e.tags.join(' '),
        fmtExamples(e),
      ],
      guid: phraseStableGuid(e.phrase),
      tags: e.tags,
    ));
  }

  final pkg = Package(deck);
  await pkg.writeToFile(out.path);
  return PhraseExportReport(entries.length, out.path, out.lengthSync());
}
