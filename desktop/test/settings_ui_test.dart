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

  testWidgets('5.5 SettingsPage 四组渲染', (tester) async {
    // 加高测试画布，让 ListView 一次性构建四组（否则离屏项不构建）。
    tester.view.physicalSize = const Size(1200, 2400);
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
    expect(find.text('数据'), findsOneWidget);
    // 主题三段选择存在
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色'), findsOneWidget);
    expect(find.text('深色'), findsOneWidget);
    // 数据目录「更改」按钮
    expect(find.text('更改'), findsOneWidget);
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
