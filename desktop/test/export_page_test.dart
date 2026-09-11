// 导出页 UI：顶部分段（生词本 / 短语集）、短语标签筛选、空态守卫、产物命名。
// 临时 configHome/dataHome；单词种子直接写 notes（不依赖 dict.sqlite）；
// 真实 DB / 文件 IO 走 runAsync，不用 pumpAndSettle。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/notebook/repo.dart';
import 'package:lupa/pages/export_page.dart';
import 'package:lupa/phrase/repo.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/widgets/phrase_bits.dart';

Directory _tmp(String tag) => Directory(p.join(
    Directory.systemTemp.path,
    'lupa_export_ui_${tag}_${DateTime.now().microsecondsSinceEpoch}'))
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

/// 等真实 IO（sqflite / ganki 写文件）走完：每轮烧一点真实时间，再 pump 冲刷回调。
Future<void> _settle(WidgetTester tester, bool Function() done,
    {int maxRounds = 40, int ms = 60}) async {
  for (var i = 0; i < maxRounds && !done(); i++) {
    await tester.runAsync(
        () => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump(Duration(milliseconds: ms));
  }
}

/// 直接写 notes 种子单词（绕开词库校验，测试不依赖 dict.sqlite）。
Future<void> _seedWord(AppState state, String word) async {
  final con = await databaseFactory.openDatabase(p.absolute(state.nbPath));
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  await con.insert('notes', {
    'n_id': 'n_$word',
    'm_id': modelId,
    'mod': now,
    'usn': 0,
    'tags': '',
    'flds': [word, 'əˈbændən', '放弃；抛弃', 'to give up', ''].join(fieldSep),
    'sfld': word,
    'csum': 0,
    'flags': 0,
    'data': '',
  });
  await con.close();
  await state.refresh();
}

/// 导出目录里的文件名（无目录时为空列表）。
List<String> _exportFiles(Directory data) {
  final d = Directory(p.join(data.path, 'exports'));
  if (!d.existsSync()) return const [];
  return d
      .listSync()
      .whereType<File>()
      .map((f) => p.basename(f.path))
      .toList()
    ..sort();
}

String _pathOf(Directory data, String name) =>
    p.join(data.path, 'exports', name);

bool _isWordApkg(String name) =>
    name.startsWith('lupa-') &&
    !name.startsWith('lupa-phrases-') &&
    name.endsWith('.apkg');

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

  Future<AppState> pumpPage(WidgetTester tester) async {
    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ExportPage(state: state))));
    await tester.pump();
    return state;
  }

  Future<void> gotoPhrases(WidgetTester tester) async {
    await tester.tap(find.text('短语集'));
    await tester.pump();
  }

  testWidgets('2.1 默认生词本分组：两张卡与今日文案一致 + 两条命名线', (tester) async {
    final state = await pumpPage(tester);

    expect(find.text('导出'), findsOneWidget);
    expect(find.text('Anki 牌组（.apkg）'), findsOneWidget);
    expect(find.text('CSV 表格（.csv）'), findsOneWidget);
    expect(find.textContaining('7 列：单词、音标、释义、英解、词形、标签、收藏时间'),
        findsOneWidget);
    expect(find.text('数据在你手里 — 0 个词随时带走'), findsOneWidget);

    // 1.1 命名：生词本与短语集两条命名线
    expect(state.exportFileName('apkg'),
        matches(RegExp(r'^lupa-\d{8}-\d{4}\.apkg$')));
    expect(state.phraseExportFileName('apkg'),
        matches(RegExp(r'^lupa-phrases-\d{8}-\d{4}\.apkg$')));
    expect(state.phraseExportFileName('csv'),
        matches(RegExp(r'^lupa-phrases-\d{8}-\d{4}\.csv$')));
  });

  testWidgets('2.2 / 3.2 切到短语集分组：标签筛选出现、文案改短语口径', (tester) async {
    final state = await pumpPage(tester);
    await tester.runAsync(() async {
      await state.addPhraseEntry(const PhraseInput(
          phrase: 'bite the bullet', meaning: '硬着头皮上', tags: '口语'));
      await state.addPhraseEntry(const PhraseInput(
          phrase: 'spill the beans', meaning: '泄密', tags: '书面'));
    });
    await tester.pump();

    await gotoPhrases(tester);

    // 生词本的卡已不在树上，两张短语卡取而代之
    expect(find.textContaining('7 列：单词'), findsNothing);
    expect(find.textContaining('9 列：短语、直译、释义、典故、场景、场景标签、标签、收藏时间、例句'),
        findsOneWidget);
    expect(find.text('Anki 牌组（.apkg）'), findsOneWidget);
    // 标签筛选行：全部 + 两个标签
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('口语'), findsOneWidget);
    expect(find.text('书面'), findsOneWidget);
    // 头部按分组换口径；两张短语卡都带范围计数
    expect(find.text('数据在你手里 — 2 条短语随时带走'), findsOneWidget);
    expect(find.text('2 条短语'), findsNWidgets(2));

    // 布局：标签筛选与分组控件同一水平线，且右边界与卡片边框对齐
    final groupBar = tester.getRect(find.byType(PhraseFilterBar).at(0));
    final tagBar = tester.getRect(find.byType(PhraseFilterBar).at(1));
    expect(tagBar.top, groupBar.top, reason: '标签筛选应与分组控件同一水平线');
    expect(tagBar.bottom, groupBar.bottom);
    // 卡片内边距 22 + 1px 边框 → 卡片边框 = 卡片内计数文案右边界 + 23
    final countRight = tester.getRect(find.text('2 条短语').first).right;
    expect(tagBar.right, closeTo(countRight + 23, 1.0),
        reason: '标签筛选右边界应与卡片右边框对齐');
  });

  testWidgets('2.3 标签筛选只改导出范围，不动数据', (tester) async {
    final state = await pumpPage(tester);
    await tester.runAsync(() async {
      await state.addPhraseEntry(const PhraseInput(
          phrase: 'bite the bullet', meaning: '硬着头皮上', tags: '口语'));
      await state.addPhraseEntry(const PhraseInput(
          phrase: 'spill the beans', meaning: '泄密', tags: '书面'));
    });
    await tester.pump();
    await gotoPhrases(tester);

    await tester.tap(find.text('口语'));
    await tester.pump();

    expect(find.text('1 条短语'), findsNWidgets(2)); // 范围计数随之变化
    expect(state.phraseEntries.length, 2); // 数据与列表不受影响
    expect(state.phraseTags, containsAll(['口语', '书面']));

    // 切回生词本分组仍走单词口径
    await tester.tap(find.text('生词本'));
    await tester.pump();
    expect(find.text('数据在你手里 — 0 个词随时带走'), findsOneWidget);
    expect(find.textContaining('7 列：单词'), findsOneWidget);
  });

  testWidgets('2.4 按标签导出：文件名带 lupa-phrases- 前缀，内容只含该标签', (tester) async {
    final state = await pumpPage(tester);
    await tester.runAsync(() async {
      await state.addPhraseEntry(const PhraseInput(
          phrase: 'bite the bullet', meaning: '硬着头皮上', tags: '口语'));
      await state.addPhraseEntry(const PhraseInput(
          phrase: 'spill the beans', meaning: '泄密', tags: '书面'));
    });
    await tester.pump();
    await gotoPhrases(tester);
    await tester.tap(find.text('口语'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, '导出 .apkg'));
    await _settle(tester, () => _exportFiles(data).length == 1);
    // 文件先落盘、结果行的 setState 可能还差一次 pump：等 UI 出现再断言
    await _settle(tester,
        () => find.textContaining('已导出 1 条').evaluate().isNotEmpty);
    expect(_exportFiles(data).length, 1);
    expect(find.textContaining('已导出 1 条'), findsOneWidget);
    expect(find.textContaining('标签「口语」'), findsOneWidget); // 结果行标注筛选范围

    await tester.tap(find.widgetWithText(OutlinedButton, '导出 .csv'));
    await _settle(tester, () => _exportFiles(data).length == 2);
    await _settle(tester,
        () => find.textContaining('已导出 1 条').evaluate().length == 2);
    final files = _exportFiles(data);
    expect(files.length, 2);
    expect(files.every((f) => f.startsWith('lupa-phrases-')), true,
        reason: '短语导出走 lupa-phrases- 命名线，实际: $files');

    final csvName = files.firstWhere((f) => f.endsWith('.csv'));
    final csvText = File(_pathOf(data, csvName)).readAsStringSync();
    expect(csvText, contains('bite the bullet'));
    expect(csvText, isNot(contains('spill the beans')));

    // apkg 内容读回（解 zip + notes.flds）由 tool/verify_phrase_repo.dart 3.3 覆盖
    final apkgName = files.firstWhere((f) => f.endsWith('.apkg'));
    expect(File(_pathOf(data, apkgName)).lengthSync(), greaterThan(0));
  });

  testWidgets('3.1 空生词本导出被拦下：提示且不产出文件', (tester) async {
    await pumpPage(tester); // 默认生词本分组，0 个词

    await tester.tap(find.widgetWithText(FilledButton, '导出 .apkg'));
    await tester.pump();

    expect(find.text('生词本是空的，先收藏几个词再导出'), findsOneWidget);
    expect(_exportFiles(data), isEmpty);
  });

  testWidgets('3.1 空短语集导出被拦下：提示且不产出文件', (tester) async {
    await pumpPage(tester);
    await gotoPhrases(tester);

    await tester.tap(find.widgetWithText(FilledButton, '导出 .apkg'));
    await tester.pump();

    expect(find.text('短语集还是空的，先记几条短语再导出'), findsOneWidget);
    expect(_exportFiles(data), isEmpty);
  });

  testWidgets('3.1 所选标签下无短语被拦下：提示且不产出文件', (tester) async {
    final state = await pumpPage(tester);
    final oralId = (await tester.runAsync(() async => state.addPhraseEntry(
        const PhraseInput(
            phrase: 'bite the bullet', meaning: '硬着头皮上', tags: '口语'))))!;
    await tester.runAsync(() => state.addPhraseEntry(const PhraseInput(
        phrase: 'spill the beans', meaning: '泄密', tags: '书面')));
    await tester.pump();
    await gotoPhrases(tester);
    await tester.tap(find.text('口语'));
    await tester.pump();
    expect(find.text('1 条短语'), findsNWidgets(2));

    // 删掉该标签下最后一条（导出页仍停在「口语」档）→ 有效范围为 0
    await tester.runAsync(() => state.removePhraseEntry(oralId));
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, '导出 .csv'));
    await tester.pump();

    expect(find.textContaining('「口语」下暂无短语'), findsOneWidget);
    expect(_exportFiles(data), isEmpty);
  });

  testWidgets('4.3 同一分钟内先后导出两类：两份文件都在且先导出的不被改动', (tester) async {
    final state = await pumpPage(tester);
    await tester.runAsync(() async {
      await _seedWord(state, 'abandon');
      await state.addPhraseEntry(const PhraseInput(
          phrase: 'bite the bullet', meaning: '硬着头皮上', tags: '口语'));
    });
    await tester.pump();

    // 1) 生词本 apkg
    await tester.tap(find.widgetWithText(FilledButton, '导出 .apkg'));
    await _settle(tester, () => _exportFiles(data).length == 1);
    final wordName = _exportFiles(data).single;
    expect(_isWordApkg(wordName), true, reason: '实际: $wordName');
    final wordBytes = File(_pathOf(data, wordName)).readAsBytesSync();

    // 2) 同一分钟内再导短语 apkg
    await gotoPhrases(tester);
    await tester.tap(find.widgetWithText(FilledButton, '导出 .apkg'));
    await _settle(tester, () => _exportFiles(data).length == 2);

    final files = _exportFiles(data);
    expect(files.length, 2);
    expect(files.where((f) => f.startsWith('lupa-phrases-')).length, 1);
    expect(files.where(_isWordApkg).length, 1);
    expect(File(_pathOf(data, wordName)).readAsBytesSync(), equals(wordBytes),
        reason: '短语导出不得覆盖先导出的生词本文件');
  });
}
