// Lupa 全局应用状态 — UI 层唯一的状态容器（ChangeNotifier）。
// 只做"编排"：把 dict / notebook / media / export 四个业务模块接到页面上。
// 业务规则全部在数据层纯函数里，这里不写任何 SQL 与调度逻辑。
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:lupa/ai/card.dart' as ai_card;
import 'package:lupa/ai/client.dart' as ai_client;
import 'package:lupa/ai/enrich.dart' as ai_enrich;
import 'package:lupa/ai/repo.dart' as ai_repo;
import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_files.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/export/apkg.dart' as apkg_export;
import 'package:lupa/export/csv.dart' as csv_export;
import 'package:lupa/export/phrase_apkg.dart' as phrase_apkg_export;
import 'package:lupa/export/phrase_csv.dart' as phrase_csv_export;
import 'package:lupa/media/phonetic.dart';
import 'package:lupa/media/tts.dart';
import 'package:lupa/notebook/repo.dart';
import 'package:lupa/phrase/repo.dart' as phrase_repo;

/// 全局应用状态。
class AppState extends ChangeNotifier {
  late final Map<String, Object?> config;
  late String nbPath;
  late String dictDb;

  Map<String, int> stats = const {};
  List<NotebookEntry> entries = const [];
  List<NotebookEntry> due = const [];
  // ---- 短语集状态（与单词生词本完全隔离）----
  List<phrase_repo.PhraseEntry> phraseEntries = const [];
  List<phrase_repo.PhraseEntry> phraseDue = const [];
  Map<String, int> phraseStats = const {};
  List<String> phraseTags = const [];
  ThemeMode themeMode = ThemeMode.system;
  // ---- 设置模块状态（config['settings'] 的运行时镜像）----
  int defFontSize = 14;
  bool showEnglish = true;
  String defaultAccent = 'us';
  bool reviewAutoRead = false;
  // ---- AI 设置状态 ----
  bool aiEnabled = false;
  String aiProviderName = 'deepseek';
  bool aiAutoEnrich = true;

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
    final ai = _aiSettings();
    aiEnabled = ai['enabled'] as bool? ?? false;
    aiProviderName = (ai['providerName'] as String?) ?? 'deepseek';
    aiAutoEnrich = ai['autoEnrich'] as bool? ?? true;
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
    phraseStats = await phrase_repo.phraseStats(nbPath);
    phraseEntries = await phrase_repo.listPhrases(nbPath, limit: 500);
    phraseDue = await phrase_repo.duePhrases(nbPath, limit: 100);
    phraseTags = await phrase_repo.phraseTags(nbPath);
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
  // 数据层不动：notes.flds 里的 ECDICT 音标是导出契约的一部分（flds 仍为 5 段）。
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

  /// 复习评分。返回回执（含撤销所需的评分前快照）。
  Future<AnswerReceipt> answer(int cardId, int ease) =>
      answerCard(nbPath, cardId, ease);

  /// 撤销一次评分（按回执恢复；只允许该卡最新一条历史）。
  Future<bool> undoAnswer(AnswerReceipt r) => undoAnswerCard(nbPath, r);

  // ---- 导出 ----

  /// 导出目录：LUPA_HOME/exports（自动创建）。
  String exportDir() {
    final d = Directory(p.join(dataHome().path, 'exports'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d.path;
  }

  /// 备份生词本（复制 notebook.sqlite 为带时间戳备份）。返回备份路径。
  Future<String> backupNote() => backupNotebook(nbPath);

  /// 导出文件名基名（不含扩展名）：生词本 `lupa-<yyyyMMdd-HHmm>`、
  /// 短语集 `lupa-phrases-<yyyyMMdd-HHmm>`。两条命名线分开，
  /// 同一分钟内先后导出两类不会互相覆盖（见 design D4）。
  String exportBaseName({bool phrases = false}) {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${n.year}${two(n.month)}${two(n.day)}'
        '-${two(n.hour)}${two(n.minute)}';
    return '${phrases ? 'lupa-phrases' : 'lupa'}-$stamp';
  }

  /// 生词本导出文件名，如 lupa-20260906-1015.apkg
  String exportFileName(String ext) => '${exportBaseName()}.$ext';

  /// 短语集导出文件名，如 lupa-phrases-20260906-1015.apkg
  String phraseExportFileName(String ext) => '${exportBaseName(phrases: true)}.$ext';

  Future<apkg_export.ExportReport> exportApkgTo(String path) =>
      apkg_export.exportApkg(nbPath, path);

  Future<csv_export.CsvExportReport> exportCsvTo(String path) =>
      csv_export.exportCsv(nbPath, path);

  // ---- 短语集 CRUD / 复习 / 导出 ----

  Future<int> addPhraseEntry(phrase_repo.PhraseInput input) async {
    final id = await phrase_repo.addPhrase(nbPath, input);
    await refresh();
    return id;
  }

  Future<void> updatePhraseEntry(int id, phrase_repo.PhraseInput input) async {
    await phrase_repo.updatePhrase(nbPath, id, input);
    await refresh();
  }

  Future<bool> removePhraseEntry(int id) async {
    final ok = await phrase_repo.removePhrase(nbPath, id);
    await refresh();
    return ok;
  }

  /// 短语复习评分。返回回执（含撤销所需的评分前快照）。
  Future<phrase_repo.PhraseAnswerReceipt> answerPhraseCard(int id, int ease) =>
      phrase_repo.answerPhrase(nbPath, id, ease);

  /// 撤销一次短语评分。
  Future<bool> undoAnswerPhrase(phrase_repo.PhraseAnswerReceipt r) =>
      phrase_repo.undoAnswerPhrase(nbPath, r);

  /// 导出短语集 apkg。`tag` 非空时只导出带该标签的短语（null/空 = 全部）。
  Future<phrase_apkg_export.PhraseExportReport> exportPhraseApkgTo(
          String path, {String? tag}) =>
      phrase_apkg_export.exportPhraseApkg(nbPath, path, tag: tag);

  /// 导出短语集 CSV。`tag` 语义同 [exportPhraseApkgTo]。
  Future<phrase_csv_export.PhraseCsvExportReport> exportPhraseCsvTo(
          String path, {String? tag}) =>
      phrase_csv_export.exportPhraseCsv(nbPath, path, tag: tag);

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

  // ---- AI 设置 ----

  Map<String, Object?> _aiSettings() {
    final s = _settings();
    final ai = s['ai'];
    if (ai is Map) return ai.cast<String, Object?>();
    s['ai'] = <String, Object?>{};
    return s['ai'] as Map<String, Object?>;
  }

  /// AI 服务商配置块（providers.<name>）。
  Map<String, Object?> aiProviderConfig() {
    final providers = config['providers'];
    final m = (providers is Map ? providers : const {}).cast<String, Object?>();
    final pcfg = m[aiProviderName];
    if (pcfg is Map) return pcfg.cast<String, Object?>();
    final fresh = <String, Object?>{};
    m[aiProviderName] = fresh;
    config['providers'] = m;
    return fresh;
  }

  /// 取 AI 连接参数。密钥按 `LUPA_AI_KEY` > `config.json` 解析。
  String get aiBaseUrl =>
      (aiProviderConfig()['base_url'] as String?)?.trim() ?? '';
  String get aiModel => (aiProviderConfig()['model'] as String?)?.trim() ?? '';
  int get aiTimeoutSec =>
      (aiProviderConfig()['timeout_sec'] as num?)?.toInt() ?? 30;

  /// 密钥来源：环境变量优先。返回空串 = 未配置。
  String get aiApiKey => resolveAiKey(
      Platform.environment[aiKeyEnvVar], config, aiProviderName);

  /// 密钥是否来自环境变量（UI 要据此提示「此处输入无效」）。
  bool get aiKeyFromEnv =>
      (Platform.environment[aiKeyEnvVar] ?? '').trim().isNotEmpty;

  /// AI 是否**可用**：已启用 + 有密钥。UI 与编排都该看这个而不是只看 enabled。
  bool get aiReady => aiEnabled && aiApiKey.isNotEmpty;

  /// 构造客户端。未就绪时返回 null（调用方不应为「AI 没开」写 try/catch）。
  ai_client.AiClient? aiClient() {
    if (!aiReady) return null;
    return ai_client.AiClient(ai_client.AiConfig(
      baseUrl: aiBaseUrl.isEmpty ? 'https://api.deepseek.com' : aiBaseUrl,
      apiKey: aiApiKey,
      model: aiModel.isEmpty ? 'deepseek-flash' : aiModel,
      timeout: Duration(seconds: aiTimeoutSec),
    ));
  }

  void setAiEnabled(bool v) {
    _aiSettings()['enabled'] = v;
    aiEnabled = v;
    saveConfig(config);
    notifyListeners();
  }

  void setAiAutoEnrich(bool v) {
    _aiSettings()['autoEnrich'] = v;
    aiAutoEnrich = v;
    saveConfig(config);
    notifyListeners();
  }

  void setAiProviderName(String v) {
    _aiSettings()['providerName'] = v;
    aiProviderName = v;
    saveConfig(config);
    notifyListeners();
  }

  /// 写 AI 连接配置（base_url / model / api_key / timeout_sec）。
  void setAiConnection({String? baseUrl, String? model, String? apiKey, int? timeoutSec}) {
    final pcfg = aiProviderConfig();
    if (baseUrl != null) pcfg['base_url'] = baseUrl.trim();
    if (model != null) pcfg['model'] = model.trim();
    if (apiKey != null) pcfg['api_key'] = apiKey.trim();
    if (timeoutSec != null) pcfg['timeout_sec'] = timeoutSec;
    saveConfig(config);
    notifyListeners();
  }

  /// AI 缓存统计。
  Future<AiCacheStats> aiCacheStatsNow() => aiCacheStats(nbPath);

  /// 清理 AI 缓存（**不动**已保存的例句与搭配）。
  Future<int> clearAiCacheNow() async {
    final n = await clearAiCache(nbPath);
    notifyListeners();
    return n;
  }

  /// 对某个词做一次 AI 补齐/生成。供 UI 调用。
  ///
  /// [mode] 决定 feature：词库命中用 enrich/enrichPlain，未命中用 define。
  Future<ai_enrich.AiOutcome> enrichWord({
    required String word,
    required ai_card.AiFeature feature,
    List<String> expectedPos = const [],
    List<String> knownForms = const [],
    String existingTranslation = '',
    bool forceRegenerate = false,
  }) async {
    if (forceRegenerate) {
      // 「重新生成」：先删该词的全部缓存，再走正常流程
      await ai_repo.deleteAiCacheForWord(nbPath, word);
    }
    return ai_enrich.enrich(
      nbPath,
      ai_enrich.AiEnrichRequest(
        word: word,
        feature: feature,
        expectedPos: expectedPos,
        knownForms: knownForms,
        existingTranslation: existingTranslation,
      ),
      client: aiClient(),
      provider: aiProviderName,
      model: aiModel.isEmpty ? 'deepseek-flash' : aiModel,
    );
  }

  // ---- 查词页的 AI 状态（渐进增强，照 preloadPhonetics 的骨架）----
  //
  // 三态缓存：
  //   _aiOutcomes  已取到的结果（含降级/失败原因）
  //   _aiLoading   正在请求中的词（并发去重）
  // 每成功一个 notifyListeners 一次，列表/卡片渐进增强。
  final Map<String, ai_enrich.AiOutcome> _aiOutcomes = {};
  final Set<String> _aiLoading = {};

  ai_enrich.AiOutcome? aiOutcomeOf(String word) =>
      _aiOutcomes[word.trim().toLowerCase()];

  bool isAiLoading(String word) =>
      _aiLoading.contains(word.trim().toLowerCase());

  /// 取该词的 AI 内容（缓存优先，不重复请求）。
  ///
  /// [feature] 为 null 时按词库命中情况自动选：命中且能解析词性 -> enrich；
  /// 命中但无词性且是内容词 -> enrichPlain；命中但含大写（缩写/专名）-> 不请求；
  /// 未命中 -> define。
  Future<ai_enrich.AiOutcome?> loadAiFor(
    String word, {
    ai_card.AiFeature? feature,
    List<String> expectedPos = const [],
    List<String> knownForms = const [],
    String existingTranslation = '',
    bool forceRegenerate = false,
  }) async {
    final key = word.trim().toLowerCase();
    if (key.isEmpty) return null;
    if (!forceRegenerate) {
      final cached = _aiOutcomes[key];
      if (cached != null) return cached;
      if (_aiLoading.contains(key)) return null; // 已在请求中，不重复发起
    }
    if (!aiReady) {
      final none = const ai_enrich.AiOutcome(reason: 'AI 未启用');
      _aiOutcomes[key] = none;
      notifyListeners();
      return none;
    }
    _aiLoading.add(key);
    notifyListeners();
    try {
      final f = feature ??
          (expectedPos.isNotEmpty
              ? ai_card.AiFeature.enrich
              : ai_card.AiFeature.enrichPlain);
      final outcome = await enrichWord(
        word: word,
        feature: f,
        expectedPos: expectedPos,
        knownForms: knownForms,
        existingTranslation: existingTranslation,
        forceRegenerate: forceRegenerate,
      );
      _aiOutcomes[key] = outcome;
      return outcome;
    } catch (e) {
      final failed = ai_enrich.AiOutcome(reason: 'AI 补齐失败: $e');
      _aiOutcomes[key] = failed;
      return failed;
    } finally {
      _aiLoading.remove(key);
      notifyListeners();
    }
  }

  /// 请求切到设置页（AI 鉴权失败时由查词页/详情弹窗调用）。
  ///
  /// 用「请求计数」而非直接持有路由：AppState 不依赖 UI 层，
  /// AppShell 监听它并完成实际切换。
  int _openSettingsRequests = 0;
  int get openSettingsRequests => _openSettingsRequests;
  void requestOpenSettings() {
    _openSettingsRequests++;
    notifyListeners();
  }

  /// 丢弃某个词的 AI 状态（重新查询时清掉旧结果）。
  void forgetAi(String word) => _aiOutcomes.remove(word.trim().toLowerCase());

  /// 切库后清空 AI 状态（与音标缓存同理：缓存为 DB 背书，切库后旧条目无意义）。
  void clearAiState() {
    _aiOutcomes.clear();
    _aiLoading.clear();
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
    clearAiState();
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
