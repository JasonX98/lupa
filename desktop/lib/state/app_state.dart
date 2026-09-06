// Lupa 全局应用状态 — UI 层唯一的状态容器（ChangeNotifier）。
// 只做"编排"：把 dict / notebook / media / export 四个业务模块接到页面上。
// 业务规则全部在数据层纯函数里，这里不写任何 SQL 与调度逻辑。
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:lupa/data/config.dart';
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
  late final String nbPath;
  late final String dictDb;

  Map<String, int> stats = const {};
  List<NotebookEntry> entries = const [];
  List<NotebookEntry> due = const [];
  ThemeMode themeMode = ThemeMode.system;

  final AudioPlayer _player = AudioPlayer();

  /// 启动初始化：加载配置、确保生词本库存在、拉一次统计。
  Future<void> init() async {
    config = loadConfig();
    await ensureNotebook();
    final home = dataHome();
    nbPath = notebookDbPath(home);
    dictDb = dictDbPath(home);
    await refresh();
  }

  String _providerUrl(String key) =>
      providerConfig(config)[key]! as String;

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
    await _player.stop();
    await _player.play(BytesSource(Uint8List.fromList(audio.blob)));
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

  // ---- 外观 ----

  void toggleTheme() {
    themeMode = switch (themeMode) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    notifyListeners();
  }

  String get themeLabel => switch (themeMode) {
        ThemeMode.light => '浅色',
        ThemeMode.dark => '深色',
        ThemeMode.system => '跟随系统',
      };
}
