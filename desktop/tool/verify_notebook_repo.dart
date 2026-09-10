// 验证 4.1 / 4.2 / 4.3：生词本 CRUD、固定间隔调度、复习答题。
// 用法: LUPA_HOME=../data dart run tool/verify_notebook_repo.dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lupa/data/data_home.dart';
import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/dict/query.dart' show queryWord;
import 'package:lupa/notebook/repo.dart';
import 'package:lupa/notebook/scheduler.dart';

var failures = 0;

void check(String name, bool ok, {Object? detail}) {
  stdout.writeln('$name: ${ok ? "PASS" : "FAIL"}${detail == null ? "" : "  ($detail)"}');
  if (!ok) failures++;
}

Future<void> main() async {
  final home = dataHome(); // LUPA_HOME
  final dictDb = dictDbPath(home);
  final tmp = await Directory.systemTemp.createTemp('lupa_nb_verify_');
  final nbPath = p.absolute(p.join(tmp.path, 'notebook.sqlite'));

  // ---------- 4.2 调度纯函数（按评分分级推进） ----------
  check('4.2 nextInterval(0, Good)=3 新词与 1 天卡同档',
      nextInterval(0, easeGood) == 3);
  check('4.2 nextInterval(1, Good)=3', nextInterval(1, easeGood) == 3);
  check('4.2 nextInterval(3, Good)=7', nextInterval(3, easeGood) == 7);
  check('4.2 nextInterval(7, Good)=15', nextInterval(7, easeGood) == 15);
  check('4.2 nextInterval(15, Good)=30', nextInterval(15, easeGood) == 30);
  check('4.2 nextInterval(30, Good)=30 顶格', nextInterval(30, easeGood) == 30);
  check('4.2 nextInterval(7, Again)=1 答错回退', nextInterval(7, easeAgain) == 1);
  // 分级：模糊保持当前档、简单前进两档（记得保持"前进一档"不变）
  check('4.2 nextInterval(7, Hard)=7 模糊不推进', nextInterval(7, easeHard) == 7);
  check('4.2 nextInterval(15, Hard)=15', nextInterval(15, easeHard) == 15);
  check('4.2 nextInterval(7, Easy)=30 简单前进两档',
      nextInterval(7, easeEasy) == 30);
  check('4.2 nextInterval(15, Easy)=30 顶格', nextInterval(15, easeEasy) == 30);
  check('4.2 nextInterval(0, Hard)=1 新词模糊进第一档',
      nextInterval(0, easeHard) == 1);
  check('4.2 nextInterval(0, Easy)=7 新词简单进第三档',
      nextInterval(0, easeEasy) == 7);
  check('4.2 7 天卡：模糊 < 记得 < 简单',
      nextInterval(7, easeHard) < nextInterval(7, easeGood) &&
          nextInterval(7, easeGood) < nextInterval(7, easeEasy));
  final (ivl, due) = dueTimestamp(1, easeGood, now: 1000000);
  check('4.2 dueTimestamp(1,Good)=(3, 1000000+3*86400)',
      ivl == 3 && due == 1000000 + 3 * 86400);

  // ---------- 4.1 CRUD ----------
  final noteId = await addWord(nbPath, dictDb, 'abandon', 'cet6 test');
  check('4.1 addWord(abandon) 返回 note id', noteId > 0, detail: noteId);

  // 词库内容快照比对（flds 5 段）
  final entry = await queryWord('abandon', home);
  final list1 = await listWords(nbPath);
  check('4.1 list 长度=1', list1.length == 1);
  final e = list1.first;
  check('4.1 word 快照', e.word == entry!.word, detail: e.word);
  check('4.1 phonetic 快照', e.phonetic == entry.phonetic);
  check('4.1 tags 快照', e.tags == 'cet6 test', detail: e.tags);
  check('4.1 新卡 type=0 queue=0 ivl=0', e.cardType == 0 && e.queue == 0 && e.ivl == 0);

  await Future<void>.delayed(const Duration(seconds: 1)); // mod 是秒级，避开同时刻
  await addWord(nbPath, dictDb, 'perceive', '');
  var l2 = await listWords(nbPath);
  check('4.1 加第二个词后 list=2 且倒序（新在前）', l2.length == 2 && l2.first.word == 'perceive');

  // 重复（忽略大小写）
  var dup = false;
  try {
    await addWord(nbPath, dictDb, 'ABANDON', '');
  } on DuplicateWordError {
    dup = true;
  }
  check('4.1 重复加词(忽略大小写)拒绝', dup);

  // 未收录
  var notIn = false;
  try {
    await addWord(nbPath, dictDb, 'zzzznotaword', '');
  } on WordNotInDictError {
    notIn = true;
  }
  check('4.1 未收录词拒绝', notIn);

  // stats: 2 total, 2 new
  var s = await notebookStats(nbPath);
  check('4.1 stats total=2 new=2', s['total'] == 2 && s['new'] == 2, detail: s);

  // 移除
  final removed = await removeWord(nbPath, 'perceive');
  check('4.1 removeWord(perceive)=true', removed);
  final removedAgain = await removeWord(nbPath, 'perceive');
  check('4.1 重复移除=false', removedAgain == false);
  l2 = await listWords(nbPath);
  check('4.1 移除后 list=1', l2.length == 1);

  // ---------- 4.3 答题与 revlog ----------
  // 重新加 perceive 用于答题
  await addWord(nbPath, dictDb, 'perceive', '');
  final cards = await dueWords(nbPath);
  check('4.3 dueWords 含新卡', cards.length == 2, detail: cards.length);
  final card = cards.where((c) => c.word == 'abandon').first;

  final r1 = await answerCard(nbPath, card.cardId, easeGood);
  check('4.3 新卡 Good => ivl=3', r1.nextIvl == 3, detail: r1.nextIvl);

  final after = await listWords(nbPath, includeSuspended: true);
  final a = after.where((c) => c.word == 'abandon').first;
  check('4.3 卡片 type=Review(2)', a.cardType == 2, detail: a.cardType);
  check('4.3 卡片 due 已更新', a.due == r1.nextDue);
  check('4.3 卡片 reps=1 lapses=0', a.reps == 1 && a.lapses == 0);

  // 忘了：回退第一档且 lapses+1
  final r2 = await answerCard(nbPath, a.cardId, easeAgain);
  final after2 = await listWords(nbPath, includeSuspended: true);
  final a2 = after2.where((c) => c.word == 'abandon').first;
  check('4.3 忘了 => ivl=1', r2.nextIvl == 1 && a2.ivl == 1);
  check('4.3 忘了 => lapses=1 type=Learn(1)', a2.lapses == 1 && a2.cardType == 1);

  // 分级推进落到真实卡片上：记得前进一档、模糊保持、简单前进两档
  final r3 = await answerCard(nbPath, a.cardId, easeGood);
  check('4.3 间隔 1 记得 => 3', r3.nextIvl == 3, detail: r3.nextIvl);
  final r4 = await answerCard(nbPath, a.cardId, easeHard);
  check('4.3 间隔 3 模糊 => 3 保持当前档', r4.nextIvl == 3, detail: r4.nextIvl);
  final r5 = await answerCard(nbPath, a.cardId, easeEasy);
  check('4.3 间隔 3 简单 => 15 前进两档', r5.nextIvl == 15, detail: r5.nextIvl);

  // revlog 每次答题一条
  final con = await databaseFactory.openDatabase(nbPath);
  final revlogCount =
      (await con.rawQuery('SELECT COUNT(*) AS c FROM revlog')).first.values.first as int;
  await con.close();
  check('4.3 revlog 记录=5', revlogCount == 5, detail: revlogCount);

  // ---------- 4.4 撤销最近一次评分 ----------
  final beforeUndo =
      (await listWords(nbPath, includeSuspended: true)).where((c) => c.word == 'abandon').first;
  check('4.4 撤销前 ivl=15', beforeUndo.ivl == 15, detail: beforeUndo.ivl);

  check('4.4 撤销成功', await undoAnswerCard(nbPath, r5));
  final afterUndo =
      (await listWords(nbPath, includeSuspended: true)).where((c) => c.word == 'abandon').first;
  check('4.4 撤销后 ivl 回到 3', afterUndo.ivl == 3, detail: afterUndo.ivl);
  check('4.4 撤销后 reps 回到 4 且 lapses 不变',
      afterUndo.reps == 4 && afterUndo.lapses == 1,
      detail: 'reps=${afterUndo.reps} lapses=${afterUndo.lapses}');
  check('4.4 撤销后 type 回到 Review(2)', afterUndo.cardType == 2, detail: afterUndo.cardType);

  final conU = await databaseFactory.openDatabase(nbPath);
  final revlogAfterUndo =
      (await conU.rawQuery('SELECT COUNT(*) AS c FROM revlog')).first.values.first as int;
  await conU.close();
  check('4.4 撤销后 revlog=4', revlogAfterUndo == 4, detail: revlogAfterUndo);

  // 不是最新一条的回执（r3/r5 已完成回退）必须被拒且无副作用
  check('4.4 过期回执被拒', !(await undoAnswerCard(nbPath, r3)));
  check('4.4 重复撤销被拒', !(await undoAnswerCard(nbPath, r5)));
  final afterReject =
      (await listWords(nbPath, includeSuspended: true)).where((c) => c.word == 'abandon').first;
  check('4.4 被拒后状态不变',
      afterReject.ivl == 3 && afterReject.reps == 4, detail: afterReject.ivl);

  // 撤销后可正常重新评分（只保留这一条新历史）
  final r6 = await answerCard(nbPath, afterReject.cardId, easeEasy);
  check('4.4 撤销后可重新评分 => ivl=15', r6.nextIvl == 15, detail: r6.nextIvl);
  final conR = await databaseFactory.openDatabase(nbPath);
  final revlogAfterRedo =
      (await conR.rawQuery('SELECT COUNT(*) AS c FROM revlog')).first.values.first as int;
  await conR.close();
  check('4.4 重新评分后 revlog=5', revlogAfterRedo == 5, detail: revlogAfterRedo);

  // ---------- 4.5 按范围重置 + 孤儿清理 ----------
  final planAll = await planReviewReset(nbPath, all: true);
  check('4.5 全量计划命中 2 张卡', planAll.cardIds.length == 2, detail: planAll.cardIds.length);
  check('4.5 全量计划历史行数=5', planAll.revlogRows == 5, detail: planAll.revlogRows);
  check('4.5 应用后删除 5 行', await applyReviewReset(nbPath, planAll) == 5);
  final afterReset = (await listWords(nbPath, includeSuspended: true))
      .where((c) => c.word == 'abandon')
      .first;
  check('4.5 重置后回到新词',
      afterReset.ivl == 0 && afterReset.reps == 0 && afterReset.lapses == 0 && afterReset.cardType == 0,
      detail: 'ivl=${afterReset.ivl} reps=${afterReset.reps} type=${afterReset.cardType}');
  final statsReset = await notebookStats(nbPath);
  check('4.5 重置后统计：新词=2 复习中=0',
      statsReset['new'] == 2 && statsReset['review'] == 0, detail: statsReset);
  check('4.5 重置后重新进入到期队列', (await dueWords(nbPath)).length == 2);

  // 窗口在评分时刻之前 → 不命中（历史已在上一步清空，这里验证计划为空）
  final monthAgo = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 86400 * 30;
  final planOld = await planReviewReset(nbPath, sinceSec: monthAgo, untilSec: monthAgo + 60);
  check('4.5 窗口外不命中', planOld.isEmpty, detail: planOld.cardIds.length);

  // 孤儿历史：造一行 cid 不存在的记录
  final conO = await databaseFactory.openDatabase(nbPath,
      options: OpenDatabaseOptions(singleInstance: false));
  await conO.rawInsert(
    'INSERT INTO revlog (r_id, cid, usn, ease, ivl, last_ivl, factor, time, type) '
    'VALUES (?, ?, 0, 3, 1, 0, 0, 0, 1)',
    [DateTime.now().millisecondsSinceEpoch, 999999],
  );
  await conO.close();
  final orphans = await planOrphanRevlog(nbPath);
  check('4.5 识别孤儿历史 1 行', orphans.length == 1, detail: orphans.length);
  check('4.5 清理孤儿 1 行', await applyOrphanRevlogCleanup(nbPath, orphans) == 1);
  final afterOrphan = (await listWords(nbPath, includeSuspended: true))
      .where((c) => c.word == 'abandon')
      .first;
  check('4.5 清孤儿不影响卡片状态',
      afterOrphan.ivl == 0 && afterOrphan.cardType == 0, detail: afterOrphan.ivl);
  check('4.5 清理后无孤儿', (await planOrphanRevlog(nbPath)).isEmpty);

  // 移除生词时一并清历史（对齐短语侧外键级联）
  final r7 = await answerCard(nbPath, afterOrphan.cardId, easeGood);
  check('4.5 移除前该卡有 1 条历史',
      (await planReviewReset(nbPath, words: {'abandon'})).revlogRows == 1);
  await removeWord(nbPath, 'abandon');
  final conRm = await databaseFactory.openDatabase(nbPath,
      options: OpenDatabaseOptions(singleInstance: false));
  final leftOver = (await conRm.rawQuery(
          'SELECT COUNT(*) c FROM revlog WHERE cid = ?', [r7.cardId]))
      .first['c'] as int;
  await conRm.close();
  check('4.5 移除后无残留历史', leftOver == 0, detail: leftOver);

  await tmp.delete(recursive: true);
  stdout.writeln(failures == 0 ? 'ALL PASS' : 'FAILURES: $failures');
}
