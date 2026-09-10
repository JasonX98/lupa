// 复习数据重置维护脚本（openspec change reset-review-history）。
//
// 把被误评分推进过的卡片打回新词，并删除其复习历史；顺带可清孤儿历史行。
// **默认 dry-run**（只打印计划，不写库），显式 --apply 才写入，且写入前自动备份生词本。
//
// 数据目录解析与 AppState 同源：settings.dataDir > LUPA_HOME > <exe>/lupa_data。
//
// 用法：
//   dart run tool/reset_review_state.dart --all
//   dart run tool/reset_review_state.dart --since 2026-09-05T12:00 --until 2026-09-06T12:00
//   dart run tool/reset_review_state.dart --word abandon --word serene
//   dart run tool/reset_review_state.dart --orphans
//   dart run tool/reset_review_state.dart --all --phrases --apply
//
// 时间精度：单词 revlog 的 r_id 低 16 位被 XOR 随机化 → 判定窗口约 ±65 秒，
// 同一分钟内的多次评分互相不可区分（dry-run 会打印每个命中的依据）；
// 短语侧 phrase_review_log.ts 是真实秒级时间，精确。
import 'dart:io';

import 'package:lupa/data/data_files.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/notebook/repo.dart';
import 'package:lupa/phrase/repo.dart' as phrase_repo;

class _Opts {
  final Set<String> words = {};
  int? sinceSec;
  int? untilSec;
  bool all = false;
  bool phrases = false;
  bool orphans = false;
  bool apply = false;
  bool help = false;
  String? error;
}

int _tsOf(String s) {
  final d = DateTime.tryParse(s);
  if (d == null) throw FormatException('时间格式应为 ISO8601（如 2026-09-05T12:00）: $s');
  return d.millisecondsSinceEpoch ~/ 1000;
}

_Opts _parse(List<String> args) {
  final o = _Opts();
  String next(List<String> a, int i, String flag) {
    if (i + 1 >= a.length) throw FormatException('$flag 缺少取值');
    return a[i + 1];
  }

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    try {
      switch (a) {
        case '--word':
          o.words.add(next(args, i, a));
          i++;
        case '--since':
          o.sinceSec = _tsOf(next(args, i, a));
          i++;
        case '--until':
          o.untilSec = _tsOf(next(args, i, a));
          i++;
        case '--all':
          o.all = true;
        case '--phrases':
          o.phrases = true;
        case '--orphans':
          o.orphans = true;
        case '--apply':
          o.apply = true;
        case '-h':
        case '--help':
          o.help = true;
        default:
          o.error = '未知参数 $a';
      }
    } on FormatException catch (e) {
      o.error = e.message;
    }
    if (o.error != null) break;
  }
  if (o.error == null &&
      !o.help &&
      o.words.isEmpty &&
      !o.all &&
      o.sinceSec == null &&
      o.untilSec == null &&
      !o.orphans) {
    o.error = '至少要指定一种范围：--word / --since / --all / --orphans';
  }
  return o;
}

void _usage() {
  stdout.writeln('''
用法: dart run tool/reset_review_state.dart <范围> [--apply] [--phrases]

范围（至少一个）：
  --word <词>            重置指定词（可重复；仅单词侧生效）
  --since <ISO8601>      时间窗口起点（含）
  --until <ISO8601>      时间窗口终点（不含）
  --all                  全部卡片（危险：真实学习进度一并清空）
  --orphans              只清理孤儿复习历史（cid 已不存在的行）

开关：
  --phrases              同时作用于短语集（默认只动单词）
  --apply                真正写入（默认 dry-run，只打印计划）
  -h, --help             显示本帮助

写入前会自动备份生词本，并打印备份路径。''');
}

Future<void> main(List<String> args) async {
  final o = _parse(args);
  if (o.help) {
    _usage();
    return;
  }
  if (o.error != null) {
    stderr.writeln('参数错误：${o.error}');
    _usage();
    exit(2);
  }

  final home = dataHome();
  final nb = notebookDbPath(home);
  stdout.writeln('数据目录: ${home.path}');
  stdout.writeln('生词本库: $nb');
  stdout.writeln('模式    : ${o.apply ? 'APPLY（写入）' : 'DRY-RUN（只读，不会改任何数据）'}');
  if (!File(nb).existsSync()) {
    stderr.writeln('生词本库不存在，没有可清理的数据。');
    exit(1);
  }

  try {
    final doWord = o.words.isNotEmpty || o.all || o.sinceSec != null || o.untilSec != null;
    final wordPlan = doWord
        ? await planReviewReset(
            nb,
            words: o.words.isEmpty ? null : o.words,
            sinceSec: o.sinceSec,
            untilSec: o.untilSec,
            all: o.all,
          )
        : null;
    final phrasePlan = o.phrases
        ? await phrase_repo.planPhraseReset(nb, all: o.all, sinceSec: o.sinceSec, untilSec: o.untilSec)
        : null;
    final orphans = o.orphans ? await planOrphanRevlog(nb) : const <int>[];

    if (wordPlan != null) {
      if (wordPlan.isEmpty) {
        stdout.writeln('单词    : 无命中卡片。');
      } else {
        stdout.writeln(
            '单词    : 命中 ${wordPlan.cardIds.length} 张卡，将删除复习历史 ${wordPlan.revlogRows} 行');
        for (var i = 0; i < wordPlan.cardIds.length; i++) {
          final id = wordPlan.cardIds[i];
          stdout.writeln('  - ${wordPlan.words[i].padRight(18)} 依据=${wordPlan.basis[id]}');
        }
      }
    }
    if (phrasePlan != null) {
      if (phrasePlan.isEmpty) {
        stdout.writeln('短语    : 无命中短语。');
      } else {
        stdout.writeln(
            '短语    : 命中 ${phrasePlan.ids.length} 条，将删除复习历史 ${phrasePlan.logRows} 行');
        for (var i = 0; i < phrasePlan.ids.length; i++) {
          stdout.writeln('  - ${phrasePlan.phrases[i].padRight(18)} 依据=${phrasePlan.basis[phrasePlan.ids[i]]}');
        }
      }
    }
    if (o.orphans) {
      stdout.writeln('孤儿历史: ${orphans.length} 行待清理');
    }

    if (!o.apply) {
      stdout.writeln('提示    : 这是 dry-run。核对上方清单后加 --apply 才会写入（写入前自动备份）。');
      return;
    }

    final backup = await backupNotebook(nb);
    stdout.writeln('已备份  : $backup');
    if (wordPlan != null && !wordPlan.isEmpty) {
      final deleted = await applyReviewReset(nb, wordPlan);
      stdout.writeln(
          '单词    : 已重置 ${wordPlan.cardIds.length} 张卡，删除复习历史 $deleted 行');
    }
    if (phrasePlan != null && !phrasePlan.isEmpty) {
      final deleted = await phrase_repo.applyPhraseReset(nb, phrasePlan);
      stdout.writeln('短语    : 已重置 ${phrasePlan.ids.length} 条，删除复习历史 $deleted 行');
    }
    if (orphans.isNotEmpty) {
      final deleted = await applyOrphanRevlogCleanup(nb, orphans);
      stdout.writeln('孤儿历史: 已清理 $deleted 行');
    }
    stdout.writeln('完成    : 这些卡片已回到「新词」，重新打开应用即可看到。');
  } catch (e) {
    final msg = e.toString();
    if (msg.contains('locked') || msg.contains('busy') || msg.contains('in use')) {
      stderr.writeln('数据库被占用：请先关闭 Lupa 再重试（盘上数据未改动）。');
    } else {
      stderr.writeln('执行失败: $e');
    }
    exit(1);
  }
}
