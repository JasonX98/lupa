// 复习界面在窗口尺寸变化下不裁剪内容（openspec: fix-review-card-overflow 需求）。
//
// 背景：复习卡是固定设计高度（短语 460 / 单词 340），外层还有进度条 / 反馈行 /
// 评分区。窗口被拖矮后这些元素总和超过视口 → Column 溢出 → 评分按钮被裁掉。
// 这里在**旧代码会溢出**的视口下走真实交互（翻面 → 评分），断言：
//   1) 无 overflow（flutter_test 遇 RenderFlex overflow 直接判失败）
//   2) 评分按钮可触达（ensureVisible 后 tap 不会 "would not hit test"）
//   3) 评分真的推进了队列（进入完成页 / 下一张）
//
// 真实 IO 走 tester.runAsync 烧时间再 pump（与 review_undo_test 同一套写法）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/notebook/repo.dart';
import 'package:lupa/phrase/repo.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/widgets/app_shell.dart';
import 'package:lupa/widgets/flip_card.dart';

/// 评分按钮文案（两页一致：`忘了（1）`）——比 '忘了' 精确，避免命中完成页统计。
const _rateAgain = '忘了（1）';

/// 完成页标记（两页一致：`共 N 张 · …`）。
const _doneMark = '共 1 张';

Directory _tmp(String tag) => Directory(p.join(
    Directory.systemTemp.path,
    'lupa_layout_${tag}_${DateTime.now().microsecondsSinceEpoch}'))
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

/// 等真实 DB IO：每轮烧一点真实时间并推进假时钟（动画也要走）。
Future<void> _settleDb(WidgetTester tester, bool Function() done,
    {int maxRounds = 30, int ms = 60}) async {
  for (var i = 0; i < maxRounds && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump(Duration(milliseconds: ms));
  }
}

/// 种子单词卡：复习中、间隔 1 天、已过期（不依赖 dict.sqlite）。
Future<void> _seedWordCard(AppState state, String word) async {
  final con = await databaseFactory.openDatabase(p.absolute(state.nbPath));
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final noteId = await con.insert('notes', {
    'n_id': 'n_$word',
    'm_id': modelId,
    'mod': now - 86400,
    'usn': 0,
    'tags': '',
    'flds': [word, '/əˈbændən/', '放弃；抛弃', 'to give up', ''].join(fieldSep),
    'sfld': word,
    'csum': 0,
    'flags': 0,
    'data': '',
  });
  await con.insert('cards', {
    'c_id': 'c_$word',
    'n_id': noteId,
    'did': deckId,
    'ord': 0,
    'mod': now - 86400,
    'usn': 0,
    'type': cardReview,
    'queue': queueNew,
    'due': now - 7200,
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
}

void main() {
  late Directory cfg;
  late Directory data;

  setUp(() {
    cfg = _tmp('cfg');
    data = _tmp('data');
  });

  tearDown(() {
    clearConfigHomeOverride();
    clearDataHomeOverride();
    for (final d in [cfg, data]) {
      try {
        if (d.existsSync()) d.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  /// 视口固定成"旧代码会溢出"的尺寸；测试结束恢复。
  void useViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// 评分按钮可触达：滚动到可见处后能真正命中点击。
  Future<void> expectReachable(WidgetTester tester, Finder f) async {
    expect(f, findsOneWidget);
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f); // warnIfMissed 默认 true：命中不到会直接失败
    await tester.pump();
  }

  testWidgets('6.2 短语复习页：600px 高的窗口不裁剪，评分可达', (tester) async {
    useViewport(tester, const Size(800, 600)); // 旧代码在此溢出 8px

    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.runAsync(() async {
      await state.addPhraseEntry(const PhraseInput(
        phrase: 'hear me out',
        meaning: '先别急着反驳，听我说完',
        scene: '场景一：正式书面行文\n场景二：口语寒暄\n场景三：商务邮件',
        examples: [
          PhraseExample(en: 'Hear me out before you judge.', zh: '先听我说完再评判。'),
        ],
      ));
    });

    await tester.pumpWidget(MaterialApp(home: AppShell(state: state)));
    await tester.pump();
    await tester.tap(find.text('短语集'));
    await tester.pump();
    await tester.tap(find.textContaining('开始复习'));
    await _settleDb(
        tester, () => find.byType(FlipCard).evaluate().isNotEmpty);

    // 翻面：背面 + 评分区（旧代码下这里就把评分区挤出视口）
    await tester.tap(find.byType(FlipCard));
    await _settleDb(tester, () => find.text(_rateAgain).evaluate().isNotEmpty);

    await expectReachable(tester, find.text(_rateAgain));
    // 评分后队列推进：唯一一张评完 → 完成页
    await _settleDb(tester, () => find.textContaining(_doneMark).evaluate().isNotEmpty);
    expect(find.textContaining(_doneMark), findsOneWidget);
    expect(find.text(_rateAgain), findsNothing);
  });

  testWidgets('6.2 单词复习页：460px 高的窗口不裁剪，评分可达', (tester) async {
    useViewport(tester, const Size(800, 460)); // 单词卡 340 + 外层元素 → 旧代码溢出

    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.runAsync(() async {
      await _seedWordCard(state, 'abandon');
      await state.refresh();
    });

    await tester.pumpWidget(MaterialApp(home: AppShell(state: state)));
    await tester.pump();
    await tester.tap(find.text('单词复习'));
    await _settleDb(
        tester, () => find.byType(FlipCard).evaluate().isNotEmpty);

    await tester.tap(find.byType(FlipCard));
    await _settleDb(tester, () => find.text(_rateAgain).evaluate().isNotEmpty);

    await expectReachable(tester, find.text(_rateAgain));
    await _settleDb(tester, () => find.textContaining(_doneMark).evaluate().isNotEmpty);
    expect(find.textContaining(_doneMark), findsOneWidget);
    expect(find.text(_rateAgain), findsNothing);
  });

  testWidgets('6.2 窗口足够高时：卡片与评分区居中且无需滚动', (tester) async {
    useViewport(tester, const Size(1000, 1000));

    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.runAsync(() async {
      await state.addPhraseEntry(const PhraseInput(
        phrase: 'hear me out',
        meaning: '先别急着反驳，听我说完',
        scene: '场景一：正式书面行文\n场景二：口语寒暄',
      ));
    });

    await tester.pumpWidget(MaterialApp(home: AppShell(state: state)));
    await tester.pump();
    await tester.tap(find.text('短语集'));
    await tester.pump();
    await tester.tap(find.textContaining('开始复习'));
    await _settleDb(
        tester, () => find.byType(FlipCard).evaluate().isNotEmpty);
    await tester.tap(find.byType(FlipCard));
    await _settleDb(tester, () => find.text(_rateAgain).evaluate().isNotEmpty);

    final viewH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    // 评分区无需滚动即可见（ensureVisible 若不需滚动就是空操作）
    expect(tester.getRect(find.text(_rateAgain)).bottom, lessThanOrEqualTo(viewH));
    // 卡片上下都有留白 = 垂直居中
    final card = tester.getRect(find.byType(FlipCard));
    expect(card.top, greaterThan(0));
    expect(card.bottom, lessThan(viewH));
  });
}
