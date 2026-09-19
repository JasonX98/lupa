// AI 客户端 —— 手写薄封装，零 pub 依赖。
//
// 选型理由（openspec/changes/add-ai-word-enrichment design D10）：API 面积极小
// （1 个端点、非流式），项目已有两个同构的手写 provider（media/phonetic.dart /
// media/tts.dart），引入 SDK 会造成风格分叉并带进传递依赖；而校验与修复重试是
// 本项目的自有逻辑，任何 SDK 都帮不上。DeepSeek 兼容 OpenAI 协议。
//
// 错误处理与既有 media 层不同：那里「单类型 + message」够用，这里不行 ——
// 不同错误需要**不同行为**（401 不该重试、429 该退避、畸形 JSON 重试无意义），
// 不能靠 message 字符串分叉。所以保留 XxxFetchError 的形状（仍是 implements
// Exception 的类、仍有 message），但把「怎么处理」变成可判定的 kind。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// AI 失败的类别。行为按 kind 判定，文案按 kind 生成。
enum AiErrorKind {
  /// 密钥无效 / 无权限（401 / 403）。不可重试。
  auth,

  /// 限流（429）。可重试，遵守 Retry-After。
  rateLimit,

  /// 网络不可达 / 连接失败 / 断网。可重试。
  network,

  /// 超时。可重试。
  timeout,

  /// 服务端错误（5xx）。可重试。
  server,

  /// 响应不是合法 JSON 或缺少必要结构。不可重试（同样请求大概率同样失败）。
  malformed,

  /// 请求本身有误（4xx 其它）。不可重试。
  badRequest,
}

extension AiErrorKindX on AiErrorKind {
  /// 网络层是否值得重发一次。
  bool get retryable => switch (this) {
        AiErrorKind.rateLimit ||
        AiErrorKind.network ||
        AiErrorKind.timeout ||
        AiErrorKind.server =>
          true,
        _ => false,
      };
}

/// AI 调用失败。
class AiError implements Exception {
  final AiErrorKind kind;
  final String message;

  /// 服务端给出的建议等待时长（Retry-After），仅 rateLimit 可能非空。
  final Duration? retryAfter;

  const AiError(this.kind, this.message, {this.retryAfter});

  @override
  String toString() => 'AiError(${kind.name}): $message';
}

/// 一次调用的结果。
class AiCompletion {
  final String content;

  /// 用量（服务端返回时非空），用于设置页统计与成本观测。
  final int promptTokens;
  final int completionTokens;
  final int cacheHitTokens;
  final String model;
  final String rawBody;

  const AiCompletion({
    required this.content,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cacheHitTokens = 0,
    this.model = '',
    this.rawBody = '',
  });
}

/// 连接参数。
class AiConfig {
  final String baseUrl;
  final String apiKey;
  final String model;
  final Duration timeout;

  const AiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.timeout = const Duration(seconds: 30),
  });
}

/// 退避基准（design D7：固定 2s，Retry-After ≤ 5s 则遵守它）。
const Duration aiRetryBackoff = Duration(seconds: 2);
const Duration aiRetryAfterCap = Duration(seconds: 5);

/// **一次用户触发**允许的总请求上限（design D7：网络重试与校验重试会相乘，必须封顶）。
const int aiMaxRequestsPerTrigger = 3;

/// 客户端。可注入 [send] 以便测试替换传输层（见 test/ai_client_test.dart）。
class AiClient {
  final AiConfig config;
  final HttpClient? _http;
  final Future<AiCompletion> Function(Uri, Map<String, String>, String)? _send;

  AiClient(this.config, {HttpClient? http, Future<AiCompletion> Function(Uri, Map<String, String>, String)? send})
      : _http = http,
        _send = send;

  /// 发送一次对话请求（**不含重试**，重试由 [callWithRetry] 负责）。
  Future<AiCompletion> chatJson(List<Map<String, String>> messages) async {
    final uri = Uri.parse('${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}'
        '/chat/completions');
    final body = json.encode({
      'model': config.model,
      'messages': messages,
      'response_format': {'type': 'json_object'},
      'stream': false,
    });
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${config.apiKey}',
    };
    if (_send != null) return _send(uri, headers, body);

    final client = _http ?? HttpClient();
    try {
      final req = await client.postUrl(uri);
      headers.forEach(req.headers.set);
      req.add(utf8.encode(body));
      final resp = await req.close().timeout(config.timeout);
      final text = await resp.transform(utf8.decoder).join();

      if (resp.statusCode != 200) {
        throw _errorForStatus(resp.statusCode, text, resp.headers);
      }
      return _parseCompletion(text);
    } on AiError {
      rethrow;
    } on TimeoutException catch (e) {
      throw AiError(AiErrorKind.timeout, '请求超时: $e');
    } on SocketException catch (e) {
      throw AiError(AiErrorKind.network, '网络不可达: ${e.message}');
    } on HttpException catch (e) {
      throw AiError(AiErrorKind.network, 'HTTP 异常: ${e.message}');
    } finally {
      if (_http == null) client.close();
    }
  }

  /// 带网络层重试的调用，且**总请求数封顶** [aiMaxRequestsPerTrigger]。
  ///
  /// [budget] 是调用方持有的共享计数器 —— 校验层的修复重试也走它，这样
  /// 「网络重试 1 次 + 校验重试 1 次」不会变成 4 次请求。
  Future<AiCompletion> callWithRetry(
    List<Map<String, String>> messages, {
    required RequestBudget budget,
    Future<void> Function(Duration)? sleep,
  }) async {
    var attempt = 0;
    while (true) {
      attempt++;
      if (!budget.tryConsume()) {
        throw const AiError(AiErrorKind.badRequest, '已达到本次请求上限');
      }
      try {
        return await chatJson(messages);
      } on AiError catch (e) {
        if (!e.kind.retryable || attempt > 1) rethrow;
        if (!budget.hasRemaining) rethrow;
        var wait = aiRetryBackoff;
        final ra = e.retryAfter;
        if (ra != null && ra <= aiRetryAfterCap) wait = ra;
        if (sleep != null) {
          await sleep(wait);
        } else {
          await Future<void>.delayed(wait);
        }
      }
    }
  }

  AiError _errorForStatus(int status, String body, HttpHeaders headers) {
    final snippet = body.length > 200 ? '${body.substring(0, 200)}...' : body;
    if (status == 401 || status == 403) {
      return AiError(AiErrorKind.auth, 'API Key 无效或无权访问（HTTP $status）');
    }
    if (status == 429) {
      return AiError(AiErrorKind.rateLimit, '请求过于频繁（HTTP 429）',
          retryAfter: _parseRetryAfter(headers));
    }
    if (status >= 500) {
      return AiError(AiErrorKind.server, 'AI 服务暂时不可用（HTTP $status）');
    }
    return AiError(AiErrorKind.badRequest, '请求被拒绝（HTTP $status）: $snippet');
  }

  static Duration? _parseRetryAfter(HttpHeaders headers) {
    final v = headers.value('retry-after');
    if (v == null) return null;
    final secs = int.tryParse(v.trim());
    if (secs != null) return Duration(seconds: secs);
    return null;
  }

  AiCompletion _parseCompletion(String body) {
    final Object? decoded;
    try {
      decoded = json.decode(body);
    } catch (e) {
      throw AiError(AiErrorKind.malformed, '响应不是合法 JSON: $e');
    }
    if (decoded is! Map) {
      throw const AiError(AiErrorKind.malformed, '响应顶层不是对象');
    }
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiError(AiErrorKind.malformed, '响应缺少 choices');
    }
    final first = choices.first;
    if (first is! Map) {
      throw const AiError(AiErrorKind.malformed, 'choices[0] 不是对象');
    }
    final msg = first['message'];
    if (msg is! Map) {
      throw const AiError(AiErrorKind.malformed, 'choices[0].message 缺失');
    }
    final content = msg['content'];
    if (content is! String || content.trim().isEmpty) {
      throw const AiError(AiErrorKind.malformed, 'choices[0].message.content 为空');
    }
    final usage = decoded['usage'];
    final u = usage is Map ? usage.cast<String, Object?>() : const <String, Object?>{};
    return AiCompletion(
      content: content,
      promptTokens: _int(u['prompt_tokens']),
      completionTokens: _int(u['completion_tokens']),
      cacheHitTokens: _int(u['prompt_cache_hit_tokens']),
      model: (decoded['model'] as String?) ?? '',
      rawBody: body,
    );
  }

  static int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
}

/// 一次用户触发的请求预算。
///
/// 网络重试与校验重试**共用**它，因此「重试」不会叠加成 4 次请求（design D7）。
class RequestBudget {
  final int limit;
  int _used = 0;

  RequestBudget({this.limit = aiMaxRequestsPerTrigger});

  int get used => _used;
  bool get hasRemaining => _used < limit;

  /// 消耗一次额度；额度耗尽时返回 false（调用方不应再发请求）。
  bool tryConsume() {
    if (_used >= limit) return false;
    _used++;
    return true;
  }
}
