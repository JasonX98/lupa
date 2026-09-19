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

  // ---- AI 设置 ----

  test('4.4 AI 默认关闭且自动补齐默认开（首次运行不发任何请求）', () async {
    final state = AppState();
    await state.init();
    expect(state.aiEnabled, isFalse);
    expect(state.aiAutoEnrich, isTrue);
    expect(state.aiProviderName, 'deepseek');
    expect(state.aiModel, 'deepseek-flash');
    expect(state.aiBaseUrl, 'https://api.deepseek.com');
    expect(state.aiReady, isFalse); // 未启用 + 无密钥
  });

  test('4.5 启用但无密钥时 aiReady 仍为 false（启用 ≠ 可用）', () async {
    final state = AppState();
    await state.init();
    state.setAiEnabled(true);
    expect(state.aiEnabled, isTrue);
    expect(state.aiApiKey, isEmpty);
    expect(state.aiReady, isFalse);
    expect(state.aiClient(), isNull, reason: '未就绪时不应构造客户端');
  });

  test('4.6 写入密钥后 aiReady 为 true 且能构造客户端', () async {
    final state = AppState();
    await state.init();
    state.setAiEnabled(true);
    state.setAiConnection(apiKey: 'sk-test-123');
    expect(state.aiApiKey, 'sk-test-123');
    expect(state.aiReady, isTrue);
    final c = state.aiClient();
    expect(c, isNotNull);
    expect(c!.config.model, 'deepseek-flash');
    expect(c.config.apiKey, 'sk-test-123');
  });

  test('4.7 AI 设置持久化到 config.json（重启后仍生效）', () async {
    final state = AppState();
    await state.init();
    state.setAiEnabled(true);
    state.setAiAutoEnrich(false);
    state.setAiConnection(baseUrl: 'https://example.test', model: 'my-model', apiKey: 'k1');

    // 重新加载配置（模拟重启）
    final again = AppState();
    await again.init();
    expect(again.aiEnabled, isTrue);
    expect(again.aiAutoEnrich, isFalse);
    expect(again.aiBaseUrl, 'https://example.test');
    expect(again.aiModel, 'my-model');
    expect(again.aiApiKey, 'k1');
  });

  test('4.8 连接信息在 providers.<name>，行为开关在 settings.ai', () async {
    final state = AppState();
    await state.init();
    state.setAiConnection(baseUrl: 'https://x.test', model: 'm', apiKey: 'k');
    state.setAiEnabled(true);

    final providers = state.config['providers'] as Map<String, Object?>;
    final ds = (providers['deepseek'] as Map).cast<String, Object?>();
    expect(ds['base_url'], 'https://x.test');
    expect(ds['model'], 'm');
    expect(ds['api_key'], 'k');

    final settings = (state.config['settings'] as Map).cast<String, Object?>();
    final ai = (settings['ai'] as Map).cast<String, Object?>();
    expect(ai['enabled'], true);
    expect(ai.containsKey('api_key'), isFalse, reason: '密钥不应进 settings.ai');
  });

  test('4.9 AI 缓存统计与清理（清理不影响其他表）', () async {
    final state = AppState();
    await state.init();
    final before = await state.aiCacheStatsNow();
    expect(before.count, 0);
    expect(before.totalTokens, 0);
    final removed = await state.clearAiCacheNow();
    expect(removed, 0);
    final after = await state.aiCacheStatsNow();
    expect(after.count, 0);
  });

  group('resolveAiKey（纯函数：环境变量优先于 config.json）', () {
    final cfg = <String, Object?>{
      'providers': {
        'deepseek': {'api_key': 'from-config'},
      },
    };

    test('环境变量优先', () {
      expect(resolveAiKey('from-env', cfg), 'from-env');
    });

    test('环境变量为空时回落配置文件', () {
      expect(resolveAiKey('', cfg), 'from-config');
      expect(resolveAiKey(null, cfg), 'from-config');
      expect(resolveAiKey('   ', cfg), 'from-config');
    });

    test('两处都空 -> 空串（视为未配置）', () {
      expect(resolveAiKey(null, {'providers': {'deepseek': {}}}), '');
      expect(resolveAiKey(null, {}), '');
      expect(resolveAiKey('', {'providers': {}}), '');
    });

    test('去掉首尾空白', () {
      expect(resolveAiKey('  k  ', cfg), 'k');
      expect(resolveAiKey(null, {
        'providers': {
          'deepseek': {'api_key': '  k2  '}
        }
      }), 'k2');
    });

    test('provider 名不匹配时视为未配置', () {
      expect(resolveAiKey(null, cfg, 'other'), '');
    });

    test('只支持一个环境变量名（多来源会多一层优先级要解释）', () {
      expect(aiKeyEnvVar, 'LUPA_AI_KEY');
    });
  });
}
