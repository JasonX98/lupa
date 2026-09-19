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
    },
    // AI 服务商：与 youdao 同构（连谁归 providers），复用 providerConfig()。
    // 行为开关（要不要用）归 settings.ai，见下。
    'deepseek': {
      'base_url': 'https://api.deepseek.com',
      'model': 'deepseek-flash',
      'api_key': '',
      'timeout_sec': 30,
    },
  },
  // 设置模块：写入 config.json 的嵌套 settings 块。见 specs/settings/spec.md。
  'settings': {
    'theme': 'system', // system | light | dark
    'defFontSize': 14, // 12–18
    'showEnglish': true,
    'defaultAccent': 'us', // us | uk
    'reviewAutoRead': false,
    'dataDir': null, // 显式切换数据目录后写绝对路径；null = 用 LUPA_HOME/exe 默认
    // AI 行为开关。enabled 默认 false：首次运行没有密钥，默认开会让用户
    // 第一次查词就撞错误弹窗。正确引导顺序是「填密钥 -> 提示可启用」。
    // 字段名用 providerName 而非 provider，避免与顶层 default_provider
    // （音标/TTS 的服务商）混淆 —— 两者是完全不同的维度。
    'ai': {
      'enabled': false,
      'providerName': 'deepseek',
      'autoEnrich': true,
    },
  },
};

/// AI 密钥的环境变量名。**只支持这一个名字** —— 多一个来源就多一层优先级
/// 要解释，而收益只是「少设一个变量」。
const String aiKeyEnvVar = 'LUPA_AI_KEY';

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

/// 解析 AI 密钥：`LUPA_AI_KEY` 环境变量优先于 `config.json`。
///
/// 纯函数形式便于单测（flutter test 无法设进程环境变量）。
/// 空串视为未配置 —— 否则「填了密钥又删掉」会退化成用空串去请求。
String resolveAiKey(String? envValue, Map<String, Object?> config, [String provider = 'deepseek']) {
  final env = envValue?.trim();
  if (env != null && env.isNotEmpty) return env;
  final providers = config['providers'];
  if (providers is Map) {
    final pcfg = providers[provider];
    if (pcfg is Map) {
      final k = pcfg['api_key'];
      if (k is String) return k.trim();
    }
  }
  return '';
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
