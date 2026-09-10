// 外壳快捷键与焦点归属测试（openspec change fix-shortcut-focus-and-docs）。
//
// 与既有 UI 冒烟不同：这里发送**真实按键**（sendKeyEvent），断言可观察结果——
// 当前显示的页面、生词本库里的调度状态与复习记录条数。
// 回归重点（用户实际踩到的路径）：
//   * Ctrl+R 进复习 → 空格翻面 → Ctrl+I 切走 → 按 3：不得写库
//   * 查词页输入 → Ctrl+B 切走 → 后续文本不得落进隐藏搜索框
//
// 注意（踩过的坑）：flutter_test 跑在 fake-async zone 里，凡是真实 IO（sqflite）
// 都必须放进 tester.runAsync，否则 await 永不返回、测试挂死。
// 数据：临时 configHome/dataHome；种子卡片直接写 notes/cards（不依赖 dict.sqlite）。
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
import 'package:lupa/pages/review_page.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/widgets/app_shell.dart';

// ---- 页面标记 ----
// find 默认 skipOffstage，IndexedStack 只暴露当前页，因此「当前是哪一页」可以直接
// 用各页独有文案断言。
// 注意：统计条渲染成 '总词数 '（尾部带空格）→ 用 textContaining；
// 「记录短语」另有一条空态说明也含这四个字 → 必须用精确 text。
const _searchHint = '输入单词，回车查询（Ctrl+F 回到这里）';
const _notebookMark = '总词数';
const _reviewMark = '显示答案（空格）';
const _phraseMark = '记录短语';
const _exportMark = 'Anki 牌组（.apkg）';

Finder _mark(String s) => find.textContaining(s);

Directory _tmp(String tag) => Directory(p.join(
    Directory.systemTemp.path,
    'lupa_shortcut_${tag}_${DateTime.now().microsecondsSinceEpoch}'))
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

/// 直接写 notes/cards 种子卡片（绕开词库校验，测试不依赖 dict.sqlite）。
/// 默认造一张「复习中、间隔 1 天、一小时前到期」的卡，复习队列必然包含它。
Future<int> _seedDueCard(AppState state, String word) async {
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
    'due': now - 3600,
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

/// 读卡片调度状态 + 该卡复习记录条数（一次连接取完；真实 IO 走 runAsync）。
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

/// 让异步 IO 与 setState 落地。
/// 关键：fake-async zone 里只 pump 是**不推进真实时间**的，sqflite 的真实 IO 需要
/// 真实时钟——所以每轮先 runAsync 烧掉一点真实时间，再 pump 把已排队的回调 flush 出来。
Future<void> _settle(WidgetTester tester, {int rounds = 6, int ms = 60}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump(Duration(milliseconds: ms));
  }
}

/// 轮询等待某个 finder 命中：真实 IO 完成时机不确定，固定 sleep 会假失败。
/// 先过一帧再判定：切页后页面的焦点是在 post-frame 回调里要回去的，
/// 测试不能在「切页那一帧」里紧接着发下一个按键（真人做不到，也会假失败）。
Future<void> _waitFor(WidgetTester tester, Finder f, {String? what}) async {
  for (var i = 0; i < 25; i++) {
    await _settle(tester, rounds: 1, ms: 60);
    if (f.evaluate().isNotEmpty) return;
  }
  fail('等待超时：${what ?? f.toString()}');
}

/// 轮询到复习记录条数达到期望值。
Future<(Map<String, Object?>, int)> _waitLogs(
    WidgetTester tester, AppState state, int cardId, int expected) async {
  var last = await _cardState(tester, state, cardId);
  for (var i = 0; i < 25 && last.$2 != expected; i++) {
    await _settle(tester, rounds: 1, ms: 60);
    last = await _cardState(tester, state, cardId);
  }
  return last;
}

/// 负面断言前的等待：给「若真会发生」的写库留够真实时间，避免假通过。
Future<void> _settleForNoWrite(WidgetTester tester) =>
    _settle(tester, rounds: 18, ms: 60);

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

/// 查词页搜索框（隐藏页也能找到：skipOffstage: false + 按 hintText 定位）。
TextField _searchField(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField, skipOffstage: false))
    .firstWhere((f) => f.decoration?.hintText == _searchHint);

/// 复习页根 Focus 的 FocusNode（用于强制接管键盘，绕开外壳）。
FocusNode _reviewFocusNode(WidgetTester tester) => tester
    .widget<Focus>(find
        .descendant(of: find.byType(ReviewPage), matching: find.byType(Focus))
        .first)
    .focusNode!;

void main() {
  late Directory cfg;
  late Directory data;

  setUp(() {
    cfg = _tmp('cfg');
    data = _tmp('data');
  });

  tearDown(() {
    // Windows 上 sqlite 释放文件句柄有延迟，删不掉不影响测试结论
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

  /// 建库 + 种子卡片（不挂外壳），返回已 refresh 的状态。
  Future<AppState> seed(WidgetTester tester,
      {List<String> words = const ['abandon']}) async {
    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.runAsync(() async {
      for (final w in words) {
        await _seedDueCard(state, w);
      }
      await state.refresh();
    });
    return state;
  }

  Future<AppState> boot(WidgetTester tester,
      {List<String> words = const ['abandon']}) async {
    final state = await seed(tester, words: words);
    await tester.pumpWidget(MaterialApp(home: AppShell(state: state)));
    await _settle(tester);
    return state;
  }

  testWidgets('2.1 骨架：种子卡片进入到期队列', (tester) async {
    final state = await boot(tester);
    expect(state.due, isNotEmpty);
    expect(state.due.first.word, 'abandon');
  });

  testWidgets('2.2 Ctrl+F/B/R/I/E 切换页面', (tester) async {
    await boot(tester);
    expect(find.text(_searchHint), findsOneWidget); // 起始在查词页

    await _ctrl(tester, LogicalKeyboardKey.keyB);
    await _waitFor(tester, _mark(_notebookMark), what: '生词本页');
    expect(_mark(_notebookMark), findsOneWidget);

    await _ctrl(tester, LogicalKeyboardKey.keyR);
    await _waitFor(tester, find.text(_reviewMark), what: '单词复习页');
    expect(find.text(_reviewMark), findsOneWidget);

    await _ctrl(tester, LogicalKeyboardKey.keyI);
    await _waitFor(tester, find.text(_phraseMark), what: '短语集页');
    expect(find.text(_phraseMark), findsOneWidget);

    await _ctrl(tester, LogicalKeyboardKey.keyE);
    await _waitFor(tester, find.text(_exportMark), what: '导出页');
    expect(find.text(_exportMark), findsOneWidget);

    await _ctrl(tester, LogicalKeyboardKey.keyF);
    expect(find.text(_searchHint), findsOneWidget);
  });

  testWidgets('2.3 复习页：空格翻面后按 3 推进调度并写记录', (tester) async {
    final state = await boot(tester);
    final cardId = state.due.first.cardId;

    await _ctrl(tester, LogicalKeyboardKey.keyR);
    await _waitFor(tester, find.text(_reviewMark), what: '复习页卡片');
    await _press(tester, LogicalKeyboardKey.space); // 翻面
    await _waitFor(tester, find.textContaining('忘了'), what: '评分区');
    await _press(tester, LogicalKeyboardKey.digit3); // 记得

    final (after, logs) = await _waitLogs(tester, state, cardId, 1);
    expect(logs, 1);
    expect(after['ivl'], 3); // 间隔 1 天 --记得--> 3 天
    expect(after['reps'], 2);
  });

  testWidgets('2.4 未翻面时数字键不评分', (tester) async {
    final state = await boot(tester);
    final cardId = state.due.first.cardId;

    await _ctrl(tester, LogicalKeyboardKey.keyR);
    await _waitFor(tester, find.text(_reviewMark), what: '复习页卡片');

    await _press(tester, LogicalKeyboardKey.digit3); // 未翻面直接按
    await _settleForNoWrite(tester);
    var (after, logs) = await _cardState(tester, state, cardId);
    expect(logs, 0, reason: '未翻面不得评分');
    expect(after['ivl'], 1);
    expect(after['reps'], 1);

    // 正向对照：空格确实到达了本页（否则上面的「无写入」是空断言），
    // 且翻面本身不写任何东西
    await _press(tester, LogicalKeyboardKey.space);
    await _waitFor(tester, find.textContaining('忘了'), what: '评分区（正向对照）');
    await _settleForNoWrite(tester);
    (after, logs) = await _cardState(tester, state, cardId);
    expect(logs, 0, reason: '只翻面不评分，不得写库');
    expect(after['ivl'], 1);
  });

  testWidgets('2.5 回归：离开复习页后按 3 不得评分', (tester) async {
    final state = await boot(tester);
    final cardId = state.due.first.cardId;

    await _ctrl(tester, LogicalKeyboardKey.keyR); // 进复习
    await _waitFor(tester, find.text(_reviewMark), what: '复习页卡片');
    await _press(tester, LogicalKeyboardKey.space); // 翻面（可评分状态）
    await _waitFor(tester, find.textContaining('忘了'), what: '评分区');
    await _ctrl(tester, LogicalKeyboardKey.keyI); // 切到短语集
    await _waitFor(tester, find.text(_phraseMark), what: '短语集页');

    await _press(tester, LogicalKeyboardKey.digit3); // 隐藏页不得吃这个键
    await _press(tester, LogicalKeyboardKey.space);
    await _settleForNoWrite(tester);

    final (after, logs) = await _cardState(tester, state, cardId);
    expect(logs, 0);
    expect(after['ivl'], 1);
    expect(after['reps'], 1);
    expect(after['lapses'], 0);
  });

  testWidgets('2.5b isActive 守卫：非当前页即使被强行给焦点也不处理按键', (tester) async {
    final state = await seed(tester);
    final cardId = state.due.first.cardId;

    // 直接挂复习页（不经外壳，独立验证页面自身的 isActive 守卫），isActive: false 并强制给焦点
    await tester.pumpWidget(
        MaterialApp(home: ReviewPage(state: state, isActive: false)));
    await _settle(tester);
    await _waitFor(tester, find.text(_reviewMark), what: '非激活页的卡片');
    _reviewFocusNode(tester).requestFocus();
    await _settle(tester);

    await _press(tester, LogicalKeyboardKey.space);
    expect(find.text(_reviewMark), findsOneWidget,
        reason: '非激活页不得翻面');
    await _press(tester, LogicalKeyboardKey.digit3);
    await _settleForNoWrite(tester);
    var (_, logs) = await _cardState(tester, state, cardId);
    expect(logs, 0, reason: '非激活页不得写库');

    // 正向对照：同一页 isActive: true 时按键必须生效（否则上面是空断言）
    await tester.pumpWidget(
        MaterialApp(home: ReviewPage(state: state, isActive: true)));
    await _waitFor(tester, find.text(_reviewMark), what: '激活后的卡片');
    _reviewFocusNode(tester).requestFocus();
    await _settle(tester);
    await _press(tester, LogicalKeyboardKey.space);
    await _waitFor(tester, find.textContaining('忘了'), what: '激活后翻面生效');
    (_, logs) = await _cardState(tester, state, cardId);
    expect(logs, 0, reason: '仅翻面不评分');
  });

  testWidgets('2.6 回归：离开查词页后输入不得落进隐藏搜索框', (tester) async {
    await boot(tester);

    // 起始：查词页持有输入连接（SearchPage initState 请求焦点）
    expect(tester.testTextInput.hasAnyClients, isTrue,
        reason: '查词页启动时应聚焦搜索框');
    tester.testTextInput.enterText('abandon');
    await _settle(tester);
    expect(_searchField(tester).controller!.text, 'abandon');

    // 切到生词本：隐藏的搜索框必须交出输入连接
    await _ctrl(tester, LogicalKeyboardKey.keyB);
    await _waitFor(tester, _mark(_notebookMark), what: '生词本页');
    await _settleForNoWrite(tester);
    expect(tester.testTextInput.hasAnyClients, isFalse,
        reason: '隐藏的查词页必须交出输入连接（否则文本/空格会打进看不见的输入框）');
    expect(_searchField(tester).focusNode?.hasFocus, isFalse,
        reason: '隐藏的搜索框不得持有焦点');
    if (tester.testTextInput.hasAnyClients) {
      // 缺陷存在时这里会把文本投进隐藏搜索框，下面的断言随即失败
      tester.testTextInput.enterText('zzz');
      await _settle(tester);
    }
    expect(_searchField(tester).controller!.text, 'abandon');

    // 切回查词页：焦点应还给搜索框
    await _ctrl(tester, LogicalKeyboardKey.keyF);
    expect(tester.testTextInput.hasAnyClients, isTrue,
        reason: '切回查词页应把焦点还给搜索框');
    expect(_searchField(tester).controller!.text, 'abandon');
  });

  testWidgets('2.6b 回归：Tab 遍历不得走进隐藏页的控件', (tester) async {
    await boot(tester);
    await _ctrl(tester, LogicalKeyboardKey.keyB);
    await _waitFor(tester, _mark(_notebookMark), what: '生词本页');

    // 生词本页本身没有输入控件；隐藏页的控件不该被 Tab 走到。
    // （本用例守的是「隐藏页不得被 Tab 聚焦」这个行为，不绑定具体实现。）
    for (var i = 0; i < 8; i++) {
      await _press(tester, LogicalKeyboardKey.tab);
      expect(_searchField(tester).focusNode!.hasFocus, isFalse,
          reason: '第 ${i + 1} 次 Tab 后焦点进了隐藏的搜索框');
    }
  });

  testWidgets('3.2 侧栏快捷键提示与绑定同源', (tester) async {
    await boot(tester);
    // _nav 是单点数据源：提示文案由 SingleActivator 派生，与 CallbackShortcuts
    // 的 bindings 同源——两侧不会再漂移（漂了这条就会红）。
    for (final hint in ['Ctrl+F', 'Ctrl+B', 'Ctrl+R', 'Ctrl+I', 'Ctrl+E']) {
      expect(find.text(hint), findsOneWidget, reason: '侧栏应显示 $hint');
    }
  });
}
