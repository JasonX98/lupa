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
}
