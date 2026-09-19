// 查词页 AI 段落与未收录三段式的 UI 测试。
//
// 全部用本地 stub 传输层（不触网、不需要密钥）。AppState 的 AI 编排通过
// setAiConnection + 一个假 AiClient 注入 —— 但 AppState.aiClient() 内部构造
// 客户端，所以这里改为直接断言 UI 行为与 AppState 的状态机，AI 结果通过
// _aiOutcomes 注入（loadAiFor 的缓存分支）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:lupa/ai/card.dart' as ai_card;
import 'package:lupa/ai/enrich.dart' as ai_enrich;
import 'package:lupa/ai/pos.dart';
import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/notebook/repo.dart' show NoteProvenance, NoteSource, WordAiGroup;
import 'package:lupa/pages/search_page.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/widgets/word_bits.dart';

Directory _tmp(String tag) => Directory(p.join(
    Directory.systemTemp.path,
    'lupa_aiui_${tag}_${DateTime.now().microsecondsSinceEpoch}'))
  ..createSync(recursive: true);

/// 用临时 config/data 目录初始化 AppState（不碰真实数据）。
///
/// [aiEnabled] 与 [apiKey] 决定 AI 是否 ready。
/// [withDict] 为 true 时把真实词库复制进临时数据目录 —— 查词测试需要它，
/// 否则 queryWord 会因缺 dict.sqlite 抛错，走到 _ErrorCard 而不是三段式。
Future<AppState> _init(Directory cfg, Directory data,
    {bool aiEnabled = false, String apiKey = '', bool withDict = false}) async {
  setConfigHomeOverride(cfg.path);
  setDataHomeOverride(data.path);
  if (withDict) {
    final src = File(p.join(
        Platform.environment['LUPA_HOME'] ?? '../data', 'dict.sqlite'));
    if (src.existsSync()) {
      src.copySync(p.join(data.path, 'dict.sqlite'));
    }
  }
  File(p.join(cfg.path, configFile)).writeAsStringSync(json.encode({
    'default_provider': 'youdao',
    'providers': {
      'youdao': {'phonetic_url': 'u', 'tts_url': 't'},
      'deepseek': {
        'base_url': 'http://127.0.0.1:9',
        'model': 'deepseek-flash',
        'api_key': apiKey,
        'timeout_sec': 5,
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

/// 直接构造一个成功的 AiOutcome（不经过网络）。
ai_enrich.AiOutcome _okOutcome(String word, {bool partial = false}) {
  final card = ai_card.parseAiCard(json.encode({
    'word': word,
    'canonical': word,
    'is_known_word': true,
    'senses': [
      {
        'pos': 'n.',
        'gloss': '记录',
        'examples': [
          {'en': 'He kept a $word of it.', 'zh': '他记录了下来。'}
        ]
      },
      {
        'pos': 'vt.',
        'gloss': '记录',
        'examples': [
          {'en': 'She will $word it.', 'zh': '她会记录。'}
        ]
      },
    ],
    'collocations': [
      {
        'phrase': '$word a video',
        'gloss': '录制视频',
        'examples': [
          {'en': 'They $word a video.', 'zh': '他们录视频。'}
        ]
      }
    ],
  })).card!;
  return ai_enrich.AiOutcome(
      card: card, partial: partial, reason: partial ? '缺少 vi.' : '');
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

  group('AI 段落渲染（AiSection 纯组件）', () {
    Widget host(Widget child) =>
        MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

    testWidgets('loading 态显示进度且不阻塞', (tester) async {
      await tester.pumpWidget(host(const AiSection(outcome: null, loading: true)));
      expect(find.textContaining('正在补齐'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('idle 态：可请求时给按钮', (tester) async {
      await tester.pumpWidget(host(AiSection(
        outcome: null,
        onRequest: () {},
      )));
      expect(find.text('AI 补齐'), findsOneWidget);
    });

    testWidgets('idle 态：不可用时说明原因 + 去设置', (tester) async {
      await tester.pumpWidget(host(AiSection(
        outcome: null,
        unavailableReason: 'AI 未启用，可在设置中开启并填入密钥',
        onGoSettings: () {},
      )));
      expect(find.textContaining('AI 未启用'), findsOneWidget);
      expect(find.text('去设置'), findsOneWidget);
      expect(find.text('AI 补齐'), findsNothing);
    });

    testWidgets('失败态：提示原因 + 重试', (tester) async {
      await tester.pumpWidget(host(AiSection(
        outcome: const ai_enrich.AiOutcome(reason: 'AI 补齐失败（网络不可用）'),
        onRegenerate: () {},
      )));
      expect(find.textContaining('网络不可用'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });

    testWidgets('就绪态：按词性分组渲染例句与搭配', (tester) async {
      await tester.pumpWidget(host(AiSection(
        outcome: _okOutcome('record'),
        onRegenerate: () {},
      )));
      expect(find.text('AI 补充'), findsOneWidget);
      expect(find.text('n.'), findsOneWidget);
      expect(find.text('vt.'), findsOneWidget);
      expect(find.text('He kept a record of it.'), findsOneWidget);
      expect(find.text('他记录了下来。'), findsOneWidget);
      expect(find.text('常用搭配'), findsOneWidget);
      expect(find.text('record a video'), findsOneWidget);
      expect(find.text('重新生成'), findsOneWidget);
    });

    testWidgets('部分缺失时标注「部分词性缺例句」', (tester) async {
      await tester.pumpWidget(host(AiSection(
        outcome: _okOutcome('record', partial: true),
      )));
      expect(find.text('部分词性缺例句'), findsOneWidget);
    });

    testWidgets('来自缓存时标注「来自缓存」', (tester) async {
      await tester.pumpWidget(host(AiSection(
        outcome: ai_enrich.AiOutcome(card: _okOutcome('go').card, fromCache: true),
      )));
      expect(find.text('来自缓存'), findsOneWidget);
    });

    testWidgets('降级内容用「通用例句」标题、不出现词性分组', (tester) async {
      final card = ai_card.parseAiCard(json.encode({
        'word': 'online',
        'is_known_word': true,
        'examples': [
          {'en': 'She is online now.', 'zh': '她在线。'}
        ],
      })).card!;
      await tester.pumpWidget(
          host(AiSection(outcome: ai_enrich.AiOutcome(card: card))));
      expect(find.text('通用例句'), findsOneWidget);
      expect(find.text('n.'), findsNothing);
      expect(find.text('She is online now.'), findsOneWidget);
    });
  });

  group('AppState 的 AI 状态机', () {
    test('AI 未就绪时不构造客户端、缓存记为未启用', () async {
      final s = await _init(cfg, data);
      expect(s.aiReady, isFalse);
      expect(s.aiClient(), isNull);
      final o = await s.loadAiFor('record', feature: ai_card.AiFeature.enrich);
      expect(o!.card, isNull);
      expect(o.reason, contains('未启用'));
      // 已缓存该结论：第二次不重复走流程
      expect(s.aiOutcomeOf('record'), isNotNull);
    });

    test('就绪但无网络时返回失败且不抛异常', () async {
      final s = await _init(cfg, data, aiEnabled: true, apiKey: 'sk-x');
      expect(s.aiReady, isTrue);
      final o = await s.loadAiFor('record', feature: ai_card.AiFeature.enrich);
      expect(o!.card, isNull);
      expect(o.reason, isNotEmpty);
      expect(s.aiOutcomeOf('record'), isNotNull);
    });

    test('结果按词缓存，重复请求不重复发起', () async {
      final s = await _init(cfg, data);
      await s.loadAiFor('record', feature: ai_card.AiFeature.enrich);
      final first = s.aiOutcomeOf('record');
      await s.loadAiFor('record', feature: ai_card.AiFeature.enrich);
      expect(identical(s.aiOutcomeOf('record'), first), isTrue);
    });

    test('forgetAi 清掉单词状态', () async {
      final s = await _init(cfg, data);
      await s.loadAiFor('record', feature: ai_card.AiFeature.enrich);
      expect(s.aiOutcomeOf('record'), isNotNull);
      s.forgetAi('record');
      expect(s.aiOutcomeOf('record'), isNull);
    });

    test('requestOpenSettings 递增计数（AppShell 据此切页）', () async {
      final s = await _init(cfg, data);
      expect(s.openSettingsRequests, 0);
      s.requestOpenSettings();
      expect(s.openSettingsRequests, 1);
      s.requestOpenSettings();
      expect(s.openSettingsRequests, 2);
    });

    test('切库清空 AI 状态', () async {
      final s = await _init(cfg, data);
      await s.loadAiFor('record', feature: ai_card.AiFeature.enrich);
      expect(s.aiOutcomeOf('record'), isNotNull);
      final dst = _tmp('dst');
      await s.switchDataDir(dst.path, copyExisting: false);
      expect(s.aiOutcomeOf('record'), isNull);
      dst.deleteSync(recursive: true);
    });
  });

  group('enrichMode 分流决定 UI 是否显示 AI 入口', () {
    test('缩写/专名（none）不显示入口', () {
      // Mr 的释义无词性前缀且含大写 -> none
      expect(enrichMode('Mr', '先生\n[计] 存储器回收程序'), EnrichMode.none);
    });

    test('内容词（degraded）走降级补齐', () {
      expect(enrichMode('online', '[计] 联机'), EnrichMode.degraded);
    });

    test('多词性词（full）走分组补齐', () {
      expect(enrichMode('record', 'n. 记录\nvt. 记录'), EnrichMode.full);
    });
  });

  group('查词页未收录三段式', () {
    // 注意：SearchPage 的 _submit 走真实 sqflite IO，在 testWidgets 的 fake-async
    // 区里永不完成 → 必须用 tester.runAsync 包住「输入 + 等待」。
    // 另：结果卡内容较多，需要放大画布，否则会撞 RenderFlex overflow。
    void bigCanvas(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('词库未收录且无出路时提示未收录', (tester) async {
      bigCanvas(tester);
      final s = await tester.runAsync(() => _init(cfg, data, withDict: true));
      if (!File(p.join(data.path, 'dict.sqlite')).existsSync()) {
        return; // 无真实词库时跳过（CI 上没设 LUPA_HOME 的情形）
      }
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: SearchPage(state: s!))));
      await tester.pump();

      await tester.runAsync(() async {
        await tester.enterText(find.byType(TextField).first, 'zzzznotaword');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();

      expect(find.text('词库未收录'), findsOneWidget);
      expect(find.textContaining('AI 未启用'), findsOneWidget);
      expect(find.text('去设置'), findsOneWidget);
    });

    testWidgets('词库命中时展示词条，AI 未启用时不出现 AI 补齐按钮', (tester) async {
      bigCanvas(tester);
      final s = await tester.runAsync(() => _init(cfg, data, withDict: true));
      if (!File(p.join(data.path, 'dict.sqlite')).existsSync()) return;
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: SearchPage(state: s!))));
      await tester.pump();

      await tester.runAsync(() async {
        await tester.enterText(find.byType(TextField).first, 'abandon');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();

      // 词库命中：展示词条，且因 AI 未就绪而不出现可点的「AI 补齐」
      expect(find.text('abandon'), findsWidgets);
      expect(find.text('AI 补齐'), findsNothing);
      expect(find.textContaining('AI 未启用'), findsOneWidget);
    });
  });

  _detailTests();
  _idleContractTests();
}

// ---- 详情弹窗：展示已保存的 AI 快照（不是重新请求）----
void _detailTests() {
  group('详情弹窗展示 AI 快照', () {
    test('NoteProvenance 编解码（老笔记无 data 时视为词库来源）', () {
      expect(NoteProvenance.decode(null).source, NoteSource.dict);
      expect(NoteProvenance.decode('').source, NoteSource.dict);
      expect(NoteProvenance.decode('not json').source, NoteSource.dict);
      expect(NoteProvenance.decode('{}').source, NoteSource.dict);
      expect(NoteProvenance.decode('{"source":"ai"}').source, NoteSource.ai);

      final p = const NoteProvenance(
          source: NoteSource.ai, provider: 'deepseek/x', promptVersion: 3);
      final back = NoteProvenance.decode(p.encode());
      expect(back.source, NoteSource.ai);
      expect(back.provider, 'deepseek/x');
      expect(back.promptVersion, 3);
    });

    test('WordAiGroup 区分 sense 与 collocation', () {
      const s = WordAiGroup(
          id: 1, kind: 'sense', label: 'n.', gloss: '记录', examples: []);
      const c = WordAiGroup(
          id: 2, kind: 'collocation', label: 'a video', gloss: '', examples: []);
      expect(s.isSense, isTrue);
      expect(s.isCollocation, isFalse);
      expect(c.isSense, isFalse);
      expect(c.isCollocation, isTrue);
    });
  });
}

// ---- 回归：idle 态不得出现「只有文案、没有按钮」的死状态 ----
// 实测踩过：详情弹窗传了 onRegenerate 而 AiSection 的 idle 分支当时只读
// onRequest，于是显示了「该词尚无 AI 例句，可点下方补齐」却下方无物。
void _idleContractTests() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

  group('AiSection idle 态契约：有文案就必须有出路', () {
    testWidgets('只传 onRegenerate 时也要渲染「AI 补齐」按钮', (tester) async {
      await tester.pumpWidget(host(AiSection(
        outcome: null,
        unavailableReason: '该词尚无 AI 例句',
        onRegenerate: () {},
      )));
      expect(find.text('AI 补齐'), findsOneWidget,
          reason: 'idle 态传 onRegenerate 也应能补齐（idle 没有内容可覆盖）');
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('只传 onRequest 时渲染按钮', (tester) async {
      await tester.pumpWidget(host(AiSection(outcome: null, onRequest: () {})));
      expect(find.text('AI 补齐'), findsOneWidget);
    });

    testWidgets('有文案但无任何出路 -> 整体不渲染（不承诺做不到的事）',
        (tester) async {
      await tester.pumpWidget(host(const AiSection(
        outcome: null,
        unavailableReason: '该词尚无 AI 例句，可点下方补齐',
      )));
      expect(find.textContaining('可点下方'), findsNothing,
          reason: '无按钮时不得显示「可点下方」这类文案');
      expect(find.textContaining('尚无 AI 例句'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('仅 onGoSettings -> 只渲染「去设置」', (tester) async {
      await tester.pumpWidget(host(AiSection(
        outcome: null,
        unavailableReason: 'AI 未启用',
        onGoSettings: () {},
      )));
      expect(find.text('去设置'), findsOneWidget);
      expect(find.text('AI 补齐'), findsNothing);
    });
  });
}
