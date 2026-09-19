// AI 编排 —— 缓存 → 请求 → 校验 → 修复重试 → 落缓存。
//
// 这是 lib/ai 的对外入口：把 client / prompt / card / repo 四块接起来。
// 它不做 IO 以外的决策：所有判定都在纯函数里（card.dart 的校验、pos.dart 的
// 分流），这里只负责顺序与预算。
import 'client.dart';
import 'card.dart';
import 'prompt.dart';
import 'repo.dart';

/// 一次补齐/生成的结果。
class AiOutcome {
  /// 可用的词卡（校验通过或降级保留的部分）。
  final AiCard? card;

  /// 校验未完全通过（降级展示，界面要标注）。
  final bool partial;

  /// 未通过的原因（partial 时非空）。
  final String reason;

  /// 自证结果（仅 define 有意义）。
  final SelfProof? selfProof;

  /// 是否来自缓存。
  final bool fromCache;

  /// 实际发出的网络请求数（观测用）。
  final int requests;

  const AiOutcome({
    this.card,
    this.partial = false,
    this.reason = '',
    this.selfProof,
    this.fromCache = false,
    this.requests = 0,
  });

  bool get ok => card != null && !partial;
}

/// 编排参数。
class AiEnrichRequest {
  final String word;
  final AiFeature feature;

  /// 本地解析出的词性集合（full 补齐用）。
  final List<String> expectedPos;

  /// 已知词形（L5 用）。
  final List<String> knownForms;

  /// 词库已有释义（帮模型对齐义项）。
  final String existingTranslation;

  const AiEnrichRequest({
    required this.word,
    required this.feature,
    this.expectedPos = const [],
    this.knownForms = const [],
    this.existingTranslation = '',
  });
}

/// 执行一次补齐/生成。
///
/// [client] 为 null 时直接返回失败结果（AI 未配置），不抛异常 —— 调用方
/// （UI）不应该为「AI 没开」写 try/catch。
/// [sleep] 可注入以便测试不真的等待退避。
Future<AiOutcome> enrich(
  String nbPath,
  AiEnrichRequest req, {
  required AiClient? client,
  required String provider,
  required String model,
  Future<void> Function(Duration)? sleep,
}) async {
  if (client == null) {
    return const AiOutcome(reason: 'AI 未配置');
  }
  final budget = RequestBudget();

  // ---- 缓存优先 ----
  final key = aiCacheKey(
      provider: provider, model: model, word: req.word, feature: req.feature);
  final cached = await readAiCache(nbPath, key);
  if (cached != null) {
    if (cached.valid && cached.card != null) {
      return AiOutcome(
        card: cached.card,
        fromCache: true,
        selfProof: req.feature == AiFeature.define
            ? selfProofOf(cached.card!, req.word)
            : null,
      );
    }
    // 不合格条目：不渲染、不自动重试（否则每次查词都再烧一次钱）。
    // 只有用户主动「重新生成」（会先删缓存）才会重来。
    return AiOutcome(
        reason: cached.reason.isEmpty ? '上次生成的结果不合格' : cached.reason,
        partial: false);
  }

  // ---- 请求 → 校验 → 修复重试 ----
  final messages = <Map<String, String>>[
    {'role': 'system', 'content': systemPromptFor(req.feature)},
    {
      'role': 'user',
      'content': userPromptFor(
        req.feature,
        req.word,
        pos: req.expectedPos,
        knownForms: req.knownForms,
        existingTranslation: req.existingTranslation,
      ),
    },
  ];

  AiCompletion? completion;
  AiCard? card;
  AiValidation? validation;
  var repairHint = '';
  SelfProof? proof;

  for (var attempt = 0; attempt < 2; attempt++) {
    if (attempt > 0) {
      // 回灌缺项：把「缺了什么」明确告诉模型，而不是让它从零再来
      messages.add({
        'role': 'user',
        'content': '上一次的输出有以下问题，请修正后重新输出完整 JSON：\n$repairHint',
      });
    }
    try {
      completion = await client.callWithRetry(messages,
          budget: budget, sleep: sleep);
    } on AiError catch (e) {
      // 网络层失败：把已用预算带上，便于观测；缓存不写（避免固化失败）
      return AiOutcome(reason: e.message, requests: budget.used);
    }

    final parsed = parseAiCard(completion.content);
    if (!parsed.ok) {
      validation = const AiValidation([
        AiViolation(AiViolationKind.structure, '返回内容不是可解析的词卡 JSON')
      ]);
      repairHint = validation.repairHint;
      continue;
    }

    // 自证（define）：这不是「模型写坏了」，而是「用户输入有问题」，
    // 重发请求只会让它再编一次，所以**不进修复重试**（design D3 / D4）。
    if (req.feature == AiFeature.define) {
      proof = selfProofOf(parsed.card!, req.word);
      if (proof != SelfProof.known) {
        final reason = proof == SelfProof.notAWord
            ? '这看起来不是英语单词'
            : '拼写可能应为 ${parsed.card!.canonical}';
        await writeAiCache(nbPath,
            provider: provider,
            model: model,
            word: req.word,
            feature: req.feature,
            promptVersion: promptVersion,
            valid: false,
            raw: completion.content,
            reason: reason,
            responseModel: completion.model,
            promptTokens: completion.promptTokens,
            completionTokens: completion.completionTokens,
            cacheHitTokens: completion.cacheHitTokens);
        return AiOutcome(
            reason: reason,
            selfProof: proof,
            requests: budget.used);
      }
    }

    card = truncateExamples(parsed.card!);
    validation = validateAiCard(card,
        feature: req.feature,
        expectedPos: req.expectedPos,
        knownForms: req.knownForms);
    if (validation.ok) break;
    repairHint = validation.repairHint;
    // 预算用尽则不再重试
    if (!budget.hasRemaining) break;
  }

  final ok = validation?.ok == true && card != null;

  // ---- 落缓存（合格与不合格都写，不合格带 reason）----
  if (completion != null) {
    await writeAiCache(nbPath,
        provider: provider,
        model: model,
        word: req.word,
        feature: req.feature,
        promptVersion: promptVersion,
        valid: ok,
        card: ok ? card : null,
        raw: completion.content,
        reason: ok ? '' : (validation?.repairHint ?? ''),
        responseModel: completion.model,
        promptTokens: completion.promptTokens,
        completionTokens: completion.completionTokens,
        cacheHitTokens: completion.cacheHitTokens);
  }

  if (ok) {
    return AiOutcome(
        card: card,
        selfProof: proof,
        requests: budget.used);
  }
  // 降级展示：拿到的部分仍然可用，界面标注缺失（design D4-4）
  return AiOutcome(
    card: card,
    partial: card != null,
    reason: validation?.repairHint ?? '生成失败',
    selfProof: proof,
    requests: budget.used,
  );
}
