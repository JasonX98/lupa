// AI 缓存读写 —— ai_cache 表的唯一实现（键格式、信封结构、命中计数）。
//
// 键：`<provider>/<model>:<word小写>:<feature>`（design D2）
//   - 模型折进 provider 段：换模型天然分家，无需迁移、无需清缓存
//   - word 段必须小写（与 media 层的 word.toLowerCase() 一致，别破例）
//   - feature 段见 card.dart 的 AiFeature.cacheFeature
//
// payload 是信封（design D2 / D8）：
//   {"valid": true|false, "card": {...}|null, "raw": "...", "model": "...",
//    "usage": {...}, "reason": "..."}
//   保留 raw 与 usage 是为了「读取端稳定」与「调试/成本可见」两不误。
//
// 不合格条目（valid=false）**不删除**：删了用户每次重查都要再烧一次钱；
// 留着但读取时不渲染、不自动重试，等用户主动「重新生成」（design D4-4）。
import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/notebook_db.dart';
import 'card.dart';

/// 三段式缓存键。word 段强制小写。
String aiCacheKey({
  required String provider,
  required String model,
  required String word,
  required AiFeature feature,
}) =>
    '$provider/$model:${word.trim().toLowerCase()}:${feature.cacheFeature}';

/// 一条缓存记录。
class AiCacheEntry {
  /// 信封里的 `valid`：校验是否通过。
  final bool valid;

  /// 信封里的 `card`（不合格时为 null）。
  final AiCard? card;

  /// 信封里的 `reason`（不合格原因，修复重试用）。
  final String reason;

  /// 模型原始输出（排查用）。
  final String raw;

  final String model;
  final int promptTokens;
  final int completionTokens;
  final int cacheHitTokens;

  const AiCacheEntry({
    required this.valid,
    this.card,
    this.reason = '',
    this.raw = '',
    this.model = '',
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cacheHitTokens = 0,
  });
}

/// 组装信封 JSON。写入端**必须**用这个函数，因为 aiCacheStats 靠
/// `"valid":false` 这个紧凑写法统计不合格条目数（json.encode 不产生空格）。
String encodeEnvelope({
  required bool valid,
  AiCard? card,
  String raw = '',
  String model = '',
  int promptTokens = 0,
  int completionTokens = 0,
  int cacheHitTokens = 0,
  String reason = '',
}) =>
    json.encode({
      'valid': valid,
      'card': card == null ? null : cardToJson(card),
      'raw': raw,
      'model': model,
      'usage': {
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'prompt_cache_hit_tokens': cacheHitTokens,
      },
      'reason': reason,
    });

/// AiCard -> JSON（与 card.dart 的解析器互逆）。
Map<String, Object?> cardToJson(AiCard c) => {
      'word': c.word,
      'canonical': c.canonical,
      'is_known_word': c.isKnownWord,
      'phonetic': c.phonetic,
      'translation': c.translation,
      'definition': c.definition,
      'pos': c.pos,
      'examples': c.examples
          .map((e) => {'en': e.en, 'zh': e.zh})
          .toList(),
      'senses': c.senses
          .map((g) => {
                'pos': g.label,
                'gloss': g.gloss,
                'examples': g.examples
                    .map((e) => {'en': e.en, 'zh': e.zh})
                    .toList(),
              })
          .toList(),
      'collocations': c.collocations
          .map((g) => {
                'phrase': g.label,
                'gloss': g.gloss,
                'examples': g.examples
                    .map((e) => {'en': e.en, 'zh': e.zh})
                    .toList(),
              })
          .toList(),
    };

Future<Database> _open(String nbPath) async {
  initDatabaseFactory();
  final con = await databaseFactory.openDatabase(p.absolute(nbPath),
      options: OpenDatabaseOptions(singleInstance: false));
  return con;
}

/// 读取缓存。命中时 `hit_count` 加一。未命中返回 null。
Future<AiCacheEntry?> readAiCache(String nbPath, String key) async {
  await ensureNotebookDb(nbPath);
  final con = await _open(nbPath);
  try {
    final rows = await con.rawQuery(
        'SELECT payload, model, prompt_tokens, completion_tokens, '
        'cache_hit_tokens FROM ai_cache WHERE cache_key = ?',
        [key]);
    if (rows.isEmpty) return null;
    await con.rawUpdate(
        'UPDATE ai_cache SET hit_count = hit_count + 1 WHERE cache_key = ?',
        [key]);
    return _decode(rows.first);
  } finally {
    await con.close();
  }
}

/// 只读地看一眼缓存是否存在（**不加命中计数**）。用于「已保存快照优先」判定。
Future<bool> hasAiCache(String nbPath, String key) async {
  await ensureNotebookDb(nbPath);
  final con = await _open(nbPath);
  try {
    final rows = await con
        .rawQuery('SELECT 1 FROM ai_cache WHERE cache_key = ? LIMIT 1', [key]);
    return rows.isNotEmpty;
  } finally {
    await con.close();
  }
}

AiCacheEntry _decode(Map<String, Object?> row) {
  final payload = (row['payload'] as String?) ?? '{}';
  Object? env;
  try {
    env = json.decode(payload);
  } catch (_) {
    env = null;
  }
  final m = env is Map ? env.cast<String, Object?>() : const <String, Object?>{};
  final valid = m['valid'] == true;
  AiCard? card;
  final cardPart = m['card'];
  if (valid && cardPart is Map) {
    // 复用解析器：信封里的 card 与模型原始输出是同一套字段
    final o = parseAiCard(json.encode(cardPart));
    card = o.card;
  }
  final usage = m['usage'];
  final u = usage is Map ? usage.cast<String, Object?>() : const <String, Object?>{};
  int i(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
  return AiCacheEntry(
    valid: valid,
    card: card,
    reason: (m['reason'] as String?) ?? '',
    raw: (m['raw'] as String?) ?? '',
    model: (m['model'] as String?) ?? (row['model'] as String?) ?? '',
    promptTokens: i(u['prompt_tokens']) | i(row['prompt_tokens']),
    completionTokens:
        i(u['completion_tokens']) | i(row['completion_tokens']),
    cacheHitTokens:
        i(u['prompt_cache_hit_tokens']) | i(row['cache_hit_tokens']),
  );
}

/// 写入（或覆盖）一条缓存。返回 cache_key。
///
/// [model] 是**配置的**模型（拼进缓存键与 provider 段）；[responseModel] 是
/// 服务端回报的模型（只进信封，用于观测「实际用了哪个模型」）。两者通常相同，
/// 但服务端可能把别名解析成具体版本号，所以不合并。
Future<String> writeAiCache(
  String nbPath, {
  required String provider,
  required String model,
  required String word,
  required AiFeature feature,
  required int promptVersion,
  required bool valid,
  AiCard? card,
  String raw = '',
  String reason = '',
  String responseModel = '',
  int promptTokens = 0,
  int completionTokens = 0,
  int cacheHitTokens = 0,
}) async {
  await ensureNotebookDb(nbPath);
  final key = aiCacheKey(
      provider: provider, model: model, word: word, feature: feature);
  final effectiveModel = responseModel.isEmpty ? model : responseModel;
  final payload = encodeEnvelope(
    valid: valid,
    card: card,
    raw: raw,
    model: effectiveModel,
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    cacheHitTokens: cacheHitTokens,
    reason: reason,
  );
  final con = await _open(nbPath);
  try {
    await con.execute(
      'INSERT INTO ai_cache (cache_key, word, provider, feature, '
      'prompt_version, payload, fetched_at, hit_count, model, '
      'prompt_tokens, completion_tokens, cache_hit_tokens) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?) '
      'ON CONFLICT(cache_key) DO UPDATE SET '
      'payload = excluded.payload, prompt_version = excluded.prompt_version, '
      'fetched_at = excluded.fetched_at, model = excluded.model, '
      'prompt_tokens = excluded.prompt_tokens, '
      'completion_tokens = excluded.completion_tokens, '
      'cache_hit_tokens = excluded.cache_hit_tokens',
      [
        key,
        word.trim(),
        '$provider/$model',
        feature.cacheFeature,
        promptVersion,
        payload,
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        effectiveModel,
        promptTokens,
        completionTokens,
        cacheHitTokens,
      ],
    );
    return key;
  } finally {
    await con.close();
  }
}

/// 删除某个词的全部缓存条目（「重新生成」用）。返回删除条数。
///
/// 按 `<任意 provider>/<任意 model>:<word小写>:<任意 feature>` 匹配 —— 用户点
/// 「重新生成」时应当把该词的**所有**旧产物都清掉，而不是只清当前模型那一份。
Future<int> deleteAiCacheForWord(String nbPath, String word) async {
  await ensureNotebookDb(nbPath);
  final con = await _open(nbPath);
  try {
    return await con.rawDelete(
        'DELETE FROM ai_cache WHERE word = ? COLLATE NOCASE', [word.trim()]);
  } finally {
    await con.close();
  }
}
