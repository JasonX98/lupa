// 验证 2.3 / 3.1 / 3.2：词库查询（前缀联想 / 命中 / 统计）。
// 用法: dart run tool/verify_dict_query.dart
import 'dart:io';

import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/dict/query.dart';

Future<void> main() async {
  // 与 README 快速开始一致：LUPA_HOME 指向仓库 data 目录（含已构建 dict.sqlite）
  final home = Directory(Platform.environment['LUPA_HOME'] ?? '../data');

  stdout.writeln('词库: ${dictDbPath(home)}');
  final stats = await dictStats(home);
  stdout.writeln('统计: $stats');

  // 大小写不敏感精确查询
  final e1 = await queryWord('Abandon', home); // 大写开头
  final e2 = await queryWord('abandon', home);
  stdout.writeln('queryWord("Abandon").word = ${e1?.word}');
  stdout.writeln('大小写不敏感一致: ${e1?.word == e2?.word ? "PASS" : "FAIL"}');
  stdout.writeln('abandon 音标=${e1?.phonetic} collins=${e1?.collins} oxford=${e1?.oxford} tag=${e1?.tag}');

  // 未收录
  final miss = await queryWord('zzzznotaword', home);
  stdout.writeln('未收录返回 null: ${miss == null ? "PASS" : "FAIL"}');

  // 前缀联想（高频优先）
  final sug = await suggestPrefix('perce', limit: 5, home: home);
  stdout.writeln('suggestPrefix("perce", 5) = $sug');

  // exchange 解析（3.2）
  final ex = e1?.exchanges ?? {};
  stdout.writeln('abandon.exchanges = $ex');
  final okEx = ex['d'] == 'abandoned' && ex['p'] == 'abandoned' &&
      ex['i'] == 'abandoning' && ex['3'] == 'abandons' && ex['s'] == 'abandons';
  stdout.writeln('exchange 解析: ${okEx ? "PASS" : "FAIL"}');
  stdout.writeln('DONE');
}
