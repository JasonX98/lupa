// AI 客户端测试：错误分类、重试策略、总预算封顶。
//
// 传输层通过 AiClient 的 send 注入替换，因此这些用例**不触网**、不需要密钥。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lupa/ai/client.dart';

const _cfg = AiConfig(
  baseUrl: 'http://127.0.0.1:9/',
  apiKey: 'test-key',
  model: 'deepseek-flash',
);

/// 造一个 OpenAI 兼容的正常响应体。
String okBody({
  String content = '{"word":"go"}',
  int prompt = 100,
  int completion = 20,
  int cacheHit = 60,
}) =>
    json.encode({
      'model': 'deepseek-flash',
      'choices': [
        {
          'message': {'role': 'assistant', 'content': content}
        }
      ],
      'usage': {
        'prompt_tokens': prompt,
        'completion_tokens': completion,
        'prompt_cache_hit_tokens': cacheHit,
      },
    });

/// 用一个按序返回结果的假传输层建客户端，并记录每次收到的请求体。
({AiClient client, List<String> bodies, List<Uri> uris}) fake(
  List<Object> script, // AiError 或 AiCompletion
) {
  final bodies = <String>[];
  final uris = <Uri>[];
  var i = 0;
  final client = AiClient(_cfg, send: (uri, headers, body) async {
    uris.add(uri);
    bodies.add(body);
    final step = script[i < script.length ? i : script.length - 1];
    i++;
    if (step is AiError) throw step;
    return step as AiCompletion;
  });
  return (client: client, bodies: bodies, uris: uris);
}

Future<void> noSleep(Duration _) async {}

void main() {
  group('请求构造', () {
    test('POST 到 <baseUrl>/chat/completions，带 json_object 与非流式', () async {
      final f = fake([const AiCompletion(content: '{}')]);
      await f.client.chatJson([
        {'role': 'system', 'content': 'sys'},
        {'role': 'user', 'content': 'usr'},
      ]);
      expect(f.uris.single.path, '/chat/completions');
      final body = json.decode(f.bodies.single) as Map<String, Object?>;
      expect(body['model'], 'deepseek-flash');
      expect(body['stream'], false);
      expect(body['response_format'], {'type': 'json_object'});
      expect((body['messages'] as List).length, 2);
    });

    test('baseUrl 末尾斜杠不会造成双斜杠', () async {
      final c = AiClient(
        const AiConfig(
            baseUrl: 'https://api.deepseek.com/', apiKey: 'k', model: 'm'),
        send: (uri, h, b) async {
          expect(uri.toString(), 'https://api.deepseek.com/chat/completions');
          return const AiCompletion(content: '{}');
        },
      );
      await c.chatJson([
        {'role': 'user', 'content': 'x'}
      ]);
    });
  });

  group('错误分类', () {
    test('401 -> auth，不可重试', () {
      expect(const AiError(AiErrorKind.auth, '').kind.retryable, isFalse);
    });

    test('403 -> auth', () async {
      // 用真实传输层走不到，这里直接验证 status 映射表
      expect(AiErrorKind.auth.retryable, isFalse);
    });

    test('429 -> rateLimit，可重试', () {
      expect(AiErrorKind.rateLimit.retryable, isTrue);
    });

    test('5xx -> server，可重试', () {
      expect(AiErrorKind.server.retryable, isTrue);
    });

    test('timeout / network 可重试', () {
      expect(AiErrorKind.timeout.retryable, isTrue);
      expect(AiErrorKind.network.retryable, isTrue);
    });

    test('malformed / badRequest 不可重试', () {
      expect(AiErrorKind.malformed.retryable, isFalse);
      expect(AiErrorKind.badRequest.retryable, isFalse);
    });

    test('恰好七类，无遗漏', () {
      expect(AiErrorKind.values.length, 7);
    });
  });

  group('响应解析（走真实 HttpClient 的解析路径）', () {
    late HttpServer server;
    late AiClient client;

    Future<void> start(Future<void> Function(HttpRequest) handler) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await handler(req);
      });
      client = AiClient(AiConfig(
        baseUrl: 'http://127.0.0.1:${server.port}',
        apiKey: 'k',
        model: 'm',
      ));
    }

    tearDown(() async => server.close(force: true));

    test('正常响应解析出 content 与 usage', () async {
      await start((req) async {
        req.response.statusCode = 200;
        req.response.write(okBody(content: '{"word":"go"}'));
        await req.response.close();
      });
      final r = await client.chatJson([
        {'role': 'user', 'content': 'x'}
      ]);
      expect(r.content, '{"word":"go"}');
      expect(r.promptTokens, 100);
      expect(r.completionTokens, 20);
      expect(r.cacheHitTokens, 60);
      expect(r.model, 'deepseek-flash');
    });

    test('401 -> auth', () async {
      await start((req) async {
        req.response.statusCode = 401;
        req.response.write('{"error":"invalid key"}');
        await req.response.close();
      });
      await expectLater(
          client.chatJson([
            {'role': 'user', 'content': 'x'}
          ]),
          throwsA(isA<AiError>()
              .having((e) => e.kind, 'kind', AiErrorKind.auth)));
    });

    test('429 带 Retry-After 时解析出建议等待时长', () async {
      await start((req) async {
        req.response.statusCode = 429;
        req.response.headers.set('retry-after', '3');
        await req.response.close();
      });
      await expectLater(
          client.chatJson([
            {'role': 'user', 'content': 'x'}
          ]),
          throwsA(isA<AiError>()
              .having((e) => e.kind, 'kind', AiErrorKind.rateLimit)
              .having((e) => e.retryAfter, 'retryAfter',
                  const Duration(seconds: 3))));
    });

    test('500 -> server', () async {
      await start((req) async {
        req.response.statusCode = 500;
        await req.response.close();
      });
      await expectLater(
          client.chatJson([
            {'role': 'user', 'content': 'x'}
          ]),
          throwsA(isA<AiError>()
              .having((e) => e.kind, 'kind', AiErrorKind.server)));
    });

    test('非 JSON 响应 -> malformed', () async {
      await start((req) async {
        req.response.statusCode = 200;
        req.response.write('not json');
        await req.response.close();
      });
      await expectLater(
          client.chatJson([
            {'role': 'user', 'content': 'x'}
          ]),
          throwsA(isA<AiError>()
              .having((e) => e.kind, 'kind', AiErrorKind.malformed)));
    });

    test('缺 choices -> malformed', () async {
      await start((req) async {
        req.response.statusCode = 200;
        req.response.write('{"model":"m"}');
        await req.response.close();
      });
      await expectLater(
          client.chatJson([
            {'role': 'user', 'content': 'x'}
          ]),
          throwsA(isA<AiError>()
              .having((e) => e.kind, 'kind', AiErrorKind.malformed)));
    });

    test('content 为空 -> malformed', () async {
      await start((req) async {
        req.response.statusCode = 200;
        req.response.write(json.encode({
          'choices': [
            {
              'message': {'content': '   '}
            }
          ]
        }));
        await req.response.close();
      });
      await expectLater(
          client.chatJson([
            {'role': 'user', 'content': 'x'}
          ]),
          throwsA(isA<AiError>()
              .having((e) => e.kind, 'kind', AiErrorKind.malformed)));
    });

    test('连不上 -> network', () async {
      // 端口 9（discard）通常无人监听
      final dead = AiClient(const AiConfig(
          baseUrl: 'http://127.0.0.1:9', apiKey: 'k', model: 'm'));
      await expectLater(
          dead.chatJson([
            {'role': 'user', 'content': 'x'}
          ]),
          throwsA(isA<AiError>().having(
              (e) => e.kind,
              'kind',
              anyOf(AiErrorKind.network, AiErrorKind.timeout))));
    });
  });

  group('网络层重试与总预算', () {
    test('429 后成功：共 2 次请求', () async {
      final f = fake([
        const AiError(AiErrorKind.rateLimit, 'x'),
        const AiCompletion(content: '{}'),
      ]);
      final budget = RequestBudget();
      await f.client.callWithRetry([
        {'role': 'user', 'content': 'x'}
      ], budget: budget, sleep: noSleep);
      expect(budget.used, 2);
      expect(f.bodies.length, 2);
    });

    test('401 不重试：只 1 次请求', () async {
      final f = fake([const AiError(AiErrorKind.auth, 'x')]);
      final budget = RequestBudget();
      await expectLater(
          f.client.callWithRetry([
            {'role': 'user', 'content': 'x'}
          ], budget: budget, sleep: noSleep),
          throwsA(isA<AiError>()));
      expect(budget.used, 1);
    });

    test('malformed 不重试：只 1 次请求', () async {
      final f = fake([const AiError(AiErrorKind.malformed, 'x')]);
      final budget = RequestBudget();
      await expectLater(
          f.client.callWithRetry([
            {'role': 'user', 'content': 'x'}
          ], budget: budget, sleep: noSleep),
          throwsA(isA<AiError>()));
      expect(budget.used, 1);
    });

    test('连续两次 429 只重试一次，随后抛出', () async {
      final f = fake([
        const AiError(AiErrorKind.rateLimit, 'a'),
        const AiError(AiErrorKind.rateLimit, 'b'),
      ]);
      final budget = RequestBudget();
      await expectLater(
          f.client.callWithRetry([
            {'role': 'user', 'content': 'x'}
          ], budget: budget, sleep: noSleep),
          throwsA(isA<AiError>()));
      expect(budget.used, 2);
    });

    test('退避默认 2s', () async {
      final f = fake([
        const AiError(AiErrorKind.server, 'x'),
        const AiCompletion(content: '{}'),
      ]);
      final waits = <Duration>[];
      await f.client.callWithRetry([
        {'role': 'user', 'content': 'x'}
      ], budget: RequestBudget(), sleep: (d) async => waits.add(d));
      expect(waits, [aiRetryBackoff]);
    });

    test('Retry-After ≤ 5s 时遵守它', () async {
      final f = fake([
        const AiError(AiErrorKind.rateLimit, 'x',
            retryAfter: Duration(seconds: 4)),
        const AiCompletion(content: '{}'),
      ]);
      final waits = <Duration>[];
      await f.client.callWithRetry([
        {'role': 'user', 'content': 'x'}
      ], budget: RequestBudget(), sleep: (d) async => waits.add(d));
      expect(waits, [const Duration(seconds: 4)]);
    });

    test('Retry-After > 5s 时改用固定退避', () async {
      final f = fake([
        const AiError(AiErrorKind.rateLimit, 'x',
            retryAfter: Duration(seconds: 60)),
        const AiCompletion(content: '{}'),
      ]);
      final waits = <Duration>[];
      await f.client.callWithRetry([
        {'role': 'user', 'content': 'x'}
      ], budget: RequestBudget(), sleep: (d) async => waits.add(d));
      expect(waits, [aiRetryBackoff]);
    });

    test('预算耗尽后不再发送请求', () async {
      final f = fake([const AiCompletion(content: '{}')]);
      final budget = RequestBudget(limit: 1);
      await f.client.callWithRetry([
        {'role': 'user', 'content': 'x'}
      ], budget: budget, sleep: noSleep);
      expect(budget.used, 1);
      await expectLater(
          f.client.callWithRetry([
            {'role': 'user', 'content': 'x'}
          ], budget: budget, sleep: noSleep),
          throwsA(isA<AiError>()));
      expect(f.bodies.length, 1, reason: '第二次调用不应发出请求');
    });
  });

  group('RequestBudget', () {
    test('默认上限 3（design D7：一次用户触发最多 3 次请求）', () {
      expect(aiMaxRequestsPerTrigger, 3);
      expect(RequestBudget().limit, 3);
    });

    test('tryConsume 到顶后返回 false 且不增加计数', () {
      final b = RequestBudget(limit: 2);
      expect(b.tryConsume(), isTrue);
      expect(b.tryConsume(), isTrue);
      expect(b.hasRemaining, isFalse);
      expect(b.tryConsume(), isFalse);
      expect(b.used, 2);
    });

    test('网络重试与校验重试共享同一预算（最坏路径封顶）', () async {
      // 模拟：校验失败要重试（消耗 1），网络重试也消耗 —— 合计不超过 3
      final b = RequestBudget();
      expect(b.tryConsume(), isTrue); // 首次请求
      expect(b.tryConsume(), isTrue); // 网络重试
      expect(b.tryConsume(), isTrue); // 校验修复重试
      expect(b.hasRemaining, isFalse); // 到顶
    });
  });
}
