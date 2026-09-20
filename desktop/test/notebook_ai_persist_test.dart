// 回归：查词页收藏时，该词的 AI 例句/搭配必须随笔记一并落库，
// 且**不得**因此篡改笔记「核心词条内容」的来源标记。
//
// 用户报的缺陷（截图：查词页有完整 AI 补充，生词本详情却写「该词尚无 AI 例句」）：
//   查 provenance → AI 自动补齐 → 点五角星收藏 → 生词本里点开该词 → AI 区块是空的。
//
// 根因在**写路径的接线**，不在读写任一侧本身：
//   * 读路径是对的 —— listWords → _entriesFromRows → _loadAiGroups（一次 IN 批量查询）
//     → NotebookEntry.aiGroups；详情弹窗用 detailHasAi() 决定渲染 AI 区块还是
//     「该词尚无 AI 例句」。
//   * 写路径漏了 —— _toggleStar 手里明明有 _ai?.card，却没传给 state.add()，
//     于是 word_ai_groups/word_ai_examples 里一行都没有，读回来自然为空。
//   * 既有测试没兜住：tool/verify_ai.dart 是直连 repo 调 addAiWord() 验的，
//     测的是「repo 函数本身对不对」，而不是「界面按钮把它接上了没有」。
//
// 本文件同时守第二件事（第二类缺陷）：replaceAiGroups() 曾把 notes.data 的
// source **硬编码成 ai**，于是「词库词 + AI 例句」会被标成「AI 生成」。
// spec「卡片来源标记」记的是**核心词条内容**的来源：词库词的核心内容来自词库，
// AI 只补了例句，来源必须仍是 dict。这条在旧代码里也够得着 —— 生词本详情里
// 对词库词点「AI 补齐」就会踩到（用户截图里那个按钮正是它）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lupa/ai/card.dart' as ai_card;
import 'package:lupa/ai/prompt.dart' show promptVersion;
import 'package:lupa/ai/repo.dart' as ai_repo;
import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/notebook/repo.dart';
import 'package:lupa/pages/search_page.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/widgets/word_detail_dialog.dart'
    show aiOutcomeFromNotebook, detailHasAi;

const _word = 'provenance';

/// 一份正常的 AI 卡：1 个词性组（2 条例句）+ 1 个搭配组（1 条例句）。
ai_card.AiCard _card() => ai_card.parseAiCard(json.encode({
      'word': _word,
      'canonical': _word,
      'is_known_word': true,
      'senses': [
        {
          'pos': 'n.',
          'gloss': '起源，出处',
          'examples': [
            {
              'en': 'The provenance of this ancient manuscript remains a mystery.',
              'zh': '这份古代手稿的起源对历史学家来说仍是个谜。',
            },
            {
              'en': 'She documented the provenance of every artifact.',
              'zh': '她仔细记录了每件文物的出处。',
            },
          ],
        },
      ],
      'collocations': [
        {
          'phrase': 'the provenance of',
          'gloss': '……的起源/出处',
          'examples': [
            {
              'en': 'The provenance of the painting was traced back to Italy.',
              'zh': '这幅画的出处可以追溯到意大利。',
            },
          ],
        },
      ],
    })).card!;

Directory _tmp(String tag) => Directory(p.join(Directory.systemTemp.path,
    'lupa_aipersist_${tag}_${DateTime.now().microsecondsSinceEpoch}'))
  ..createSync(recursive: true);

/// 最小 `dict.sqlite`（只 `dict` 表 + 一条词条）—— 让本文件不依赖外部 LUPA_HOME，
/// 因而在任何环境（含 CI）都真的执行，而不是被静默跳过。
Future<void> _writeFakeDict(String dir) async {
  initDatabaseFactory();
  final db = await databaseFactory
      .openDatabase(p.absolute(p.join(dir, 'dict.sqlite')));
  await db.execute('''
CREATE TABLE dict (
  word TEXT, sw TEXT, phonetic TEXT, definition TEXT, translation TEXT,
  pos TEXT, collins INTEGER, oxford INTEGER, tag TEXT, bnc INTEGER,
  frq INTEGER, exchange TEXT, audio TEXT
)''');
  await db.insert('dict', {
    'word': _word,
    'sw': _word,
    'phonetic': 'ˈprɒvənəns',
    'definition': 'n where something originated',
    'translation': 'n. 起源，出处', // 有 n. 前缀 → enrichMode = full
    'pos': 'n:1',
    'collins': 0,
    'oxford': 0,
    'tag': 'gre',
    'bnc': 0,
    'frq': 16671,
    'exchange': '',
    'audio': '',
  });
  await db.close();
}

Future<AppState> _initState(Directory cfg, Directory data,
    {bool aiEnabled = true}) async {
  setConfigHomeOverride(cfg.path);
  setDataHomeOverride(data.path);
  File(p.join(cfg.path, configFile)).writeAsStringSync(json.encode({
    'default_provider': 'youdao',
    'providers': {
      'youdao': {'phonetic_url': 'u', 'tts_url': 't'},
      'deepseek': {
        'base_url': 'http://127.0.0.1:9', // 不可达：本文件只走缓存，不触网
        'model': 'deepseek-flash',
        'api_key': 'test-key',
        'timeout_sec': 5,
      },
    },
    'settings': {
      'theme': 'system',
      'ai': {'enabled': aiEnabled, 'providerName': 'deepseek', 'autoEnrich': true},
    },
  }), encoding: utf8);
  await _writeFakeDict(data.path);
  final state = AppState();
  await state.init();
  return state;
}

void main() {
  late Directory cfg;
  late Directory data;

  /// 让真实 IO（sqflite）与 setState 落地。
  /// fake-async 区里只 pump 是**不推进真实时间**的，所以每轮先 runAsync 烧掉一点
  /// 真实时间，再 pump 把已排队的回调 flush 出来（照 app_shell_shortcut_test）。
  ///
  /// 轮数要给够：`AppState.refresh()` 内部是 ~7 个串行 await，每轮真实时间窗口
  /// 大致只推进一两个 await —— 轮数太少会出现「库里已有数据、但界面还没重建」的
  /// 假失败（实测：8 轮时星标不翻转、SnackBar 不出现；40 轮正常）。
  Future<void> settle(WidgetTester tester,
      {int rounds = 40, int ms = 60}) async {
    for (var i = 0; i < rounds; i++) {
      await tester
          .runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
      await tester.pump(Duration(milliseconds: ms));
    }
  }

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

  // ---------------------------------------------------------------------
  // 1. 数据层：收藏时 AI 内容确实落进旁表
  // ---------------------------------------------------------------------
  test('1. 词库词 + AI 卡加入生词本：例句/搭配随笔记一并落库', () async {
    final s = await _initState(cfg, data);
    final noteId = await s.add(_word, aiCard: _card());
    expect(noteId, greaterThan(0));

    final entries = await listWords(s.nbPath);
    expect(entries.map((e) => e.word), contains(_word));
    final e = entries.first;

    expect(e.hasAi, isTrue, reason: '旁表应有 AI 内容（否则详情弹窗读回来是空的）');
    expect(e.aiSenses.length, 1, reason: '1 个词性组');
    expect(e.aiSenses.first.examples.length, 2, reason: '该组 2 条例句');
    expect(e.aiCollocations.length, 1, reason: '1 个搭配组');
    expect(e.aiCollocations.first.examples.length, 1);

    // 用户看到的那个判断：详情弹窗据此在「AI 区块」与「该词尚无 AI 例句」之间二选一
    expect(detailHasAi(fresh: null, entry: e), isTrue,
        reason: '详情弹窗必须认为该词已有 AI 内容，否则会显示「该词尚无 AI 例句」');
    expect(aiOutcomeFromNotebook(e), isNotNull,
        reason: '应能把旁表快照还原成 AiOutcome 交给 AiSection 渲染');
  });

  // ---------------------------------------------------------------------
  // 2. 来源标记：词库词不因「附带了 AI 例句」而被标成 AI 生成
  // ---------------------------------------------------------------------
  test('2. 词库词附带 AI 例句后，核心内容来源仍是词库（不得标成 AI 生成）', () async {
    final s = await _initState(cfg, data);
    await s.add(_word, aiCard: _card());

    final e = (await listWords(s.nbPath)).first;
    expect(e.source, NoteSource.dict,
        reason: 'spec「卡片来源标记」记的是**核心词条内容**的来源；'
            '词库词的核心内容来自词库，AI 只补了例句 —— 标成 ai 会让界面显示'
            '「AI 生成」标签，与事实不符');
  });

  test('2b. 词库词在详情里「AI 补齐」后，核心内容来源仍应是词库', () async {
    final s = await _initState(cfg, data);
    // 先按普通词库词加入（无 AI 内容）—— 这正是用户截图里那个状态
    final noteId = await s.add(_word);
    expect((await listWords(s.nbPath)).first.source, NoteSource.dict);
    expect((await listWords(s.nbPath)).first.hasAi, isFalse);

    // 等价于详情弹窗里点「AI 补齐」：它调 replaceAiGroups 写旁表
    await replaceAiGroups(s.nbPath, noteId, _card(),
        provider: s.aiProviderName, promptVersion: promptVersion);

    final e = (await listWords(s.nbPath)).first;
    expect(e.hasAi, isTrue, reason: '补齐后应有 AI 内容');
    expect(e.source, NoteSource.dict,
        reason: '补齐例句不改变核心内容来源 —— 这里曾硬编码成 ai，'
            '导致词库词被显示为「AI 生成」');
  });

  // ---------------------------------------------------------------------
  // 3. 用户实际点击路径：查词页 → 点五角星 → 生词本里能看到 AI 内容
  // ---------------------------------------------------------------------
  testWidgets('3. 查词页点星收藏：AI 内容随之落库，详情不再说「该词尚无 AI 例句」',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final s = (await tester.runAsync(() => _initState(cfg, data)))!;

    // 预置 AI 缓存：查词页会命中缓存（0 次网络请求）并渲染出 AI 补充，
    // 等价于用户截图里的那个状态，且不触网、不需要密钥。
    await tester.runAsync(() => ai_repo.writeAiCache(
          s.nbPath,
          provider: s.aiProviderName,
          model: s.aiModel,
          word: _word,
          feature: ai_card.AiFeature.enrich,
          promptVersion: promptVersion,
          valid: true,
          card: _card(),
        ));

    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SearchPage(state: s))));
    await tester.pump();

    // 查词（真实 sqflite IO → 必须 runAsync）
    await tester.runAsync(() async {
      await tester.enterText(find.byType(TextField).first, _word);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();

    // 前提：查词页确实渲染出了 AI 补充（否则下面的 star 断言是空断言）
    expect(find.text('AI 补充'), findsOneWidget,
        reason: '应命中 AI 缓存并渲染 AI 区块');
    expect(
        find.text('The provenance of this ancient manuscript remains a mystery.'),
        findsOneWidget,
        reason: 'AI 例句应显示在查词页 — 用户截图里的那个状态');

    // 点五角星收藏
    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.star_border_rounded));
    // 写库 + refresh + notifyListeners 都是真实异步，逐轮烧真实时间再 pump
    await settle(tester);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget,
        reason: '应已加入生词本（星标点亮）');

    // 生词本侧：AI 内容必须已经在库里
    final e = (await tester.runAsync(() async {
      final list = await listWords(s.nbPath);
      return list.firstWhere((x) => x.word.toLowerCase() == _word);
    }))!;
    expect(e.hasAi, isTrue,
        reason: '收藏时没把 AI 例句/搭配写进旁表 —— 生词本里就会显示'
            '「该词尚无 AI 例句」（用户报的缺陷）');
    expect(e.aiSenses.first.examples.length, 2);
    expect(e.aiCollocations.length, 1);
    expect(detailHasAi(fresh: null, entry: e), isTrue);
  });
}
