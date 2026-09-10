// 验证 4.1 / 4.2 / 4.3：生词本 CRUD、固定间隔调度、复习答题与 Python 版行为一致。
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

  final (nextIvl, nextDue) = await answerCard(nbPath, card.cardId, easeGood);
  check('4.3 新卡 Good => ivl=3', nextIvl == 3, detail: nextIvl);

  final after = await listWords(nbPath, includeSuspended: true);
  final a = after.where((c) => c.word == 'abandon').first;
  check('4.3 卡片 type=Review(2)', a.cardType == 2, detail: a.cardType);
  check('4.3 卡片 due 已更新', a.due == nextDue);
  check('4.3 卡片 reps=1 lapses=0', a.reps == 1 && a.lapses == 0);

  // 忘了：回退第一档且 lapses+1
  final (ivl2, _) = await answerCard(nbPath, a.cardId, easeAgain);
  final after2 = await listWords(nbPath, includeSuspended: true);
  final a2 = after2.where((c) => c.word == 'abandon').first;
  check('4.3 忘了 => ivl=1', ivl2 == 1 && a2.ivl == 1);
  check('4.3 忘了 => lapses=1 type=Learn(1)', a2.lapses == 1 && a2.cardType == 1);

  // 分级推进落到真实卡片上：记得前进一档、模糊保持、简单前进两档
  final (ivl3, _) = await answerCard(nbPath, a.cardId, easeGood);
  check('4.3 间隔 1 记得 => 3', ivl3 == 3, detail: ivl3);
  final (ivl4, _) = await answerCard(nbPath, a.cardId, easeHard);
  check('4.3 间隔 3 模糊 => 3 保持当前档', ivl4 == 3, detail: ivl4);
  final (ivl5, _) = await answerCard(nbPath, a.cardId, easeEasy);
  check('4.3 间隔 3 简单 => 15 前进两档', ivl5 == 15, detail: ivl5);

  // revlog 每次答题一条
  final con = await databaseFactory.openDatabase(nbPath);
  final revlogCount =
      (await con.rawQuery('SELECT COUNT(*) AS c FROM revlog')).first.values.first as int;
  await con.close();
  check('4.3 revlog 记录=5', revlogCount == 5, detail: revlogCount);

  await tmp.delete(recursive: true);
  stdout.writeln(failures == 0 ? 'ALL PASS' : 'FAILURES: $failures');
}
