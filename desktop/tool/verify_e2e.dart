// Lupa 端到端验证（openspec task 8.1）：查词 → 加入生词本 → 复习 → 导出 apkg/csv。
// 与 GUI 页面调用同一套业务函数（queryWord / addWord / answerCard / exportApkg / exportCsv），
// headless 跑通即等价于 UI 全流程走通。
//
// 运行：LUPA_HOME=<真实数据目录> dart run tool/verify_e2e.dart
// 生词本与导出产物均写入系统临时目录，不污染真实数据。
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/dict/query.dart';
import 'package:lupa/export/apkg.dart';
import 'package:lupa/export/csv.dart';
import 'package:lupa/notebook/repo.dart';

int _pass = 0;
int _fail = 0;

void check(String name, bool cond, [String detail = '']) {
  if (cond) {
    _pass++;
    print('PASS  $name');
  } else {
    _fail++;
    print('FAIL  $name  $detail');
  }
}

Future<void> main() async {
  final dictDb = dictDbPath(); // 真实词库（只读）
  final tmpHome = await Directory.systemTemp.createTemp('lupa-e2e-');
  final nb = p.join(tmpHome.path, 'notebook.sqlite');

  print('== Lupa e2e ==');
  print('dict: $dictDb');
  print('notebook(临时): $nb');

  // 1. 查词（7.1 的数据路径）
  final entry = await queryWord('abandon');
  check('查词 abandon 命中', entry != null && entry.word.toLowerCase() == 'abandon');
  check('词条含音标/释义', entry != null && entry.phonetic.isNotEmpty && entry.translation.isNotEmpty);
  final sugg = await suggestPrefix('aban', limit: 5);
  check('前缀联想 aban* 非空', sugg.isNotEmpty);

  // 2. 加入生词本（7.2）
  final noteId = await addWord(nb, dictDb, 'abandon', 'e2e');
  check('加入生词本返回 noteId', noteId > 0);
  final entries = await listWords(nb);
  check('列表含 abandon 且 tags=e2e',
      entries.any((e) => e.word.toLowerCase() == 'abandon' && e.tags == 'e2e'));

  // 3. 复习（7.3）：到期队列 + 评分推进调度
  var due = await dueWords(nb);
  check('新卡进入到期队列', due.isNotEmpty && due.first.ivl == 0);
  final cardId = due.first.cardId;
  final rec = await answerCard(nb, cardId, 3); // 记得
  // 新卡与间隔 1 天的卡同档：记得前进一档 → 3 天
  check('评分 3 后间隔推进到 3 天', rec.nextIvl == 3, 'nextIvl=${rec.nextIvl}');
  final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  check('nextDue = now + 3*86400',
      (rec.nextDue - nowSec - 3 * 86400).abs() <= 2);
  due = await dueWords(nb);
  check('答对后当天不再到期', due.isEmpty || due.first.cardId != cardId);

  // 4. 导出（7.4 / 8.1 末段）
  final outApkg = p.join(tmpHome.path, 'e2e.apkg');
  final report = await exportApkg(nb, outApkg);
  check('apkg 导出 1 张卡', report.count == 1 && File(report.path).lengthSync() > 0);
  check('apkg guid 稳定',
      stableGuid('abandon') == 'c82559e49d41d9a0', stableGuid('abandon'));

  final outCsv = p.join(tmpHome.path, 'e2e.csv');
  final csvReport = await exportCsv(nb, outCsv);
  // 注意：readAsStringSync 会剥掉 UTF-8 BOM，必须用字节断言
  final csvBytes = File(outCsv).readAsBytesSync();
  check('csv 导出含 BOM（EF BB BF）', csvReport.count == 1 &&
      csvBytes.length > 3 &&
      csvBytes[0] == 0xEF && csvBytes[1] == 0xBB && csvBytes[2] == 0xBF);
  final csvText = File(outCsv).readAsStringSync();
  check('csv 含表头与数据', csvText.contains('word,phonetic') &&
      csvText.contains('abandon'));

  // 5. 去重与未收录词的行为契约
  var dup = false;
  try {
    await addWord(nb, dictDb, 'abandon', '');
  } on DuplicateWordError {
    dup = true;
  }
  check('重复加词抛 DuplicateWordError', dup);

  var missing = false;
  try {
    await addWord(nb, dictDb, 'zzznotawordzzz', '');
  } on WordNotInDictError {
    missing = true;
  }
  check('未收录词抛 WordNotInDictError', missing);

  // 清理
  await tmpHome.delete(recursive: true);
  print('== $_pass passed, $_fail failed ==');
  if (_fail > 0) exitCode = 1;
}
