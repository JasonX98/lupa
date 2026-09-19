// 详情弹窗的 AI 区块：真实渲染（这也是漏掉 bug 的那一层 ——
// 之前只测了 AiSection 组件本身，没测详情弹窗怎么用它）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:lupa/ai/card.dart';
import 'package:lupa/ai/enrich.dart';
import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/notebook/repo.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/widgets/word_detail_dialog.dart';

Directory _tmp(String t) => Directory(p.join(Directory.systemTemp.path,
    'lupa_dlg_${t}_${DateTime.now().microsecondsSinceEpoch}'))
  ..createSync(recursive: true);

Future<AppState> _init(Directory cfg, Directory data,
    {bool aiEnabled = false, String apiKey = ''}) async {
  setConfigHomeOverride(cfg.path);
  setDataHomeOverride(data.path);
  File(p.join(cfg.path, configFile)).writeAsStringSync(json.encode({
    'providers': {
      'youdao': {'phonetic_url': 'u', 'tts_url': 't'},
      'deepseek': {
        'base_url': 'http://127.0.0.1:9',
        'model': 'deepseek-flash',
        'api_key': apiKey,
      },
    },
    'settings': {
      'ai': {'enabled': aiEnabled, 'providerName': 'deepseek', 'autoEnrich': false},
    },
  }), encoding: utf8);
  final s = AppState();
  await s.init();
  return s;
}

/// [source] 默认 dict：**词库词 + AI 旁表**才是最典型的组合 ——
/// hoax 是词库词（addWord 写入，来源 dict），之后才补的 AI 例句。
/// 只有词库未收录、由 AI 生成整卡的词，来源才是 ai。
NotebookEntry _entry(String word,
        {List<WordAiGroup> ai = const [], NoteSource source = NoteSource.dict}) =>
    NotebookEntry(
      noteId: 1,
      cardId: 1,
      word: word,
      phonetic: 'həʊks',
      translation: 'vt. 欺骗，哄骗，愚弄\nn. 愚弄人，恶作剧',
      definition: 'subject to a playful hoax',
      exchange: '',
      tags: '',
      cardType: 0,
      queue: 0,
      due: 0,
      ivl: 0,
      reps: 0,
      lapses: 0,
      addedAt: 0,
      aiGroups: ai,
      source: source,
    );

/// 等真实 DB IO（sqflite ffi 隔离区）走完：每轮烧一点真实时间，再 pump 把
/// 已排队的回调冲刷出来。不要用 pumpAndSettle —— 这里等的是 isolate 往返，
/// 不是动画（照 phrase_ui_test 的既有做法）。
Future<void> _settleDb(WidgetTester tester, bool Function() done,
    {int maxRounds = 40, int ms = 60}) async {
  for (var i = 0; i < maxRounds && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump(Duration(milliseconds: ms));
  }
}

/// 等弹窗把 _loading 走完（body 出现即算就绪）。
Future<void> _settleDialog(WidgetTester tester) async {
  await _settleDb(tester, () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
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

  testWidgets('AI 就绪 + 词无 AI 内容 -> 必须给出可点的「AI 补齐」', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = (await tester.runAsync(
        () => _init(cfg, data, aiEnabled: true, apiKey: 'sk-x')))!;
    expect(s.aiReady, isTrue);

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WordDetailDialog(state: s, entry: _entry('hoax')))));
    // 弹窗 _load() 会查词库/音标（真实 IO）-> 用 runAsync 让它完成
    await _settleDialog(tester);

    // 核心断言：不能只有文案
    expect(find.text('AI 补齐'), findsOneWidget,
        reason: '词无 AI 内容时必须能点补齐（曾只有文案、无按钮）');
    expect(find.byType(OutlinedButton), findsWidgets);
    expect(find.textContaining('可点下方'), findsNothing,
        reason: '文案不应承诺「点下方」——按钮就在同一行');
  });

  testWidgets('AI 未启用且词无 AI 内容 -> 整个 AI 区块不渲染（不在每个词上刷提示）',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = (await tester.runAsync(() => _init(cfg, data)))!;
    expect(s.aiReady, isFalse);

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WordDetailDialog(state: s, entry: _entry('hoax')))));
    await _settleDialog(tester);

    // 设计：if (nb.hasAi || aiReady) 才渲染 AI 区块。
    // AI 关 + 该词也没 AI 内容 -> 什么都不显示（比在每个词上显示「AI 未启用」更像话）。
    expect(find.text('AI 补齐'), findsNothing);
    expect(find.textContaining('AI 未启用'), findsNothing);
    expect(find.textContaining('尚无 AI 例句'), findsNothing);
  });

  testWidgets('已有 AI 内容 -> 展示例句与搭配 + 「重新生成」', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = (await tester.runAsync(
        () => _init(cfg, data, aiEnabled: true, apiKey: 'sk-x')))!;
    final entry = _entry('hoax', ai: [
      const WordAiGroup(
        id: 1,
        kind: WordAiGroup.kindSense,
        label: 'n.',
        gloss: '愚弄人的事',
        examples: [
          WordAiExample(en: 'It was just a cruel hoax.', zh: '那只是个残酷的恶作剧。')
        ],
      ),
      const WordAiGroup(
        id: 2,
        kind: WordAiGroup.kindCollocation,
        label: 'hoax call',
        gloss: '恶作剧电话',
        examples: [
          WordAiExample(en: 'Police traced the hoax call.', zh: '警方追查了那通恶作剧电话。')
        ],
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: WordDetailDialog(state: s, entry: entry))));
    await _settleDialog(tester);

    expect(find.text('It was just a cruel hoax.'), findsOneWidget);
    expect(find.text('那只是个残酷的恶作剧。'), findsOneWidget);
    expect(find.text('hoax call'), findsOneWidget);
    expect(find.text('重新生成'), findsOneWidget);
    expect(find.text('AI 补齐'), findsNothing,
        reason: '已有内容时不该出现「补齐」');
    expect(find.text('AI 生成'), findsNothing,
        reason: '该卡来源是 dict（词库词 + 旁表 AI 例句），不是 AI 整卡');
  });

  testWidgets('AI 整卡来源的卡 -> 详情里标注「AI 生成」', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = (await tester.runAsync(
        () => _init(cfg, data, aiEnabled: true, apiKey: 'sk-x')))!;
    final entry = _entry('limerence',
        source: NoteSource.ai,
        ai: [
          const WordAiGroup(
            id: 1,
            kind: WordAiGroup.kindSense,
            label: 'n.',
            gloss: '痴恋',
            examples: [WordAiExample(en: 'He was in limerence.', zh: '他陷入痴恋。')],
          ),
        ]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: WordDetailDialog(state: s, entry: entry))));
    await _settleDialog(tester);
    expect(find.text('AI 生成'), findsOneWidget);
  });

  _freshResultTests();
}

// ---- 回归：补齐后必须**当场**显示，不需要关掉弹窗再打开 ----
//
// 为什么用纯函数而不是起 stub 服务器跑完整往返：
// 从 `tester.tap` 触发真实 IO（DB -> HTTP -> 写库 -> refresh）在 widget test 里
// 需要把点击也放进 runAsync，与 fake-async 交错后既慢又不稳定（实测 5s+ 且
// 请求根本发不出去）。而缺陷的本质是**一个渲染决策**：
// 「手上这份不可变的 NotebookEntry 快照 vs 刚生成的结果，该渲染哪个」。
// 把它抽成纯函数后可以毫秒级、确定性地测到。
void _freshResultTests() {
  AiOutcome freshOutcome(String word) {
    final card = parseAiCard(json.encode({
      'word': word,
      'is_known_word': true,
      'senses': [
        {
          'pos': 'n.',
          'gloss': '小枝，细枝',
          'examples': [
            {'en': 'A twig snapped under his foot.', 'zh': '一根小树枝在他脚下折断了。'}
          ]
        }
      ],
      'collocations': [],
    })).card!;
    return AiOutcome(card: card);
  }

  group('详情弹窗渲染哪一份 AI 内容', () {
    test('打开的瞬间：无 AI 内容 -> 没有可渲染的 outcome', () {
      final stale = _entry('twig');
      expect(stale.hasAi, isFalse);
      expect(resolveDetailAi(fresh: null, entry: stale), isNull);
      expect(detailHasAi(fresh: null, entry: stale), isFalse);
    });

    test('补齐成功后：新结果优先于打开时的空快照（回归点）', () {
      final stale = _entry('twig'); // 打开弹窗时的快照：aiGroups 是空的
      final fresh = freshOutcome('twig');

      // 这就是 bug 的核心：只看快照会拿到 null（界面空着），
      // 于是用户必须关掉弹窗再打开。
      expect(aiOutcomeFromNotebook(stale), isNull);

      final picked = resolveDetailAi(fresh: fresh, entry: stale);
      expect(picked, same(fresh), reason: '应渲染刚生成的那份，而不是旧快照');
      expect(picked!.card!.senses.single.examples.single.en,
          'A twig snapped under his foot.');
      // 同时状态要切换成「已有内容」，界面才会把「AI 补齐」换成「重新生成」
      expect(detailHasAi(fresh: fresh, entry: stale), isTrue);
    });

    test('没有新结果时：用库里读回的快照', () {
      final withAi = _entry('twig', ai: [
        const WordAiGroup(
          id: 1,
          kind: WordAiGroup.kindSense,
          label: 'n.',
          gloss: '小枝',
          examples: [WordAiExample(en: 'A twig.', zh: '一根小枝。')],
        ),
      ]);
      final picked = resolveDetailAi(fresh: null, entry: withAi);
      expect(picked, isNotNull);
      expect(picked!.card!.senses.single.label, 'n.');
      expect(picked.card!.senses.single.examples.single.en, 'A twig.');
      expect(detailHasAi(fresh: null, entry: withAi), isTrue);
    });

    test('快照与搭配分组都正确映射（sense / collocation 分流）', () {
      final withAi = _entry('twig', ai: [
        const WordAiGroup(
          id: 1,
          kind: WordAiGroup.kindSense,
          label: 'n.',
          gloss: '小枝',
          examples: [WordAiExample(en: 'A twig.', zh: '')],
        ),
        const WordAiGroup(
          id: 2,
          kind: WordAiGroup.kindCollocation,
          label: 'twig to it',
          gloss: '明白过来',
          examples: [WordAiExample(en: 'He twigged to it.', zh: '他明白了。')],
        ),
      ]);
      final c = aiOutcomeFromNotebook(withAi)!.card!;
      expect(c.senses.length, 1, reason: '搭配不该混进 senses');
      expect(c.collocations.length, 1);
      expect(c.collocations.single.label, 'twig to it');
    });

    test('降级补齐（label 为空的 sense 组）映射为顶层 examples', () {
      final plain = _entry('online', ai: [
        const WordAiGroup(
          id: 1,
          kind: WordAiGroup.kindSense,
          label: '', // 降级内容：无词性 label
          gloss: '',
          examples: [WordAiExample(en: 'She is online.', zh: '她在线。')],
        ),
      ]);
      final c = aiOutcomeFromNotebook(plain)!.card!;
      expect(c.senses, isEmpty);
      expect(c.examples.single.en, 'She is online.');
    });
  });
}
