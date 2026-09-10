// ganki apkg spike — 验证 ganki 能否用 Lupa 模型生成 Anki 可导入的 .apkg
// 复用 lib/export/apkg.dart 的固定 model / deck / 稳定 guid 逻辑。
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ganki/ganki.dart';

// ---- 与 Lupa export/apkg.py 对齐 ----
const int modelId = 1607392319;
const int deckId = 2059400110;
const String modelName = 'Lupa 单词卡';
const String deckName = 'Lupa::生词本';

const String css = '''
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

final Model lupaModel = Model(
  modelId: modelId,
  name: modelName,
  css: css,
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

/// 稳定 guid：与 Lupa `_stable_guid` 一致：sha1('lupa::<word>') 前 16 位
String stableGuid(String word) {
  final digest = sha1.convert(utf8.encode('lupa::$word')).toString();
  return digest.substring(0, 16);
}

/// 词形变化格式化：把 ECDICT 的 `d:abandoned/p:...` 转成友好中文标签（同 Python `_fmt_exchange`）
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
    if (value.isNotEmpty) {
      parts.add('${labels[key] ?? key} $value');
    }
  }
  return parts.join('<br>');
}

Future<void> main(List<String> args) async {
  final outPath = args.isNotEmpty ? args[0] : 'lupa-spike.apkg';
  final deck = Deck(deckId: deckId, name: deckName);

  final words = [
    ['abandon', '/əˈbændən/', 'v. 放弃；抛弃', 'to give up completely', 'd:abandoned/p:abandoned/i:abandoning/3:abandons/s:abandons', 'cet6 ky'],
    ['perceive', '/pəˈsiːv/', 'v. 察觉；感知', 'to become aware of', 'd:perceived/p:perceived/i:perceiving/3:perceives', 'cet6 ky'],
  ];

  for (final f in words) {
    deck.addNote(Note(
      model: lupaModel,
      fields: [f[0], f[1], f[2], f[3], fmtExchange(f[4]), f[5]],
      guid: stableGuid(f[0]),
    ));
  }

  final pkg = Package(deck);
  await pkg.writeToFile(outPath);

  final f = File(outPath);
  stdout.writeln('Wrote ${f.path} (${f.lengthSync()} bytes)');
  stdout.writeln('modelId=$modelId deckId=$deckId guid(abandon)=${stableGuid('abandon')}');
}
