// Lupa 数据目录解析 — 唯一来源（portable-data-dir change + settings-module change）。
//
// 两颗"家"：
//   configHome()  — config.json 固定所在（LUPA_HOME > `<exe>/lupa_data`）。
//                   config.json 是应用级设置，不随数据目录覆盖而移动。
//   dataHome()    — 实际数据所在目录（notebook.sqlite / dict.sqlite / exports/）。
//                   解析顺序：settings.dataDir（config.json 覆盖）> LUPA_HOME > `<exe>/lupa_data`。
//
// 与 Python CLI 行为声明解耦（Python 现仅作 MVP 验证，不作后续契约）。
// schema.sql 是独立模板，不走本目录（见 notebook_db.dart loadSchemaSql）。
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 运行时数据目录覆盖缓存（来自 config.json 的 settings.dataDir）。
String? _homeOverride;
bool _overrideLoaded = false;

/// 测试/运行时 config.json 所在目录覆盖（用于把 config 指到临时目录）。
String? _configHomeOverride;

/// config.json 所在目录。LUPA_HOME 环境变量优先，默认 `<exe>/lupa_data`。
Directory configHome() {
  if (_configHomeOverride != null) {
    return Directory(p.absolute(_configHomeOverride!));
  }
  final env = Platform.environment['LUPA_HOME'];
  if (env != null && env.isNotEmpty) return Directory(p.absolute(env));
  final exeDir = p.dirname(Platform.resolvedExecutable);
  return Directory(p.absolute(p.join(exeDir, 'lupa_data')));
}

/// 测试/运行时把 config 所在目录覆盖到指定路径。
void setConfigHomeOverride(String path) => _configHomeOverride = p.absolute(path);

/// 清除 config 所在目录覆盖。
void clearConfigHomeOverride() => _configHomeOverride = null;

/// 数据目录。解析顺序：settings.dataDir 覆盖 > configHome()。
///
/// 首次调用（或覆盖变更后）读取 configHome()/config.json 的 settings.dataDir，
/// 命中非空则以其为准；否则回退 configHome()。
Directory dataHome() {
  if (!_overrideLoaded) reloadDataHomeOverride();
  if (_homeOverride != null) return Directory(p.absolute(_homeOverride!));
  return configHome();
}

/// 读取 config.json 的 settings.dataDir 覆盖，刷新缓存。
/// 由 config.dart 的 saveConfig 在写配置后调用；也可手动调用以感知外部改动。
void reloadDataHomeOverride() {
  _overrideLoaded = true;
  _homeOverride = null;
  final cfgFile = File(p.join(configHome().path, 'config.json'));
  if (!cfgFile.existsSync()) return;
  try {
    final cfg = json.decode(cfgFile.readAsStringSync(encoding: utf8))
        as Map<String, Object?>;
    _homeOverride = resolveDataDirOverride(cfg);
  } catch (_) {
    // 配置损坏/不可读：忽略，回退 configHome()
  }
}

/// 从 config 提取数据目录覆盖值（null 表示未覆盖）。纯函数，便于测试。
String? resolveDataDirOverride(Map<String, Object?> cfg) {
  final s = cfg['settings'];
  if (s is Map) {
    final d = s['dataDir'];
    if (d is String && d.trim().isNotEmpty) return d.trim();
  }
  return null;
}

/// 显式设置数据目录覆盖（运行时切换数据目录时由 AppState 调用）。
void setDataHomeOverride(String path) {
  _homeOverride = p.absolute(path);
  _overrideLoaded = true;
}

/// 清除数据目录覆盖。
void clearDataHomeOverride() {
  _homeOverride = null;
  _overrideLoaded = true;
}
