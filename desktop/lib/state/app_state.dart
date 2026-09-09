// Lupa 全局应用状态 — UI 层唯一的状态容器（ChangeNotifier）。
// 只做"编排"：把 dict / notebook / media / export 四个业务模块接到页面上。
// 业务规则全部在数据层纯函数里，这里不写任何 SQL 与调度逻辑。
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_files.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/export/apkg.dart' as apkg_export;
import 'package:lupa/export/csv.dart' as csv_export;
import 'package:lupa/media/phonetic.dart';
import 'package:lupa/media/tts.dart';
import 'package:lupa/notebook/repo.dart';

/// 全局应用状态。
class AppState extends ChangeNotifier {
  late final Map<String, Object?> config;
  late String nbPath;
  late String dictDb;

  Map<String, int> stats = const {};
  List<NotebookEntry> entries = const [];
  List<NotebookEntry> due = const [];
  ThemeMode themeMode = ThemeMode.system;
  // ---- 设置模块状态（config['settings'] 的运行时镜像）----
  int defFontSize = 14;
  bool showEnglish = true;
  String defaultAccent = 'us';
  bool reviewAutoRead = false;

  AudioPlayer? _player; // 懒加载：speak() 时才创建，避免测试构造 AppState 依赖平台

  /// 启动初始化：加载配置、确保生词本库存在、拉一次统计。
  Future<void> init() async {
    config = loadConfig();
    final s = _settings();
    themeMode = _themeModeFromString(s['theme'] as String?);
    defFontSize = (s['defFontSize'] as num?)?.toInt() ?? 14;
    showEnglish = s['showEnglish'] as bool? ?? true;
    defaultAccent = (s['defaultAccent'] as String?) ?? 'us';
    reviewAutoRead = s['reviewAutoRead'] as bool? ?? false;
    await ensureNotebook();
    final home = dataHome();
    nbPath = notebookDbPath(home);
    dictDb = dictDbPath(home);
    await refresh();
  }

  String _providerUrl(String key) =>
      providerConfig(config)[key]! as String;

  /// 取当前 provider 的 URL 模板（设置页展示/编辑用）。
  String providerUrl(String key) =>
      providerConfig(config)[key]! as String;

  /// 编辑 provider URL 模板并写回 config。
  void setProviderUrl(String key, String url) {
    final pcfg = providerConfig(config);
    pcfg[key] = url.trim();
    saveConfig(config);
    notifyListeners();
  }

  /// 重拉统计 / 生词列表 / 到期队列，并通知监听者。
  Future<void> refresh() async {
    stats = await notebookStats(nbPath);
    entries = await listWords(nbPath, limit: 500);
    due = await dueWords(nbPath, limit: 100);
    notifyListeners();
  }

  /// 是否已在生词本（基于已加载的列表，MVP 规模内足够准确）。
  bool isInNotebook(String word) {
    final w = word.trim().toLowerCase();
    return entries.any((e) => e.word.toLowerCase() == w);
  }

  /// 加生词。异常（词未收录 / 重复）由调用方捕获后给用户提示。
  Future<int> add(String word) async {
    final noteId = await addWord(nbPath, dictDb, word, '');
    await refresh();
    return noteId;
  }

  /// 移除生词。返回是否确实删了。
  Future<bool> remove(String word) async {
    final ok = await removeWord(nbPath, word);
    await refresh();
    return ok;
  }

  /// 联网查音标（缓存优先）。离线时调用方自行兜底词库自带音标。
  Future<PhoneticResult> phonetic(String word) =>
      getPhonetic(nbPath, word, _providerUrl('phonetic_url'));

  // ---- 音标展示统一层 ----
  // 列表/复习/详情卡的音标都走「在线缓存优先」，与查词页同源，
  // 避免 ECDICT 老式音标（si'ri:n）与在线现代 IPA（səˈriːn）混排不一致。
  // 数据层不动：notes.flds 里的 ECDICT 音标是 Anki 导出契约的一部分。
  final Map<String, PhoneticResult> _phonetics = {};
  final Set<String> _phoneticLoading = {};

  /// 已取到的在线音标（可能为 null = 还没拉到，展示层回退 ECDICT 字段）。
  PhoneticResult? phoneticOf(String word) =>
      _phonetics[word.trim().toLowerCase()];

  /// 批量预热音标：逐词走 getPhonetic（缓存命中秒回，未命中联网），
  /// 每成功一个通知一次，列表渐进增强。失败静默（离线兜底 ECDICT）。
  Future<void> preloadPhonetics(Iterable<String> words) async {
    for (final w in words) {
      final key = w.trim().toLowerCase();
      if (_phonetics.containsKey(key) || _phoneticLoading.contains(key)) {
        continue;
      }
      _phoneticLoading.add(key);
      try {
        final p = await getPhonetic(nbPath, w, _providerUrl('phonetic_url'));
        _phonetics[key] = p;
        notifyListeners();
      } catch (_) {
        // 离线/未收录：静默，展示层回退 ECDICT 音标
      } finally {
        _phoneticLoading.remove(key);
      }
    }
  }

  /// 朗读：TTS 取音（缓存优先）→ 内存字节直喂播放器（BytesSource）。
  /// 不写临时文件——Windows 端走 Media Foundation 内存 IStream，无清理问题。
  Future<void> speak(String word, String accent) async {
    final audio = await getAudio(nbPath, word, accent, _providerUrl('tts_url'));
    final player = _player ??= AudioPlayer();
    await player.stop();
    await player.play(BytesSource(Uint8List.fromList(audio.blob)));
  }

  /// 复习评分。返回 (nextIvlDays, nextDueUnixSeconds)。
  Future<(int, int)> answer(int cardId, int ease) =>
      answerCard(nbPath, cardId, ease);

  // ---- 导出 ----

  /// 导出目录：LUPA_HOME/exports（自动创建）。
  String exportDir() {
    final d = Directory(p.join(dataHome().path, 'exports'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  /// 备份生词本（复制 notebook.sqlite 为带时间戳备份）。返回备份路径。
  Future<String> backupNote() => backupNotebook(nbPath);

  /// 带时间戳的导出文件名，如 lupa-20260906-1015.apkg
  String exportFileName(String ext) {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${n.year}${two(n.month)}${two(n.day)}'
        '-${two(n.hour)}${two(n.minute)}';
    return 'lupa-$stamp.$ext';
  }

  Future<apkg_export.ExportReport> exportApkgTo(String path) =>
      apkg_export.exportApkg(nbPath, path);

  Future<csv_export.CsvExportReport> exportCsvTo(String path) =>
      csv_export.exportCsv(nbPath, path);

  // ---- 设置模块 ----

  Map<String, Object?> _settings() {
    final s = config['settings'];
    if (s is Map) return s.cast<String, Object?>();
    config['settings'] = <String, Object?>{};
    return config['settings'] as Map<String, Object?>;
  }

  ThemeMode _themeModeFromString(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  void setTheme(String theme) {
    _settings()['theme'] = theme;
    themeMode = _themeModeFromString(theme);
    saveConfig(config);
    notifyListeners();
  }

  void setDefFontSize(int v) {
    _settings()['defFontSize'] = v;
    defFontSize = v;
    saveConfig(config);
    notifyListeners();
  }

  void setShowEnglish(bool v) {
    _settings()['showEnglish'] = v;
    showEnglish = v;
    saveConfig(config);
    notifyListeners();
  }

  void setDefaultAccent(String v) {
    _settings()['defaultAccent'] = v;
    defaultAccent = v;
    saveConfig(config);
    notifyListeners();
  }

  void setReviewAutoRead(bool v) {
    _settings()['reviewAutoRead'] = v;
    reviewAutoRead = v;
    saveConfig(config);
    notifyListeners();
  }

  /// 运行时切换数据目录。dst 已含 notebook.sqlite 则直接切换；
  /// 空目录且 copyExisting=true 时先复制 notebook/dict/exports，再切换。
  Future<void> switchDataDir(String newDir, {bool copyExisting = false}) async {
    final dst = Directory(p.absolute(newDir));
    dst.createSync(recursive: true);
    final dstNotebook = File(p.join(dst.path, 'notebook.sqlite'));
    if (!dstNotebook.existsSync() && copyExisting) {
      await copyDataDir(dataHome().path, dst.path);
    }
    nbPath = notebookDbPath(dst);
    dictDb = dictDbPath(dst);
    _settings()['dataDir'] = dst.path;
    saveConfig(config);
    _phonetics.clear(); // 音标缓存为 DB 背书，切库后旧条目无意义
    await refresh();
    notifyListeners();
  }

  /// LUPA_HOME 已设且与 settings.dataDir 不同时返回 true（方案甲分歧提示）。
  bool get dataDirDiverges => dataDirDivergent(
      Platform.environment['LUPA_HOME'], _settings()['dataDir'] as String?);
}

/// 纯逻辑：LUPA_HOME 已设且与数据目录覆盖（settings.dataDir）不同 → true。
/// 便于单测（flutter test 无法设置进程环境变量）。
bool dataDirDivergent(String? luHome, String? override) {
  final env = luHome?.trim();
  if (env == null || env.isEmpty) return false;
  final ov = override?.trim();
  if (ov == null || ov.isEmpty) return false;
  return p.normalize(p.absolute(env)) != p.normalize(p.absolute(ov));
}
