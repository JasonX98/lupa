// 短语集 UI 冒烟：PhrasePage / PhraseReviewPage / 组件 / AppShell 入口与 Ctrl+I。
// 用临时 configHome/dataHome 驱动 init 后的 AppState（不碰真实数据）。
// 注意：只 pump() 单帧断言结构；DB IO 用 runAsync 完成，不用 pumpAndSettle。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/pages/phrase_page.dart';
import 'package:lupa/pages/phrase_review_page.dart';
import 'package:lupa/phrase/repo.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/widgets/app_shell.dart';
import 'package:lupa/widgets/flip_card.dart';
import 'package:lupa/widgets/phrase_bits.dart';

Directory _tmp(String tag) => Directory(p.join(
    Directory.systemTemp.path,
    'lupa_phrase_ui_${tag}_${DateTime.now().microsecondsSinceEpoch}'))
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

/// 等真实 DB IO（sqflite ffi 隔离区）走完：每轮烧一点真实时间，再 pump 把
/// 已排队的回调冲刷出来。不要用 pumpAndSettle —— 这里等的是 isolate 往返，不是动画。
Future<void> _settleDb(WidgetTester tester, bool Function() done,
    {int maxRounds = 30, int ms = 60}) async {
  for (var i = 0; i < maxRounds && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump(Duration(milliseconds: ms));
  }
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
    try {
      cfg.deleteSync(recursive: true);
    } catch (_) {}
    try {
      data.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('5.3 phraseDueLabel 文案', () {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    expect(phraseDueLabel(0, 0), '新短语');
    expect(phraseDueLabel(1, nowSec - 60), '今天');
    expect(phraseDueLabel(2, nowSec + 5 * 86400).length, 5); // MM-dd
  });

  testWidgets('5.3 ExampleEditRow 渲染英文与中文输入', (tester) async {
    final c = ExampleEditRowController(enText: 'Hello world', zhText: '你好世界');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ExampleEditRow(controller: c, onRemove: () {})),
    ));
    expect(find.text('Hello world'), findsOneWidget);
    expect(find.text('你好世界'), findsOneWidget);
    c.dispose();
  });

  testWidgets('5.2 PhrasePage 空态渲染', (tester) async {
    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PhrasePage(state: state, isActive: true, onGotoReview: () {}),
      ),
    ));
    await tester.pump();

    expect(find.text('短语集'), findsOneWidget);
    expect(find.text('记录短语'), findsOneWidget);
    expect(find.text('短语集还是空的'), findsOneWidget);
  });

  testWidgets('5.2 PhrasePage 展示已记录短语', (tester) async {
    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.runAsync(() => state.addPhraseEntry(const PhraseInput(
          phrase: 'bite the bullet',
          meaning: '硬着头皮上',
          lit: '咬子弹',
        )));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PhrasePage(state: state, isActive: true, onGotoReview: () {}),
      ),
    ));
    await tester.pump();

    expect(find.text('bite the bullet'), findsOneWidget);
    expect(find.text('硬着头皮上'), findsOneWidget);
    expect(find.text('咬子弹'), findsOneWidget);
  });

  testWidgets('6.1 PhraseReviewPage 构建并进入加载态', (tester) async {
    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: PhraseReviewPage(state: state, isActive: true)),
    ));
    await tester.pump();

    // 页面内部 _reload() 走真实 DB IO，fake-async 下停在加载态；
    // 队列/评分逻辑由 phrase_state_test 覆盖，这里只做构建冒烟。
    expect(find.byType(PhraseReviewPage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('5.1 AppShell 有短语集入口，点击进入', (tester) async {
    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.pumpWidget(MaterialApp(home: AppShell(state: state)));
    await tester.pump();

    // 侧栏有「短语集」入口（其他页 offstage，find.text 默认跳过）
    expect(find.text('短语集'), findsOneWidget);

    await tester.tap(find.text('短语集'));
    await tester.pump();
    expect(find.text('记录短语'), findsOneWidget);
  });

  test('5.3 formatAddedDate 格式化', () {
    expect(formatAddedDate(0).length, 10); // YYYY-MM-DD
    expect(formatAddedDate(0), '1970-01-01');
  });

  testWidgets('5.2 详情弹窗渲染新样式区块', (tester) async {
    final entry = PhraseEntry(
      id: 1,
      pId: '1',
      phrase: 'bite the bullet',
      lit: '咬子弹',
      meaning: '硬着头皮上',
      origin: '战地手术典故',
      scene: '面对困难任务时',
      sceneTag: '口语',
      tags: const ['口语'],
      addedAt: 1788968481,
      state: 2,
      due: 0,
      ivl: 3,
      reps: 1,
      lapses: 0,
      examples: const [
        PhraseExample(en: 'I bit the bullet.', zh: '我咬牙挺住了。'),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showPhraseDetailDialog(
                ctx,
                AppState(),
                entry,
                onEdit: (_) {},
                onDelete: (_) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('bite the bullet'), findsOneWidget);
    expect(find.text('字面直译：咬子弹'), findsOneWidget);
    expect(find.text('核心释义'), findsOneWidget);
    expect(find.text('起源与词源'), findsOneWidget);
    expect(find.text('使用场景'), findsOneWidget);
    expect(find.text('例句'), findsOneWidget);
    expect(find.text('Esc 关闭'), findsOneWidget);
    expect(find.textContaining('收录于'), findsOneWidget);
    expect(find.text('硬着头皮上'), findsOneWidget);
    expect(find.text('I bit the bullet.'), findsOneWidget);
    expect(find.text('我咬牙挺住了。'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('编辑'), findsOneWidget);
  });

  testWidgets('5.4 表单多条场景：回车新增 / 加一条 / 删除 / 空白丢弃 → 详情分条 → 编辑回填',
      (tester) async {
    const scenes = [
      '争论 / 分歧时：对方正要反驳，先喊一句稳住局面',
      '分享大胆想法时：想发表不寻常观点前打预防针（如 "Hear me out, but I think..."）',
      '解释误会时：被误解，请求完整陈述',
    ];

    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.pumpWidget(MaterialApp(home: AppShell(state: state)));
    await tester.pump();

    await tester.tap(find.text('短语集'));
    await tester.pump();
    await tester.tap(find.text('记录短语'));
    await tester.pump();

    await tester.enterText(
        find.widgetWithText(TextField, '短语 *'), 'hear me out');
    await tester.enterText(
        find.widgetWithText(TextField, '核心释义 *'), '先别急着反驳，听我说完');
    await tester.pump();

    /// 第 i 行的场景输入框
    Finder sceneField(int i) => find.descendant(
        of: find.byType(SceneEditRow).at(i), matching: find.byType(TextField));

    Future<void> typeScene(int i, String text) async {
      await tester.enterText(sceneField(i), text);
      await tester.pump();
    }

    /// 弹窗内容是滚动区，按钮可能落在 600px 测试视口之外，先滚到可见处再点
    Future<void> tapVisible(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await tester.pump();
    }

    // 表单默认给一条空场景行（使用场景不再只有单行输入框）
    expect(find.byType(SceneEditRow), findsOneWidget);

    await typeScene(0, scenes[0]);
    // 回车 = 新增下一条（真机上引擎把回车翻成 done action）
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byType(SceneEditRow), findsNWidgets(2));
    await typeScene(1, scenes[1]);

    // 「+ 加一条场景」
    await tapVisible(find.text('加一条场景'));
    expect(find.byType(SceneEditRow), findsNWidgets(3));
    await typeScene(2, scenes[2]);

    // 再加一条留空、删掉它，再加一条留空 → 验证逐条删除与空白丢弃
    await tapVisible(find.text('加一条场景'));
    expect(find.byType(SceneEditRow), findsNWidgets(4));
    await tapVisible(find.byTooltip('删除场景').last);
    expect(find.byType(SceneEditRow), findsNWidgets(3));
    await tapVisible(find.text('加一条场景'));
    expect(find.byType(SceneEditRow), findsNWidgets(4));

    // 保存：写库 + refresh 是跨 isolate 的 await 链，需逐轮烧真实时间再 pump
    await tapVisible(find.text('保存'));
    await _settleDb(tester, () => find.text('hear me out').evaluate().isNotEmpty);
    expect(find.text('hear me out'), findsOneWidget);

    // 详情：三条场景各自成条（空白行未被保存）
    await tester.tap(find.text('hear me out'));
    await tester.pump();
    await tester.pump();
    expect(find.text('使用场景'), findsOneWidget);
    for (final s in scenes) {
      expect(find.text(s), findsOneWidget);
    }

    // 编辑：回填仍是三条且顺序一致
    await tapVisible(find.text('编辑'));
    expect(find.byType(SceneEditRow), findsNWidgets(3));
    for (var i = 0; i < scenes.length; i++) {
      expect(tester.widget<TextField>(sceneField(i)).controller!.text, scenes[i]);
    }
  });

  testWidgets('5.5 复习页：场景按条展示（与详情一致）', (tester) async {
    const scenes = ['场景一：正式书面行文', '场景二：口语寒暄', '场景三：商务邮件'];

    // 复习卡在 800x600 测试视口下会溢出（既有布局，与本次改动无关）：放大视口，
    // 避免把无关的 RenderFlex overflow 当成这次的失败。
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.runAsync(() async {
      await state.addPhraseEntry(const PhraseInput(
        phrase: 'hear me out',
        meaning: '先别急着反驳，听我说完',
        scene: '场景一：正式书面行文\n场景二：口语寒暄\n场景三：商务邮件',
      ));
    });

    await tester.pumpWidget(MaterialApp(home: AppShell(state: state)));
    await _settleDb(tester, () => find.text('短语集').evaluate().isNotEmpty);

    await tester.tap(find.text('短语集'));
    await tester.pump();
    await tester.tap(find.textContaining('开始复习'));
    // 等复习卡（FlipCard）本身就绪 —— 不能等 'hear me out'：IndexedStack 的
    // 非当前页（短语列表）文本同样能被 find.text 找到
    await _settleDb(
        tester, () => find.byType(FlipCard).evaluate().isNotEmpty);
    expect(find.byType(FlipCard), findsOneWidget);

    // 点击卡片翻面（等价于空格键）→ 背面场景按条展示
    await tester.tap(find.byType(FlipCard));
    await _settleDb(
        tester, () => find.text(scenes.first).evaluate().isNotEmpty);

    for (final s in scenes) {
      expect(find.text(s), findsOneWidget);
    }
  });

  testWidgets('5.6 场景行：输入法组字中回车不新增（composing 守卫）', (tester) async {
    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.pumpWidget(MaterialApp(home: AppShell(state: state)));
    await tester.pump();

    await tester.tap(find.text('短语集'));
    await tester.pump();
    await tester.tap(find.text('记录短语'));
    await tester.pump();

    final field = find.descendant(
        of: find.byType(SceneEditRow).first, matching: find.byType(TextField));
    await tester.enterText(field, '正在组字');
    await tester.pump();

    // 模拟中文输入法候选未上屏：composing 区间有效
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '正在组字', composing: TextRange(start: 0, end: 4)));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byType(SceneEditRow), findsOneWidget,
        reason: '组字中回车应放行给输入法，不新增场景行');

    // 候选上屏（composing 清空）后再回车才新增
    tester.testTextInput
        .updateEditingValue(const TextEditingValue(text: '正在组字'));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.byType(SceneEditRow), findsNWidgets(2));
  });
}
