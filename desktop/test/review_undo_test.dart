// 复习撤销（0 键）测试 —— openspec change add-review-undo。
//
// 真实按键驱动，断言可观察结果（界面回到翻面态 / 卡片调度状态 / 复习历史条数）。
// 数据：临时 configHome/dataHome，种子卡片直接写 notes/cards（不依赖 dict.sqlite）。
// 踩过的坑：flutter_test 跑在 fake-async zone，等 sqflite 真实 IO 必须用
// tester.runAsync 烧真实时间再 pump，否则 await 永不返回（测试挂死）。
// 辅助函数与 app_shell_shortcut_test.dart 保持同一套写法（两个文件各自自足）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/notebook/repo.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/widgets/app_shell.dart';

const _searchHint = '输入单词，回车查询（Ctrl+F 回到这里）';
const _reviewMark = '显示答案（空格）';
const _phraseMark = '记录短语';
const _undoHint = '按 0 撤销上一次评分';

Directory _tmp(String tag) => Directory(p.join(
    Directory.systemTemp.path,
    'lupa_undo_${tag}_${DateTime.now().microsecondsSinceEpoch}'))
  ..createSync(recursive: true);

Future<AppState> _initState(Directory cfg, Directory data) async {
  setConfigHomeOverride(cfg.path);
  setDataHomeOverride(data.path);
  File(p.join(cfg.path, configFile)).writeAsStringSync(json.encode({
    'default_provider': 'youdao',
    'providers': {'youdao': {'phonetic_url': 'u', 'tts_url': 'u'}},
    'settings': {'theme': 'system'},
  }), encoding: utf8);
  final state = AppState();
  await state.init();
  return state;
}

/// 种子卡片：复习中、间隔 1 天、已过期。`dueAgoSec` 用来固定到期队列顺序。
Future<int> _seedDueCard(AppState state, String word, int dueAgoSec) async {
  final con = await databaseFactory.openDatabase(p.absolute(state.nbPath));
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final noteId = await con.insert('notes', {
    'n_id': 'n_$word',
    'm_id': modelId,
    'mod': now - 86400,
    'usn': 0,
    'tags': '',
    'flds': [word, 'əˈbændən', '放弃；抛弃', 'to give up', ''].join(fieldSep),
    'sfld': word,
    'csum': 0,
    'flags': 0,
    'data': '',
  });
  final cardId = await con.insert('cards', {
    'c_id': 'c_$word',
    'n_id': noteId,
    'did': deckId,
    'ord': 0,
    'mod': now - 86400,
    'usn': 0,
    'type': cardReview,
    'queue': queueNew,
    'due': now - dueAgoSec,
    'ivl': 1,
    'factor': 0,
    'reps': 1,
    'lapses': 0,
    'left': 0,
    'odue': 0,
    'odid': 0,
    'flags': 0,
    'data': '',
  });
  await con.close();
  return cardId;
}

/// 读卡片调度状态 + 该卡复习历史条数（一次连接取完；真实 IO 走 runAsync）。
Future<(Map<String, Object?>, int)> _cardState(
    WidgetTester tester, AppState state, int cardId) async {
  final result = await tester.runAsync(() async {
    final con = await databaseFactory.openDatabase(p.absolute(state.nbPath));
    final rows =
        await con.rawQuery('SELECT * FROM cards WHERE id = ?', [cardId]);
    final n = (await con
            .rawQuery('SELECT COUNT(*) AS n FROM revlog WHERE cid = ?', [cardId]))
        .first['n'] as int;
    await con.close();
    return (rows.first, n);
  });
  return result!;
}

Future<void> _settle(WidgetTester tester, {int rounds = 6, int ms = 60}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump(Duration(milliseconds: ms));
  }
}

Future<void> _waitFor(WidgetTester tester, Finder f, {String? what}) async {
  for (var i = 0; i < 25; i++) {
    await _settle(tester, rounds: 1, ms: 60);
    if (f.evaluate().isNotEmpty) return;
  }
  fail('等待超时：${what ?? f.toString()}');
}

/// 轮询到复习历史条数达到期望值（写库是真实 IO，需要真实时间落地）。
Future<(Map<String, Object?>, int)> _waitLogs(
    WidgetTester tester, AppState state, int cardId, int expected) async {
  var last = await _cardState(tester, state, cardId);
  for (var i = 0; i < 25 && last.$2 != expected; i++) {
    await _settle(tester, rounds: 1, ms: 60);
    last = await _cardState(tester, state, cardId);
  }
  return last;
}

Future<void> _ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
      platform: 'windows');
  await tester.sendKeyEvent(key, platform: 'windows');
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
      platform: 'windows');
  await _settle(tester);
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key, platform: 'windows');
  await _settle(tester);
}

void main() {
  late Directory cfg;
  late Directory data;

  setUp(() {
    cfg = _tmp('cfg');
    data = _tmp('data');
  });

  tearDown(() {
    for (final d in [cfg, data]) {
      for (var i = 0; i < 5; i++) {
        try {
          if (d.existsSync()) d.deleteSync(recursive: true);
          break;
        } on FileSystemException {
          sleep(const Duration(milliseconds: 100));
        }
      }
    }
  });

  /// 挂外壳并进入复习页，返回 (state, 卡片 id 列表按到期顺序)。
  Future<(AppState, List<int>)> boot(WidgetTester tester,
      {List<String> words = const ['abandon']}) async {
    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.runAsync(() async {
      for (var i = 0; i < words.length; i++) {
        // 到期时间递减，固定队列顺序 = words 顺序
        await _seedDueCard(state, words[i], 7200 - i * 60);
      }
      await state.refresh();
    });
    final ids = state.due.map((e) => e.cardId).toList();
    await tester.pumpWidget(MaterialApp(home: AppShell(state: state)));
    await _settle(tester);
    await _ctrl(tester, LogicalKeyboardKey.keyR);
    await _waitFor(tester, find.text(_reviewMark), what: '复习页卡片');
    return (state, ids);
  }

  testWidgets('4.1 评分后按 0 撤销：回到评分前状态且历史清零', (tester) async {
    final (state, ids) = await boot(tester, words: ['abandon', 'ubiquitous']);
    final first = ids.first;

    await _press(tester, LogicalKeyboardKey.space); // 翻面
    await _waitFor(tester, find.textContaining('忘了'), what: '评分区');
    await _press(tester, LogicalKeyboardKey.digit3); // 记得
    var (row, logs) = await _waitLogs(tester, state, first, 1);
    expect(logs, 1);
    expect(row['ivl'], 3);

    // 此时界面已在下一张卡的未翻面态；撤销判定必须在「未翻面」闸门之前
    await _press(tester, LogicalKeyboardKey.digit0);
    (row, logs) = await _waitLogs(tester, state, first, 0);

    expect(logs, 0, reason: '撤销后该卡复习历史应为 0 条');
    expect(row['ivl'], 1, reason: 'ivl 回到评分前');
    expect(row['reps'], 1, reason: 'reps 回到评分前');
    expect(row['lapses'], 0);
    expect(row['type'], cardReview, reason: 'type 回到评分前');
    // 回到那张卡的翻面态，可直接重评
    await _waitFor(tester, find.textContaining('忘了'), what: '撤销后回到翻面态');
  });

  testWidgets('4.2 撤销后重新评分：只保留这一条新历史', (tester) async {
    final (state, ids) = await boot(tester);
    final only = ids.first;

    await _press(tester, LogicalKeyboardKey.space);
    await _waitFor(tester, find.textContaining('忘了'), what: '评分区');
    await _press(tester, LogicalKeyboardKey.digit2); // 模糊
    var (row, logs) = await _waitLogs(tester, state, only, 1);
    expect(row['ivl'], 1, reason: '模糊保持当前档');

    await _press(tester, LogicalKeyboardKey.digit0);
    (row, logs) = await _waitLogs(tester, state, only, 0);
    expect(logs, 0);

    // 撤销后仍处于翻面态 → 直接重新评分
    await _press(tester, LogicalKeyboardKey.digit3); // 记得
    (row, logs) = await _waitLogs(tester, state, only, 1);
    expect(logs, 1, reason: '只保留重新评分这一条');
    expect(row['ivl'], 3);
    expect(row['reps'], 2);
  });

  testWidgets('4.3 连按两次 0：只撤一次，第二次无副作用', (tester) async {
    final (state, ids) = await boot(tester);
    final only = ids.first;

    await _press(tester, LogicalKeyboardKey.space);
    await _waitFor(tester, find.textContaining('忘了'), what: '评分区');
    await _press(tester, LogicalKeyboardKey.digit3);
    var (row, logs) = await _waitLogs(tester, state, only, 1);
    expect(logs, 1);

    // 两次按键之间不 settle：第二次落在 _submitting 窗口内（守卫）与清槽之后
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0, platform: 'windows');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0, platform: 'windows');
    await _settle(tester);
    (row, logs) = await _waitLogs(tester, state, only, 0);
    expect(logs, 0, reason: '只应撤销一次');
    expect(row['ivl'], 1);
    expect(row['reps'], 1);
  });

  testWidgets('4.4 离开复习页后按 0 不生效（撤销不跨会话）', (tester) async {
    final (state, ids) = await boot(tester);
    final only = ids.first;

    await _press(tester, LogicalKeyboardKey.space);
    await _waitFor(tester, find.textContaining('忘了'), what: '评分区');
    await _press(tester, LogicalKeyboardKey.digit3);
    var (row, logs) = await _waitLogs(tester, state, only, 1);
    expect(logs, 1);

    await _ctrl(tester, LogicalKeyboardKey.keyI); // 切到短语集
    await _waitFor(tester, find.text(_phraseMark), what: '短语集页');
    await _press(tester, LogicalKeyboardKey.digit0); // 隐藏页不得响应撤销
    await _settle(tester);
    (row, logs) = await _cardState(tester, state, only);
    expect(logs, 1, reason: '离开后撤销应失效');
    expect(row['ivl'], 3);

    // 切回复习页：队列重载 → 撤销槽清空 → 再按 0 仍不生效
    // （那张卡已推进到未来，队列为空 → 页面显示「没有到期的卡片」，
    //   看到它即说明重载已落盘、旧回执已作废）
    await _ctrl(tester, LogicalKeyboardKey.keyR);
    await _waitFor(tester, find.text('没有到期的卡片'), what: '重载后的复习页');
    await _press(tester, LogicalKeyboardKey.digit0);
    await _settle(tester);
    (row, logs) = await _cardState(tester, state, only);
    expect(logs, 1, reason: '重载后旧回执作废');
    expect(row['ivl'], 3);
  });

  testWidgets('4.5 最后一张评完（完成页）也能撤销', (tester) async {
    final (state, ids) = await boot(tester);
    final only = ids.first;

    await _press(tester, LogicalKeyboardKey.space);
    await _waitFor(tester, find.textContaining('忘了'), what: '评分区');
    await _press(tester, LogicalKeyboardKey.digit3);
    var (row, logs) = await _waitLogs(tester, state, only, 1);
    expect(logs, 1);
    expect(find.text(_reviewMark), findsNothing, reason: '评完进入完成页');

    await _press(tester, LogicalKeyboardKey.digit0);
    (row, logs) = await _waitLogs(tester, state, only, 0);
    expect(logs, 0, reason: '完成页也要能撤最后一张');
    expect(row['ivl'], 1);
    await _waitFor(tester, find.textContaining('忘了'), what: '撤销后回到该卡翻面态');
  });

  testWidgets('3.4 撤销提示只在存在可撤销评分时出现', (tester) async {
    final (state, ids) = await boot(tester, words: ['abandon', 'ubiquitous']);
    expect(ids.length, 2);
    // 刚进页：无可撤销评分 → 不显示提示
    expect(find.text(_undoHint), findsNothing);

    await _press(tester, LogicalKeyboardKey.space);
    await _waitFor(tester, find.textContaining('忘了'), what: '评分区');
    await _press(tester, LogicalKeyboardKey.digit3);
    await _waitLogs(tester, state, ids.first, 1);

    // 第二张卡的正面应出现撤销提示
    await _waitFor(tester, find.text(_undoHint), what: '撤销提示');

    // 撤销后槽被清空 → 提示消失
    await _press(tester, LogicalKeyboardKey.digit0);
    await _waitLogs(tester, state, ids.first, 0);
    expect(find.text(_undoHint), findsNothing);
  });

  testWidgets('4.6 查词页快捷键未受影响（回归）', (tester) async {
    await boot(tester);
    await _ctrl(tester, LogicalKeyboardKey.keyF);
    expect(find.text(_searchHint), findsOneWidget);
  });
}
