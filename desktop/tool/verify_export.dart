// 验证 6.1 / 6.2：apkg 与 csv 导出。
// 用法: LUPA_HOME=../data dart run tool/verify_export.dart
import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
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
  const _ApkgCheck(this.ok, this.desc, this.noteCount, this.exchange, this.phonetic);
}

Future<_ApkgCheck> _checkApkg(String path) async {
  // 字段间用 ';;' 分隔、字段内空格用 '_' 占位，避免 shell 参数拆分干扰
  const script = r'''
import sys
import zipfile, sqlite3, tempfile, os
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
con.close(); os.remove(tmp)
print(";;".join([str(ok), str(n), ex, ph]))
''';
  final tmpScript = File('${Directory.systemTemp.path}/lupa_apkg_check.py')
    ..writeAsStringSync(script);
  final result = await Process.run(
    'python', ['-X', 'utf8', tmpScript.path, path],
    stdoutEncoding: utf8,
  );
  await tmpScript.delete();
  final parts = result.stdout.toString().trim().split(';;');
  if (parts.length < 4) {
    return _ApkgCheck(false, result.stdout.toString(), 0, '', '');
  }
  return _ApkgCheck(
    parts[0] == 'True',
    parts[0],
    int.parse(parts[1]),
    parts[2].replaceAll('_', ' '),
    parts[3],
  );
}
