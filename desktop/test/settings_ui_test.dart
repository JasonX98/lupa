// 设置模块 UI 冒烟：SettingsPage 四组构建、AppShell 设置入口与主题切换移除。
// 用临时 configHome/dataHome 驱动一个 init 后的 AppState（不碰真实数据）。
// 注意：只用 pump() 单帧断言同步结构，不用 pumpAndSettle（页面含异步 DB 加载/转圈）。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/pages/settings_page.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/widgets/app_shell.dart';
import 'package:lupa/widgets/switch_lupa.dart';

Directory _tmp(String tag) => Directory(p.join(
    Directory.systemTemp.path,
    'lupa_ui_${tag}_${DateTime.now().microsecondsSinceEpoch}'))
  ..createSync(recursive: true);

Future<AppState> _initState(Directory cfg, Directory data) async {
  setConfigHomeOverride(cfg.path);
  setDataHomeOverride(data.path);
  final file = File(p.join(cfg.path, configFile));
  if (!file.existsSync()) {
    file.writeAsStringSync(json.encode({
      'default_provider': 'youdao',
      'providers': {'youdao': {'phonetic_url': 'u', 'tts_url': 't'}},
      'settings': {'theme': 'system'},
    }), encoding: utf8);
  }
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

  testWidgets('5.5 SettingsPage 五组渲染（含 AI 组）', (tester) async {
    // 加高测试画布，让 ListView 一次性构建五组（否则离屏项不构建）。
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // init 走真实 DB IO（sqflite ffi 隔离区），必须放进 runAsync，
    // 否则在 testWidgets 的 fake-async 区里永不完成 → 卡死。
    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    // 真实应用里 SettingsPage 在 AppShell 的 Scaffold 内（提供 Material）。
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SettingsPage(state: state))));
    await tester.pump();

    expect(find.text('外观'), findsOneWidget);
    expect(find.text('发音'), findsOneWidget);
    expect(find.text('复习'), findsOneWidget);
    expect(find.text('AI'), findsOneWidget);
    expect(find.text('数据'), findsOneWidget);
    // 主题三段选择存在
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    // 数据目录「更改」按钮
    expect(find.text('更改'), findsOneWidget);

    // ---- AI 组控件 ----
    expect(find.text('启用 AI'), findsOneWidget);
    expect(find.text('查词时自动补齐'), findsOneWidget);
    expect(find.text('服务基地址'), findsOneWidget);
    expect(find.text('模型'), findsOneWidget);
    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('保存 AI 配置'), findsOneWidget);
    expect(find.text('AI 缓存'), findsOneWidget);
    expect(find.text('清理 AI 缓存'), findsOneWidget);

    // 默认关闭（spec：首次运行不发起任何 AI 请求）
    expect(state.aiEnabled, isFalse);
    expect(state.aiAutoEnrich, isTrue);

    // 密钥掩码：默认不可见，点「显示」后可读
    final keyField = tester.widget<TextField>(find.byWidgetPredicate((w) =>
        w is TextField && w.controller?.text == '' && w.obscureText == true));
    expect(keyField.obscureText, isTrue);
    await tester.tap(find.byTooltip('显示'));
    await tester.pump();
    expect(find.byTooltip('隐藏'), findsOneWidget);
  });

  testWidgets('5.5a AI 输入框撑满卡片宽度（回归：曾是固定 420px 被居中）', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SettingsPage(state: state))));
    await tester.pump();

    // 根因：_aiField 曾用 `SizedBox(width: 420)`，而 _card 的 Column 默认
    // crossAxisAlignment.center 会把这个「比卡片窄」的盒子居中 —— 截图里
    // 输入框因此跑到了中间。修法有两处：去掉固定宽度 + _card 改 stretch。
    // 断言用「输入框右边缘 ≈ 开关右边缘」来锁住这个语义（两者都在卡片的
    // 内容区右边界上）。
    final keyField = find.byWidgetPredicate(
        (w) => w is TextField && w.obscureText == true);
    expect(keyField, findsOneWidget);

    final fieldRect = tester.getRect(keyField);
    // 取任一开关（「启用 AI」那个）作为内容区右边界参照
    final switchFinder = find.byType(LupaSwitch).first;
    final switchRect = tester.getRect(switchFinder);

    expect((fieldRect.right - switchRect.right).abs(), lessThan(4),
        reason: 'AI 输入框应撑满卡片内容宽度（fieldRight=${fieldRect.right} '
            'switchRight=${switchRect.right}）');
    expect(fieldRect.width, greaterThan(600),
        reason: '输入框不应是窄的固定宽度（实际 ${fieldRect.width}）');
  });

  testWidgets('5.5b AI 组：清理缓存与媒体缓存是两个独立入口', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SettingsPage(state: state))));
    await tester.pump();

    expect(find.text('清理 AI 缓存'), findsOneWidget);
    expect(find.text('清理缓存'), findsOneWidget); // 媒体缓存那个
    // 清理说明文案必须存在（否则用户不敢点）
    expect(
        find.textContaining('不会删除已保存生词卡片中的例句'), findsOneWidget);
  });

  testWidgets('5.5c AI 组：已启用但未填密钥时给出提示', (tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    state.setAiEnabled(true); // 启用但密钥仍为空
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: SettingsPage(state: state))));
    await tester.pump();

    expect(state.aiReady, isFalse); // 启用 ≠ 可用
    expect(find.textContaining('已启用但未填密钥'), findsOneWidget);
    expect(find.textContaining('密钥以明文保存在 config.json'), findsOneWidget);
  });

  testWidgets('6.1 AppShell 有设置入口且无主题循环切换', (tester) async {
    final state = (await tester.runAsync(() => _initState(cfg, data)))!;
    await tester.pumpWidget(MaterialApp(home: AppShell(state: state)));
    await tester.pump();

    // 侧栏有「设置」入口
    expect(find.text('设置'), findsOneWidget);
    // 主题切换已移除：侧栏不再出现 themeLabel 文案
    expect(find.text('跟随系统'), findsNothing);
    expect(find.text('浅色'), findsNothing);
    expect(find.text('深色'), findsNothing);

    // 点「设置」→ 进入设置页（section 标题出现）
    await tester.tap(find.text('设置'));
    await tester.pump();
    expect(find.text('外观'), findsOneWidget);
  });
}
