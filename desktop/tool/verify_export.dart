// 验证 6.1 / 6.2：apkg 与 csv 导出。
// 用法: LUPA_HOME=../data dart run tool/verify_export.dart
import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:lupa/ai/card.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/export/apkg.dart';
import 'package:lupa/export/csv.dart';
import 'package:lupa/notebook/repo.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

var failures = 0;

void check(String name, bool ok, {Object? detail}) {
  stdout.writeln('$name: ${ok ? "PASS" : "FAIL"}${detail == null ? "" : "  ($detail)"}');
  if (!ok) failures++;
}

Future<void> main(List<String> args) async {
  final home = dataHome();
  final dictDb = dictDbPath(home);
  final tmp = await Directory.systemTemp.createTemp('lupa_export_verify_');
  final nbPath = '${tmp.path}/notebook.sqlite';

  // 准备生词本：3 个词（含 tags）
  await addWord(nbPath, dictDb, 'abandon', 'cet6 ky');
  await addWord(nbPath, dictDb, 'perceive', '');
  await addWord(nbPath, dictDb, 'serene', 'test');

  // ---------- 6.1 apkg ----------
  final report = await exportApkg(nbPath, '${tmp.path}/out.apkg');
  check('6.1 apkg 写盘且非空', report.count == 3 && report.sizeBytes > 1000,
      detail: report);
  check('6.1 apkg guid 稳定 (abandon)',
      stableGuid('abandon') == 'c82559e49d41d9a0', detail: stableGuid('abandon'));

  final zip = await _checkApkg('${tmp.path}/out.apkg');
  check('6.1 apkg 含 collection.anki2 + media', zip.ok, detail: zip.desc);
  check('6.1 apkg notes=3', zip.noteCount == 3, detail: zip.noteCount);
  check('6.1 apkg exchange 中文标签',
      zip.exchange.contains('过去式 abandoned'), detail: zip.exchange);
  check('6.1 apkg phonetic 带斜线', zip.phonetic.startsWith('/'), detail: zip.phonetic);

  // ---------- 6.2 csv ----------
  final csvReport = await exportCsv(nbPath, '${tmp.path}/out.csv');
  check('6.2 csv 写盘 count=3', csvReport.count == 3, detail: csvReport);
  final bytes = File(csvReport.path).readAsBytesSync();
  check('6.2 csv UTF-8 BOM 开头',
      bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF);
  final text = utf8.decode(bytes.sublist(3));
  final decoded = Csv().decode(text);
  check('6.2 csv 解析 表头+3 行',
      decoded.length == 4 && decoded[0][0] == 'word' && decoded[1][0] == 'abandon',
      detail: decoded.length);
  check('6.2 csv 含 tags', text.contains('cet6 ky'));

  // ---------- 6.3 AI 内容落库后导出（apkg 8 字段 / csv 9 列）----------
  // 造一张含 AI 例句与搭配的卡（不经网络，直接写旁表）
  final aiCard = parseAiCard(json.encode({
    'word': 'limerence',
    'canonical': 'limerence',
    'is_known_word': true,
    'phonetic': 'ˈlɪmərəns',
    'translation': 'n. 痴恋',
    'definition': 'the state of being infatuated',
    'senses': [
      {
        'pos': 'n.',
        'gloss': '痴恋',
        'examples': [
          {'en': 'He was in limerence & happy.', 'zh': '他陷入痴恋。'}
        ]
      }
    ],
    'collocations': [
      {
        'phrase': 'pure limerence',
        'gloss': '纯粹痴恋',
        'examples': [
          {'en': 'It was pure limerence.', 'zh': '纯属痴恋。'}
        ]
      }
    ],
  })).card!;
  await addAiWord(nbPath, 'limerence', aiCard, 'ai',
      provider: 'deepseek/deepseek-flash', promptVersion: 1);

  final report2 = await exportApkg(nbPath, '${tmp.path}/out2.apkg');
  check('6.3 apkg 导出 4 张卡', report2.count == 4, detail: report2.count);

  final zip2 = await _checkApkg('${tmp.path}/out2.apkg');
  check('6.3 apkg model 为 8 字段', zip2.fieldCount == 8, detail: zip2.fieldCount);
  check('6.3 apkg 字段名含 Examples/Collocations',
      zip2.fieldNames.contains('Examples') &&
          zip2.fieldNames.contains('Collocations'),
      detail: zip2.fieldNames);
  check('6.3 apkg AI 例句渲染为列表',
      zip2.aiExamples.contains('<li>') &&
          zip2.aiExamples.contains('He was in limerence'),
      detail: zip2.aiExamples.substring(0, zip2.aiExamples.length.clamp(0, 60)));
  check('6.3 apkg AI 例句含词性标签',
      zip2.aiExamples.contains('n.'), detail: zip2.aiExamples.substring(0, zip2.aiExamples.length.clamp(0, 60)));
  check('6.3 apkg HTML 转义（& -> &amp;）',
      zip2.aiExamples.contains('&amp;'), detail: zip2.aiExamples.substring(0, zip2.aiExamples.length.clamp(0, 80)));
  check('6.3 apkg 搭配字段含搭配与例句',
      zip2.aiCollocations.contains('pure limerence') &&
          zip2.aiCollocations.contains('It was pure limerence.'),
      detail: zip2.aiCollocations.substring(0, zip2.aiCollocations.length.clamp(0, 60)));
  check('6.3 无 AI 内容的词该字段为空',
      zip2.emptyAiFieldForPlainWord, detail: 'abandon 的 Examples 应为空');

  // ---- CSV：前 7 列不变 + 末尾 2 列 ----
  final csvReport2 = await exportCsv(nbPath, '${tmp.path}/out2.csv');
  final bytes2 = File(csvReport2.path).readAsBytesSync();
  final decoded2 = Csv().decode(utf8.decode(bytes2.sublist(3)));
  final header = decoded2[0].cast<String>();
  check('6.3 csv 表头 9 列', header.length == 9, detail: header.length);
  check('6.3 csv 前 7 列逐字未变',
      header.sublist(0, 7).join(',') ==
          'word,phonetic,translation,definition,exchange,tags,added_at',
      detail: header.sublist(0, 7));
  check('6.3 csv 新列在末尾',
      header[7] == 'examples' && header[8] == 'collocations', detail: header);

  final limRow = decoded2.firstWhere((r) => r[0] == 'limerence');
  final exCell = limRow[7] as String;
  final colCell = limRow[8] as String;
  check('6.3 csv 例句单元格多行（换行分隔，零分隔符字符）',
      exCell.split('\n').length >= 3, detail: exCell.split('\n').length);
  check('6.3 csv 例句含英文与中文',
      exCell.contains('He was in limerence') && exCell.contains('他陷入痴恋。'),
      detail: exCell.replaceAll('\n', ' / '));
  check('6.3 csv 搭配单元格含搭配与例句',
      colCell.contains('pure limerence | 纯粹痴恋') &&
          colCell.contains('It was pure limerence.'),
      detail: colCell.replaceAll('\n', ' / '));

  final plainRow = decoded2.firstWhere((r) => r[0] == 'abandon');
  check('6.3 csv 无 AI 内容的词两列为空',
      (plainRow[7] as String).isEmpty && (plainRow[8] as String).isEmpty);

  await tmp.delete(recursive: true);
  stdout.writeln(failures == 0 ? 'ALL PASS' : 'FAILURES: $failures');
  if (failures > 0) throw StateError('有失败项');
}

class _ApkgCheck {
  final bool ok;
  final String desc;
  final int noteCount;
  final String exchange;
  final String phonetic;
  final int fieldCount;
  final List<String> fieldNames;
  final String aiExamples;
  final String aiCollocations;
  final bool emptyAiFieldForPlainWord;
  const _ApkgCheck(this.ok, this.desc, this.noteCount, this.exchange,
      this.phonetic, this.fieldCount, this.fieldNames, this.aiExamples,
      this.aiCollocations, this.emptyAiFieldForPlainWord);
}

Future<_ApkgCheck> _checkApkg(String path) async {
  // 字段间用 ';;' 分隔、字段内空格用 '_' 占位，避免 shell 参数拆分干扰。
  // 末尾追加 model 字段信息与 AI 字段内容（v3 新增）。
  const script = r'''
import sys
import zipfile, sqlite3, tempfile, os, json
z = zipfile.ZipFile(sys.argv[1])
names = z.namelist()
ok = "collection.anki2" in names and "media" in names
tmp = tempfile.mktemp(suffix=".anki2")
open(tmp, "wb").write(z.read("collection.anki2"))
con = sqlite3.connect(tmp)
n = con.execute("SELECT COUNT(*) FROM notes").fetchone()[0]
row = con.execute("SELECT flds FROM notes ORDER BY rowid LIMIT 1").fetchone()
flds = row[0].split("\x1f") if row else []
ex = (flds[4] if len(flds) > 4 else "").replace(" ", "_")
ph = flds[1] if len(flds) > 1 else ""

# model 字段数与字段名
col = con.execute("SELECT models FROM col LIMIT 1").fetchone()
models = json.loads(col[0])
m = list(models.values())[0]
field_names = [f["name"] for f in m["flds"]]
field_count = len(field_names)

# 找一张含 AI 例句的笔记（Examples 字段非空）与一张没有的
ai_ex = ""
ai_col = ""
plain_empty = False
for r in con.execute("SELECT flds FROM notes"):
    f = r[0].split("\x1f")
    if len(f) >= 8 and f[6].strip():
        ai_ex = f[6].replace(" ", "_")
        ai_col = f[7].replace(" ", "_")
    elif len(f) >= 8 and not f[6].strip() and not f[7].strip():
        plain_empty = True
con.close(); os.remove(tmp)
print(";;".join([str(ok), str(n), ex, ph, str(field_count),
                 ",".join(field_names), ai_ex, ai_col, str(plain_empty)]))
''';
  final tmpScript = File('${Directory.systemTemp.path}/lupa_apkg_check.py')
    ..writeAsStringSync(script);
  final result = await Process.run(
    'python', ['-X', 'utf8', tmpScript.path, path],
    stdoutEncoding: utf8,
  );
  await tmpScript.delete();
  final parts = result.stdout.toString().trim().split(';;');
  if (parts.length < 9) {
    return _ApkgCheck(false, result.stdout.toString(), 0, '', '', 0, const [],
        '', '', false);
  }
  return _ApkgCheck(
    parts[0] == 'True',
    parts[0],
    int.parse(parts[1]),
    parts[2].replaceAll('_', ' '),
    parts[3],
    int.parse(parts[4]),
    parts[5].split(','),
    parts[6].replaceAll('_', ' '),
    parts[7].replaceAll('_', ' '),
    parts[8] == 'True',
  );
}
