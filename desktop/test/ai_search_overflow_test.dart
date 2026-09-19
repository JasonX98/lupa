// 回归：小窗口下查词页结果卡不得 overflow（实测 hoax + AI 段落溢出 547px）。
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/pages/search_page.dart';
import 'package:lupa/state/app_state.dart';

void main() {
  testWidgets('小窗口下结果卡不 overflow', (tester) async {
    final cfg = Directory.systemTemp.createTempSync('lupa_ov_cfg_');
    final data = Directory.systemTemp.createTempSync('lupa_ov_data_');
    setConfigHomeOverride(cfg.path);
    setDataHomeOverride(data.path);
    final src = File(p.join(Platform.environment['LUPA_HOME']!, 'dict.sqlite'));
    if (src.existsSync()) src.copySync(p.join(data.path, 'dict.sqlite'));
    File(p.join(cfg.path, configFile)).writeAsStringSync(json.encode({
      'providers': {'youdao': {'phonetic_url': 'u', 'tts_url': 't'}},
      'settings': {'ai': {'enabled': false}},
    }), encoding: utf8);

    // 故意用很小的窗口：默认 800x600
    final s = await tester.runAsync(() async {
      final st = AppState();
      await st.init();
      return st;
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SearchPage(state: s!))));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.enterText(find.byType(TextField).first, 'hoax');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await tester.pump();
    // 没有 overflow 异常即为通过（Flutter 会在 build 时抛）
    expect(tester.takeException(), isNull);
    clearConfigHomeOverride();
    clearDataHomeOverride();
    cfg.deleteSync(recursive: true);
    data.deleteSync(recursive: true);
  });
}
