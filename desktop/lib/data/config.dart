// Lupa 配置 — 服务商 URL 全部走配置文件，不硬编码。
// 与 Python 版 src/lupa/config.py 行为对齐：LUPA_HOME/config.json > 内置默认，浅合并。
// 数据目录解析见 lib/data/data_home.dart。
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'data_home.dart';

/// 内置默认（首次运行时原样写入 config.json，用户可自行修改）
const Map<String, Object?> defaultConfig = {
  'default_provider': 'youdao',
  'providers': {
    'youdao': {
      'phonetic_url':
          'https://dict.youdao.com/jsonapi?jsonversion=2&client=mobile'
              '&q={word}&dicts=%7B%22count%22%3A99%2C%22dicts%22%3A%5B%5B%22ec%22%5D%5D%7D',
      // {accent} = 1(英音) / 2(美音)
      'tts_url': 'https://dict.youdao.com/dictvoice?audio={word}&type={accent}',
    }
  },
};

const String configFile = 'config.json';

/// 加载配置。文件不存在则写入默认配置后返回默认。
Map<String, Object?> loadConfig([Directory? home]) {
  final dir = Directory(p.absolute((home ?? dataHome()).path));
  final file = File(p.join(dir.path, configFile));
  if (!file.existsSync()) {
    dir.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(defaultConfig),
      encoding: utf8,
    );
    return _deepCopy(defaultConfig);
  }
  final user =
      json.decode(file.readAsStringSync(encoding: utf8)) as Map<String, Object?>;
  // 浅合并：用户文件只需写想覆盖的键
  final merged = _deepCopy(defaultConfig);
  merged.updateAll((k, v) => user.containsKey(k) ? user[k]! : v);
  return merged;
}

/// 取指定 provider 的 URL 模板；不存在抛 ArgumentError（对应 Python KeyError）。
Map<String, Object?> providerConfig(Map<String, Object?> config,
    [String? provider]) {
  final name = provider ??
      (config['default_provider'] as String? ?? 'youdao');
  final providers = config['providers'] as Map<String, Object?>? ?? {};
  if (!providers.containsKey(name)) {
    throw ArgumentError('配置中没有该 provider: $name');
  }
  return providers[name]! as Map<String, Object?>;
}

Map<String, Object?> _deepCopy(Map<String, Object?> src) => {
      for (final e in src.entries)
        e.key: e.value is Map
            ? _deepCopy((e.value! as Map).cast<String, Object?>())
            : e.value,
    };
