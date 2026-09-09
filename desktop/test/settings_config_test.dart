// 设置模块：config 深合并 / saveConfig 写回 / dataDir 覆盖政策 / 数据目录解析。
// 覆盖 specs/settings/spec.md 与 specs/desktop-app/spec.md 的配置契约。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';

Directory _tmpHome() {
  final d = Directory(p.join(Directory.systemTemp.path,
      'lupa_test_${DateTime.now().microsecondsSinceEpoch}'));
  d.createSync(recursive: true);
  return d;
}

void main() {
  group('loadConfig（深合并）', () {
    late Directory home;

    setUp(() => home = _tmpHome());
    tearDown(() => home.deleteSync(recursive: true));

    test('旧 config（无 settings 键）返回含默认 settings 的合并结果', () {
      // 先写一个没有 settings 的 config.json
      final file = File(p.join(home.path, configFile));
      file.writeAsStringSync(json.encode({
        'default_provider': 'youdao',
        'providers': {'youdao': {'tts_url': 'https://x/{word}'}},
      }), encoding: utf8);

      final cfg = loadConfig(home);
      expect(cfg['default_provider'], 'youdao');
      // 深合并：providers.youdao 保留默认 phonetic_url + 用户 tts_url
      final pcfg = providerConfig(cfg);
      expect(pcfg['tts_url'], 'https://x/{word}');
      expect(pcfg['phonetic_url'], isNotEmpty);
      // settings 补默认
      final s = cfg['settings'] as Map<String, Object?>;
      expect(s['theme'], 'system');
      expect(s['defFontSize'], 14);
      expect(s['showEnglish'], true);
      expect(s['defaultAccent'], 'us');
      expect(s['reviewAutoRead'], false);
      expect(s['dataDir'], isNull);
    });

    test('用户只写 settings.theme，其余 settings 默认保留', () {
      final file = File(p.join(home.path, configFile));
      file.writeAsStringSync(json.encode({
        'settings': {'theme': 'dark'},
      }), encoding: utf8);

      final cfg = loadConfig(home);
      final s = cfg['settings'] as Map<String, Object?>;
      expect(s['theme'], 'dark');
      expect(s['defFontSize'], 14); // 未写 → 默认
      expect(s['showEnglish'], true);
      expect(s['defaultAccent'], 'us');
    });

    test('文件不存在时写入默认配置', () {
      final cfg = loadConfig(home);
      expect(cfg['default_provider'], 'youdao');
      final file = File(p.join(home.path, configFile));
      expect(file.existsSync(), true);
    });
  });

  group('saveConfig（写回）', () {
    late Directory home;

    setUp(() => home = _tmpHome());
    tearDown(() => home.deleteSync(recursive: true));

    test('写回后文件内容与内存一致', () {
      final cfg = loadConfig(home);
      cfg['settings'] = {...(cfg['settings'] as Map).cast<String, Object?>(),
        'theme': 'dark', 'defFontSize': 18};
      saveConfig(cfg, home);

      final onDisk = json.decode(
          File(p.join(home.path, configFile)).readAsStringSync(encoding: utf8))
          as Map;
      expect(onDisk['settings']['theme'], 'dark');
      expect(onDisk['settings']['defFontSize'], 18);

      // 重新加载，验证读回与写回一致
      final reloaded = loadConfig(home);
      expect(((reloaded['settings'] as Map)['theme']), 'dark');
      expect(((reloaded['settings'] as Map)['defFontSize']), 18);
    });

    test('dataDir 仅在显式设置时写入，改主题不固化 dataDir', () {
      final cfg = loadConfig(home);
      // 只改主题，不动 dataDir
      cfg['settings'] = {...(cfg['settings'] as Map).cast<String, Object?>(),
        'theme': 'light'};
      saveConfig(cfg, home);

      final onDisk = json.decode(
          File(p.join(home.path, configFile)).readAsStringSync(encoding: utf8))
          as Map;
      expect(onDisk['settings']['dataDir'], isNull); // 未被固化
    });
  });

  group('dataHome 解析优先级', () {
    test('setDataHomeOverride 后 dataHome 指向覆盖目录', () {
      clearDataHomeOverride();
      final target = _tmpHome();
      setDataHomeOverride(target.path);
      expect(p.absolute(dataHome().path), p.absolute(target.path));
      clearDataHomeOverride();
      target.deleteSync(recursive: true);
    });

    test('clearDataHomeOverride 后回退 configHome', () {
      final before = dataHome(); // 触发加载
      setDataHomeOverride('/tmp/should-not-stick');
      clearDataHomeOverride();
      expect(p.absolute(dataHome().path), p.absolute(before.path));
    });
  });

  group('resolveDataDirOverride（纯函数）', () {
    test('settings.dataDir 为非空字符串时返回它', () {
      expect(resolveDataDirOverride({'settings': {'dataDir': '/data/b'}}),
          '/data/b');
    });

    test('dataDir 为 null / 空串 / 缺失时返回 null', () {
      expect(resolveDataDirOverride({'settings': {'dataDir': null}}), isNull);
      expect(resolveDataDirOverride({'settings': {'dataDir': '  '}}), isNull);
      expect(resolveDataDirOverride({'settings': {}}), isNull);
      expect(resolveDataDirOverride({}), isNull);
    });
  });
}
