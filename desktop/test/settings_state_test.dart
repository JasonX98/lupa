// 设置模块：AppState 读取 / 写入 settings、运行时切换数据目录、分歧提示。
// 通过 configHome/dataHome 覆盖把 AppState 指到临时目录，不碰真实数据。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/state/app_state.dart';

Directory _tmp(String tag) => Directory(p.join(
    Directory.systemTemp.path,
    'lupa_state_${tag}_${DateTime.now().microsecondsSinceEpoch}'))
  ..createSync(recursive: true);

void main() {
  late Directory cfgHome;
  late Directory dataDir;

  setUp(() {
    cfgHome = _tmp('cfg');
    dataDir = _tmp('data');
    // 把 config.json 与数据目录都指到临时位置（无法在 flutter test 里设 env）
    setConfigHomeOverride(cfgHome.path);
    setDataHomeOverride(dataDir.path);
  });

  tearDown(() {
    clearConfigHomeOverride();
    clearDataHomeOverride();
    cfgHome.deleteSync(recursive: true);
    dataDir.deleteSync(recursive: true);
  });

  test('4.1 init 从 config.settings 读取状态', () async {
    // 预写 config.json（带 settings 覆盖）
    File(p.join(cfgHome.path, configFile)).writeAsStringSync(json.encode({
      'default_provider': 'youdao',
      'providers': {'youdao': {'phonetic_url': 'u', 'tts_url': 't'}},
      'settings': {
        'theme': 'dark',
        'defFontSize': 18,
        'showEnglish': false,
        'defaultAccent': 'uk',
        'reviewAutoRead': true,
        'dataDir': null,
      },
    }), encoding: utf8);

    final state = AppState();
    await state.init();

    expect(state.themeMode, ThemeMode.dark);
    expect(state.defFontSize, 18);
    expect(state.showEnglish, false);
    expect(state.defaultAccent, 'uk');
    expect(state.reviewAutoRead, true);
    expect(state.dataDirDiverges, false); // 未设 LUPA_HOME（测试进程）→ 不分歧
  });

  test('4.2 各 setter 写回 config 并持久化', () async {
    final state = AppState();
    await state.init();

    state.setTheme('light');
    state.setDefFontSize(16);
    state.setShowEnglish(true);
    state.setDefaultAccent('us');
    state.setReviewAutoRead(false);

    final onDisk = json.decode(
            File(p.join(cfgHome.path, configFile)).readAsStringSync(encoding: utf8))
        as Map;
    expect(onDisk['settings']['theme'], 'light');
    expect(onDisk['settings']['defFontSize'], 16);
    expect(onDisk['settings']['showEnglish'], true);
    expect(onDisk['settings']['defaultAccent'], 'us');
    expect(onDisk['settings']['reviewAutoRead'], false);
    // 设置主题/字号等不应固化 dataDir（除非显式切换）
    expect(onDisk['settings']['dataDir'], isNull);
  });

  test('4.3 switchDataDir 切换到新目录（复制）', () async {
    final state = AppState();
    await state.init();

    final dst = _tmp('dst');
    // 复制到 dst：预置 dict.sqlite + exports 以验证 copyDataDir 一并拷贝
    File(p.join(dst.path, 'dict.sqlite')).writeAsBytesSync([1, 2, 3]);
    final exp = Directory(p.join(dst.path, 'exports'))..createSync(recursive: true);
    File(p.join(exp.path, 'x.csv')).writeAsStringSync('a,b');
    // 让 dst 已有 notebook.sqlite（先复制一个），再切换
    final srcNb = p.join(dataDir.path, 'notebook.sqlite');
    File(srcNb).copySync(p.join(dst.path, 'notebook.sqlite'));

    await state.switchDataDir(dst.path, copyExisting: false);

    expect(state.nbPath, p.absolute(p.join(dst.path, 'notebook.sqlite')));
    expect(state.dictDb, p.absolute(p.join(dst.path, 'dict.sqlite')));
    // config 写入 dataDir
    final onDisk = json.decode(
            File(p.join(cfgHome.path, configFile)).readAsStringSync(encoding: utf8))
        as Map;
    expect((onDisk['settings'] as Map)['dataDir'], p.absolute(dst.path));
    // dataHome() 现指向 dst
    expect(p.absolute(dataHome().path), p.absolute(dst.path));
    dst.deleteSync(recursive: true);
  });

  test('4.4 dataDirDivergent 纯逻辑（true/false 分支）', () {
    // false：LUPA_HOME 未设
    expect(dataDirDivergent(null, '/data/b'), false);
    expect(dataDirDivergent('  ', '/data/b'), false);
    // false：override 未设/为空
    expect(dataDirDivergent('/data/a', null), false);
    expect(dataDirDivergent('/data/a', ''), false);
    // false：两者一致
    expect(dataDirDivergent('/data/a', '/data/a'), false);
    // true：不一致
    expect(dataDirDivergent('/data/a', '/data/b'), true);
  });

  test('7.4 端到端设置流程（headless 等价）', () async {
    final state = AppState();
    await state.init();

    // 改主题 → 改字号 → 关英文释义 → 改默认口音
    state.setTheme('dark');
    state.setDefFontSize(18);
    state.setShowEnglish(false);
    state.setDefaultAccent('uk');
    expect(state.themeMode, ThemeMode.dark);
    expect(state.defFontSize, 18);
    expect(state.showEnglish, false);
    expect(state.defaultAccent, 'uk');

    // 清理缓存 → 备份生词本
    await clearMediaCache(state.nbPath);
    final backup = await state.backupNote();
    expect(File(backup).existsSync(), true);

    // 切换到新目录（复制）→ 再切回原目录
    final original = state.nbPath;
    final dst = _tmp('e2e_dst');
    await state.switchDataDir(dst.path, copyExisting: true);
    expect(state.nbPath, p.absolute(p.join(dst.path, 'notebook.sqlite')));

    await state.switchDataDir(p.dirname(original), copyExisting: false);
    expect(state.nbPath, p.absolute(original));
    dst.deleteSync(recursive: true);
  });

  test('4.3b switchDataDir 空目录 + copyExisting:true 会复制 notebook', () async {
    final state = AppState();
    await state.init();
    // init 已在 dataDir 创建有效 notebook.sqlite（源）
    final srcNb = p.join(dataDir.path, 'notebook.sqlite');
    expect(File(srcNb).existsSync(), true);

    final dst = _tmp('dst2');
    await state.switchDataDir(dst.path, copyExisting: true);

    expect(File(p.join(dst.path, 'notebook.sqlite')).existsSync(), true);
    expect(state.nbPath, p.absolute(p.join(dst.path, 'notebook.sqlite')));
    dst.deleteSync(recursive: true);
  });
}
