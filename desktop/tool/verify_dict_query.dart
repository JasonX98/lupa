// 验证 2.3 / 3.1 / 3.2 / 词形还原：词库查询（前缀联想 / 命中 / 统计 / 本地还原）。
// 用法: dart run tool/verify_dict_query.dart
import 'dart:io';

import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/dict/lemma.dart';
import 'package:lupa/dict/query.dart';

int _fail = 0;

void check(String name, bool ok, [Object? detail]) {
  stdout.writeln('$name: ${ok ? "PASS" : "FAIL"}${detail == null ? "" : "  ($detail)"}');
  if (!ok) _fail++;
}

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

  // ---------- 本地词形还原（对真实词库）----------
  // 这一层排在 AI 之前：查 went 时正确答案是「这是 go 的过去式」，
  // 而不是让 AI 从零编一张 went 的卡（见 change 的 design D3）。
  final db = await openDict(home);
  try {
    final idx = await buildLemmaIndex(db);
    stdout.writeln('词形索引规模: ${idx.length} 个变形词形');

    for (final (form, lemma) in [
      ('went', 'go'),
      ('gone', 'go'),
      ('children', 'child'),
      ('bought', 'buy'),
      ('took', 'take'),
      ('mice', 'mouse'),
      ('ran', 'run'),
      ('feet', 'foot'),
    ]) {
      final hit = await lookupLemma(db, form, index: idx);
      check('还原 $form -> $lemma', hit?.lemma == lemma, hit?.lemma);
    }

    // 精确命中优先：better 自身在词库中，不应被报为 good 的比较级
    check('better 精确命中不报还原', await lookupLemma(db, 'better', index: idx) == null);

    // 派生词超出 exchange 覆盖范围，应还原不了（这类仍走 AI）
    check('派生词还原不了（serendipitously）',
        await lookupLemma(db, 'serendipitously', index: idx) == null);
    // 无意义输入
    check('无意义输入还原不了', await lookupLemma(db, 'zzzznotaword', index: idx) == null);

    // 数据不变量：无逗号，且每个 `/` 段恰好产出一个词形（即段内无第二冒号）。
    // 注意别用 SQL 写 `LIKE '%:%:%'` —— 那是「至少 2 个冒号」，会命中
    // `d:abandoned/p:abandoned` 这种正常值，是个假阳性陷阱。
    final withComma = (await db.rawQuery(
            "SELECT COUNT(*) c FROM dict WHERE exchange LIKE '%,%'"))
        .first['c'] as int;
    check('exchange 无逗号', withComma == 0, withComma);

    final exRows = await db.rawQuery(
        "SELECT word, exchange FROM dict WHERE exchange != ''");
    var segments = 0, forms = 0, badSeg = 0;
    for (final r in exRows) {
      final ex = (r['exchange'] as String?) ?? '';
      for (final seg in ex.split('/')) {
        segments++;
        if (seg.trim().isEmpty) continue;
        final i = seg.indexOf(':');
        if (i <= 0 || seg.substring(i + 1).contains(':')) {
          badSeg++;
        } else {
          forms++;
        }
      }
    }
    check('exchange 每段恰好一个词形',
        badSeg == 0 && forms == segments,
        'segments=$segments forms=$forms bad=$badSeg');
    stdout.writeln('exchange 段数: $segments');
  } finally {
    await db.close();
  }

  stdout.writeln(_fail == 0 ? 'ALL PASS' : 'FAILURES: $_fail');
  stdout.writeln('DONE');
}
