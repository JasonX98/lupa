// 回归：侧栏在任意窗口高度下都可达（openspec change fix-ui-contrast-and-reachability 任务 3.2~3.4）。
//
// 缺陷：侧栏是固定 `Column` 且**无滚动**，窗口高度低于约 373px 时溢出
// （实测 340px → 溢出 33px、300px → 溢出 73px）；而 Windows runner 未设最小窗口
// 尺寸（`windows/runner/main.cpp` 只给初始 1280x720），用户可以真把窗口拖到那个
// 高度 —— 此时底部的「设置」入口被裁掉且无法触达。
//
// 本文件守三件事：
//   3.2 六个高度下都不产生布局溢出
//   3.3 矮窗口下滚动后「设置」仍可点、能进设置页
//   3.4 空间充足时布局**不退化**：顶部锚定不随高度移动、「设置」仍贴底、无需滚动
//
// 3.4 不用像素魔数，而是断言**布局语义**（D4）：顶部锚定（查词项 top 与高度无关）、
// 底部锚定（版本行 bottom == 视口底部）、设置入口与版本行相邻、导航顺序递增。
// 这样「把设置改成跟着内容走」或「整块改成居中」都会被抓住。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/widgets/app_shell.dart';

Directory _tmp(String tag) => Directory(p.join(
    Directory.systemTemp.path,
    'lupa_sidebar_${tag}_${DateTime.now().microsecondsSinceEpoch}'))
  ..createSync(recursive: true);

Future<AppState> _initState(Directory cfg, Directory data) async {
  setConfigHomeOverride(cfg.path);
  setDataHomeOverride(data.path);
  File(p.join(cfg.path, configFile)).writeAsStringSync(json.encode({
    'default_provider': 'youdao',
    'providers': {'youdao': {'phonetic_url': 'u', 'tts_url': 't'}},
    'settings': {'theme': 'system'},
  }), encoding: utf8);
  final state = AppState();
  await state.init();
  return state;
}

/// 侧栏根：`SizedBox(width: 208)`（宽度是布局规格的一部分，改动前后都不变）。
/// 用它做作用域，避免与页面里同名文案相互干扰。
Finder _sidebar() => find
    .ancestor(
      of: find.text('设置'),
      matching: find.byWidgetPredicate((w) => w is SizedBox && w.width == 208),
    )
    .first;

/// 侧栏内的滚动视图（未加滚动前不存在 → 返回空）。
Finder _sidebarScrollable() =>
    find.descendant(of: _sidebar(), matching: find.byType(Scrollable));

/// 侧栏当前是否可滚动（空间不足时为真）。未加滚动能力时视为「不可滚动」。
double _maxScrollExtent(WidgetTester tester) {
  final f = _sidebarScrollable();
  if (f.evaluate().isEmpty) return 0;
  return tester.state<ScrollableState>(f.first).position.maxScrollExtent;
}

/// 版本行（侧栏最底部的一项，用它证明「块底部锚定」）。
final _footer = find.textContaining('· 本地优先');

/// 侧栏导航项，自上而下（与 `_nav` 顺序一致，末尾附设置入口）。
const _navLabels = ['查词', '生词本', '单词复习', '短语集', '导出', '设置'];

Future<void> _pumpShell(WidgetTester tester, AppState state,
    {required double height, double width = 1280}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: AppShell(state: state)));
  await tester.pump();
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

  Future<AppState> boot(WidgetTester tester) async =>
      (await tester.runAsync(() => _initState(cfg, data)))!;

  testWidgets('3.2 侧栏在 720/600/460/400/340/300px 六个高度下均不溢出', (tester) async {
    final state = await boot(tester);
    // 实测基线：低于约 373px 才溢出（340px → 33px、300px → 73px）
    for (final h in [720.0, 600.0, 460.0, 400.0, 340.0, 300.0]) {
      await _pumpShell(tester, state, height: h);
      final ex = tester.takeException();
      expect(ex, isNull, reason: '窗口高 ${h.toInt()}px 时出现布局溢出/异常：$ex');
    }
  });

  testWidgets('3.3 矮窗口（300px）下滚动后仍能点进「设置」', (tester) async {
    final state = await boot(tester);
    const h = 300.0;
    await _pumpShell(tester, state, height: h);

    // 前提校验：这个高度确实放不下，否则本用例什么都没测到。
    final r0 = tester.getRect(find.text('设置'));
    expect(r0.bottom, greaterThan(h),
        reason: '高度 ${h.toInt()}px 应容纳不下侧栏内容（设置入口底部 ${r0.bottom}）');

    // 滚动到「设置」入口再点它 —— 真人能做的动作
    await tester.ensureVisible(find.text('设置'));
    await tester.pump();
    final r1 = tester.getRect(find.text('设置'));
    expect(r1.bottom, lessThanOrEqualTo(h),
        reason: '滚动后「设置」入口应完整落在视口内（底部 ${r1.bottom} ≤ $h）');

    await tester.tap(find.text('设置'));
    await tester.pump();
    expect(find.text('外观'), findsOneWidget, reason: '应已切到设置页');
  });

  testWidgets('3.4 空间充足时布局不退化：顶部锚定 + 设置贴底 + 无需滚动', (tester) async {
    final state = await boot(tester);

    final navTop = <double, double>{};
    final footerBottom = <double, double>{};
    final footerInset = <double, double>{};
    final settingsAboveFooter = <double, double>{};
    for (final h in [600.0, 720.0, 1200.0]) {
      await _pumpShell(tester, state, height: h);

      final rects = {for (final l in _navLabels) l: tester.getRect(find.text(l))};

      // 导航项自上而下递增，且「设置」在最后
      for (var i = 1; i < _navLabels.length; i++) {
        expect(rects[_navLabels[i]]!.top, greaterThan(rects[_navLabels[i - 1]]!.top),
            reason: '高度 ${h.toInt()}px：${_navLabels[i]} 应在 ${_navLabels[i - 1]} 之下');
      }

      final footer = tester.getRect(_footer);
      // 底部锚定：版本行（侧栏最底一项）到视口底部的距离与高度无关（版本行自身
      // 有 16px 下内边距，所以不断言它「恰好等于 h」——那是像素魔数）。
      // 「设置」在版本行上面，因而也跟着底部。
      footerInset[h] = h - footer.bottom;
      expect(footerInset[h], greaterThanOrEqualTo(0),
          reason: '高度 ${h.toInt()}px：版本行不得超出视口底部（说明溢出被裁了）');
      // 「设置」入口到版本行底部的距离固定 → 它跟着**底部**走，不跟着内容走。
      settingsAboveFooter[h] = footer.bottom - rects['设置']!.bottom;
      expect(settingsAboveFooter[h], greaterThan(0),
          reason: '高度 ${h.toInt()}px：「设置」入口应在版本行之上');

      // 空间充足 → 不需要滚动（不出现滚动条）
      expect(_maxScrollExtent(tester), 0,
          reason: '高度 ${h.toInt()}px 已足够容纳侧栏，不应可滚动');

      navTop[h] = rects['查词']!.top;
      footerBottom[h] = footer.bottom;
    }

    // 顶部锚定：只改高度不得挪动上部内容（抓住「整块居中」这类回退）
    expect(navTop[600], closeTo(navTop[720]!, 0.5));
    expect(navTop[1200], closeTo(navTop[720]!, 0.5));

    // 「设置」与底部的关系恒定（抓住「设置跟着内容走」这类回退）
    expect(settingsAboveFooter[600], closeTo(settingsAboveFooter[720]!, 0.5));
    expect(settingsAboveFooter[1200], closeTo(settingsAboveFooter[720]!, 0.5));
    // 版本行距底部恒定 = 底部锚定（抓住「整块居中」/「不再贴底」这类回退）
    expect(footerInset[600], closeTo(footerInset[720]!, 0.5));
    expect(footerInset[1200], closeTo(footerInset[720]!, 0.5));

    // 对照组：底部确实随高度移动 —— 否则上面几条「恒定」是空断言
    expect(footerBottom[1200]! - footerBottom[600]!, closeTo(600, 0.5),
        reason: '底部锚定意味着版本行位置应随视口高度移动');
  });
}
