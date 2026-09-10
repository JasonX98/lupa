// Lupa 配置 — 服务商 URL 全部走配置文件，不硬编码。
// 解析顺序：LUPA_HOME/config.json > 内置默认，浅合并（数据目录解析见 lib/data/data_home.dart）。
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
  // 设置模块：写入 config.json 的嵌套 settings 块。见 specs/settings/spec.md。
  'settings': {
    'theme': 'system', // system | light | dark
    'defFontSize': 14, // 12–18
    'showEnglish': true,
    'defaultAccent': 'us', // us | uk
    'reviewAutoRead': false,
    'dataDir': null, // 显式切换数据目录后写绝对路径；null = 用 LUPA_HOME/exe 默认
  },
};

const String configFile = 'config.json';

/// 加载配置。文件不存在则写入默认配置后返回默认。
///
/// 用深合并（Deep merge）：用户文件可以只写想覆盖的键，
/// 嵌套对象（providers.youdao.*、settings.*）会与默认值逐级合并，
/// 避免缺少某个 settings 键时丢默认值。
Map<String, Object?> loadConfig([Directory? home]) {
  final dir = Directory(p.absolute((home ?? configHome()).path));
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
  return _deepMerge(defaultConfig, user);
}

/// 写回配置：把整份 config 写到磁盘，并刷新数据目录覆盖缓存。
/// 调用方（AppState）负责更新内存 config 与 notifyListeners。
void saveConfig(Map<String, Object?> config, [Directory? home]) {
  final dir = Directory(p.absolute((home ?? configHome()).path));
  dir.createSync(recursive: true);
  File(p.join(dir.path, configFile))
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(config),
          encoding: utf8);
  reloadDataHomeOverride();
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

/// 深合并：override 覆盖 base，嵌套 Map 递归合并。
Map<String, Object?> _deepMerge(
    Map<String, Object?> base, Map<String, Object?> override) {
  final result = _deepCopy(base);
  override.forEach((k, v) {
    final bv = result[k];
    if (v is Map && bv is Map) {
      result[k] =
          _deepMerge(bv.cast<String, Object?>(), v.cast<String, Object?>());
    } else {
      result[k] = v;
    }
  });
  return result;
}
