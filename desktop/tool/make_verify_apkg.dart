// 从真实生词本导出验证用 apkg/csv（openspec task 8.2 用）。
// 运行：LUPA_HOME=<数据目录> dart run tool/make_verify_apkg.dart
import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/export/apkg.dart';
import 'package:lupa/export/csv.dart';

Future<void> main() async {
  final nb = notebookDbPath();
  final a = await exportApkg(nb, 'build/lupa-desktop-verify.apkg');
  print('apkg: ${a.count} 词 -> ${a.path} (${a.sizeBytes} bytes)');
  final c = await exportCsv(nb, 'build/lupa-desktop-verify.csv');
  print('csv : ${c.count} 词 -> ${c.path} (${c.sizeBytes} bytes)');
}
