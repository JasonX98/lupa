// AI 链路验证 —— 默认走本地 stub HttpServer，**全程不触网、不需要密钥**。
//
// 为什么必须有 stub（design D8）：AI 验证不能要求每次都掏一个付费密钥。而
// stub 与 live 测的东西**根本不重叠** —— stub 测代码路径、重试次数、降级行为、
// 落库形状、导出拼接（可重复、可进 CI）；live 测提示词到底能不能让真实模型产出
// 符合 schema 的内容（stub 只会返回我们写死的「正确答案」，等于自己给自己出题）。
// 所以两者都要有，但默认走 stub。
//
// 注入方式全部现成：HttpServer.bind(loopback, 0) 取随机端口 + setConfigHomeOverride
// 把 config 指到临时目录（loadConfig 是深合并，只需写 providers.deepseek.base_url
// 一个键）+ dart:io HttpClient 默认 findProxy 为 DIRECT，localhost 直连不受代理影响。
//
// 用法:
//   LUPA_HOME=<真实数据目录> dart run tool/verify_ai.dart          # stub（默认）
//   dart run tool/verify_ai.dart --live <api-key> [model]          # 真实 API
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lupa/ai/card.dart';
import 'package:lupa/ai/client.dart';
import 'package:lupa/ai/enrich.dart';
import 'package:lupa/ai/pos.dart';
import 'package:lupa/ai/repo.dart';
import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/dict/query.dart';
import 'package:lupa/dict/lemma.dart';
import 'package:lupa/notebook/repo.dart';

int _pass = 0;
int _fail = 0;

/// Set 在 Dart 里没有值相等语义（`{'a'} == {'a'}` 恒为 false），
/// 断言集合相等必须显式比较，否则测试会「永远失败」而看不出原因。
bool sameSet(Iterable<String> a, Iterable<String> b) {
  final x = a.toSet(), y = b.toSet();
  return x.length == y.length && x.every(y.contains);
}

void check(String name, bool cond, [Object? detail]) {
  if (cond) {
    _pass++;
    stdout.writeln('PASS  $name');
  } else {
    _fail++;
    stdout.writeln('FAIL  $name${detail == null ? '' : '  ($detail)'}');
  }
}

/// stub 的一次响应脚本。
class StubStep {
  final int status;
  final String body;
  final Map<String, String> headers;
  const StubStep(this.status, this.body, {this.headers = const {}});

  static StubStep ok(String content, {int prompt = 100, int completion = 20, int cacheHit = 60}) =>
      StubStep(
          200,
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
          }));
}

/// 本地 stub：按第 N 次请求返回不同剧本，并记录收到的请求体。
class Stub {
  final HttpServer _server;
  final List<StubStep> _script;
  final List<String> requests = [];
  int _i = 0;

  Stub._(this._server, this._script);

  static Future<Stub> start(List<StubStep> script) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final stub = Stub._(server, script);
    server.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      stub.requests.add(body);
      final step = script[stub._i < script.length ? stub._i : script.length - 1];
      stub._i++;
      step.headers.forEach((k, v) => req.response.headers.set(k, v));
      req.response.statusCode = step.status;
      req.response.write(step.body);
      await req.response.close();
    });
    return stub;
  }

  int get port => _server.port;
  String get baseUrl => 'http://127.0.0.1:$port';
  int get requestCount => requests.length;
  Future<void> stop() => _server.close(force: true);
}

/// 造一个合法的 full 补齐返回体（例句都用原形，避免撞 L5）。
String fullCard({String word = 'record', List<String> pos = const ['n.', 'vt.']}) {
  final senses = pos
      .map((p) => {
            'pos': p,
            'gloss': '释义$p',
            'examples': [
              {'en': 'They $word it every day.', 'zh': '他们每天$word它。'}
            ]
          })
      .toList();
  return json.encode({
    'word': word,
    'canonical': word,
    'is_known_word': true,
    'senses': senses,
    'collocations': [
      {
        'phrase': '$word a video',
        'gloss': '录制视频',
        'examples': [
          {'en': 'We $word a video weekly.', 'zh': '我们每周录一段视频。'}
        ]
      }
    ],
  });
}

Future<void> main(List<String> args) async {
  final liveIdx = args.indexOf('--live');
  if (liveIdx >= 0) {
    await _runLive(args.sublist(liveIdx + 1));
    return;
  }
  await _runStub();
}

// ============================ stub 模式 ============================

Future<void> _runStub() async {
  stdout.writeln('== Lupa AI 链路验证（本地 stub，不触网）==');
  final dictDb = dictDbPath();
  if (!File(dictDb).existsSync()) {
    stdout.writeln('词库不存在，先构建词库: $dictDb');
    exitCode = 1;
    return;
  }

  // 先记下真实词库路径：setDataHomeOverride 会把 dictDbPath() 指到临时目录，
  // 而词性解析与词形还原的全量回归必须跑在**真实 3 万词库**上。
  final realDictHome = Directory(p.dirname(dictDb));

  final cfgHome = await Directory.systemTemp.createTemp('lupa_ai_cfg_');
  final dataHome = await Directory.systemTemp.createTemp('lupa_ai_data_');
  setConfigHomeOverride(cfgHome.path);
  setDataHomeOverride(dataHome.path);

  final nb = p.join(dataHome.path, 'notebook.sqlite');
  await ensureNotebookDb(nb);

  const provider = 'deepseek';
  const model = 'deepseek-flash';

  // ---------- 剧本 1：正常返回 + 缓存键与信封 ----------
  {
    final stub = await Stub.start([StubStep.ok(fullCard())]);
    final outcome = await enrich(
      nb,
      const AiEnrichRequest(
        word: 'record',
        feature: AiFeature.enrich,
        expectedPos: ['n.', 'vt.'],
      ),
      client: _client(stub, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    check('1 正常返回 ok', outcome.ok, outcome.reason);
    check('1 词性组齐全', sameSet(outcome.card!.senseLabels, ['n.', 'vt.']),
        outcome.card!.senseLabels);
    check('1 搭配带例句', outcome.card!.collocations.single.examples.isNotEmpty);
    check('1 只发 1 次请求', stub.requestCount == 1, stub.requestCount);

    final key = aiCacheKey(
        provider: provider, model: model, word: 'record', feature: AiFeature.enrich);
    check('1 三段式键格式', key == 'deepseek/deepseek-flash:record:enrich', key);

    final con = await databaseFactory.openDatabase(nb,
        options: OpenDatabaseOptions(singleInstance: false));
    final row = (await con.rawQuery(
            'SELECT cache_key, provider, feature, prompt_version, payload, '
            'model, prompt_tokens, completion_tokens, cache_hit_tokens '
            'FROM ai_cache WHERE cache_key = ?',
            [key]))
        .first;
    await con.close();
    check('1 provider 段含模型', row['provider'] == 'deepseek/deepseek-flash');
    check('1 feature 段 = enrich', row['feature'] == 'enrich');
    check('1 prompt_version 落库', row['prompt_version'] == 1);
    check('1 model 列为真列', row['model'] == 'deepseek-flash');
    check('1 token 用量落真列',
        row['prompt_tokens'] == 100 &&
            row['completion_tokens'] == 20 &&
            row['cache_hit_tokens'] == 60,
        '${row['prompt_tokens']}/${row['completion_tokens']}/${row['cache_hit_tokens']}');
    final env = json.decode(row['payload'] as String) as Map<String, Object?>;
    check('1 信封含 valid/card/raw/model/usage',
        env.containsKey('valid') &&
            env.containsKey('card') &&
            env.containsKey('raw') &&
            env.containsKey('model') &&
            env.containsKey('usage'),
        env.keys.join(','));
    check('1 信封 valid=true', env['valid'] == true);
    await stub.stop();
  }

  // ---------- 剧本 2：缓存命中不重复请求，hit_count 递增 ----------
  {
    final stub = await Stub.start([StubStep.ok(fullCard())]);
    final outcome = await enrich(
      nb,
      const AiEnrichRequest(
          word: 'record', feature: AiFeature.enrich, expectedPos: ['n.', 'vt.']),
      client: _client(stub, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    check('2 第二次走缓存', outcome.fromCache);
    check('2 缓存命中零请求', stub.requestCount == 0, stub.requestCount);
    final con = await databaseFactory.openDatabase(nb,
        options: OpenDatabaseOptions(singleInstance: false));
    final hits = (await con.rawQuery(
            'SELECT hit_count FROM ai_cache WHERE word = ?', ['record']))
        .first['hit_count'];
    await con.close();
    check('2 hit_count 递增', (hits as int) >= 1, hits);
    await stub.stop();
  }

  // ---------- 剧本 3：enrich-plain 降级补齐（不分组） ----------
  {
    final plain = json.encode({
      'word': 'online',
      'canonical': 'online',
      'is_known_word': true,
      'examples': [
        {'en': 'She is online now.', 'zh': '她现在在线。'}
      ],
      'collocations': [
        {
          'phrase': 'go online',
          'gloss': '上线',
          'examples': [
            {'en': 'We go online at nine.', 'zh': '我们九点上线。'}
          ]
        }
      ],
    });
    final stub = await Stub.start([StubStep.ok(plain)]);
    final outcome = await enrich(
      nb,
      const AiEnrichRequest(word: 'online', feature: AiFeature.enrichPlain),
      client: _client(stub, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    check('3 降级补齐 ok', outcome.ok, outcome.reason);
    check('3 降级内容不分词性组', outcome.card!.senses.isEmpty);
    check('3 降级有通用例句', outcome.card!.examples.isNotEmpty);
    final key = aiCacheKey(
        provider: provider, model: model, word: 'online',
        feature: AiFeature.enrichPlain);
    check('3 用独立 feature 段',
        key == 'deepseek/deepseek-flash:online:enrich-plain', key);
    await stub.stop();
  }

  // ---------- 剧本 4：define 整卡落库 ----------
  {
    final define = json.encode({
      'word': 'serendipity',
      'canonical': 'serendipity',
      'is_known_word': true,
      'phonetic': 'ˌserənˈdɪpəti',
      'translation': 'n. 意外发现珍奇事物的运气',
      'definition': 'the occurrence of happy accidents',
      'pos': ['n.'],
      'senses': [
        {
          'pos': 'n.',
          'gloss': '运气',
          'examples': [
            {'en': 'It was pure serendipity.', 'zh': '纯属意外之喜。'}
          ]
        }
      ],
      'collocations': [],
    });
    final stub = await Stub.start([StubStep.ok(define)]);
    final outcome = await enrich(
      nb,
      const AiEnrichRequest(word: 'serendipity', feature: AiFeature.define),
      client: _client(stub, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    check('4 整卡 ok', outcome.ok, outcome.reason);
    check('4 整卡带音标与释义',
        outcome.card!.phonetic.isNotEmpty && outcome.card!.translation.isNotEmpty);
    check('4 自证通过', outcome.selfProof == SelfProof.known);
    await stub.stop();
  }

  // ---------- 剧本 5：L2 缺词性触发修复重试，回灌含缺项 ----------
  {
    // 必须用**未被其他剧本缓存过的词**：否则会命中缓存，0 次请求，测不到重试。
    final stub = await Stub.start([
      StubStep.ok(fullCard(word: 'retrycase', pos: ['n.'])), // 缺 vt.
      StubStep.ok(fullCard(word: 'retrycase', pos: ['n.', 'vt.'])),
    ]);
    final outcome = await enrich(
      nb,
      const AiEnrichRequest(
        word: 'retrycase',
        feature: AiFeature.enrich,
        expectedPos: ['n.', 'vt.'],
      ),
      client: _client(stub, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    // 注意：record 已在剧本 1 落过缓存，这里要先清掉才能测重试
    check('5 触发修复重试（2 次请求）', stub.requestCount == 2, stub.requestCount);
    check('5 回灌体含缺失词性',
        stub.requests.length >= 2 && stub.requests[1].contains('vt.'),
        stub.requests.length >= 2 ? stub.requests[1].substring(0, 80) : '-');
    check('5 重试后通过', outcome.ok, outcome.reason);
    await stub.stop();
  }

  // ---------- 剧本 6：两次都缺 -> 降级 + invalid 缓存 ----------
  {
    final w = 'degradecase';
    final stub = await Stub.start([
      StubStep.ok(fullCard(word: w, pos: ['n.'])),
      StubStep.ok(fullCard(word: w, pos: ['n.'])),
    ]);
    final outcome = await enrich(
      nb,
      AiEnrichRequest(
        word: w,
        feature: AiFeature.enrich,
        expectedPos: ['n.', 'vt.'],
      ),
      client: _client(stub, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    check('6 降级展示部分内容', outcome.partial && outcome.card != null,
        'partial=${outcome.partial}');
    check('6 带缺失说明', outcome.reason.contains('vt.'), outcome.reason);

    // 再查一次：不应自动重试、不应渲染
    final stub2 = await Stub.start([StubStep.ok(fullCard(word: w, pos: ['n.', 'vt.']))]);
    final again = await enrich(
      nb,
      AiEnrichRequest(
          word: w, feature: AiFeature.enrich, expectedPos: ['n.', 'vt.']),
      client: _client(stub2, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    check('6 不合格缓存不自动重试', stub2.requestCount == 0, stub2.requestCount);
    check('6 不合格缓存不渲染', again.card == null);
    await stub2.stop();
    await stub.stop();
  }

  // ---------- 剧本 7：L5 例句不含该词 ----------
  {
    final bad = json.encode({
      'word': 'abandon',
      'canonical': 'abandon',
      'is_known_word': true,
      'senses': [
        {
          'pos': 'v.',
          'gloss': '放弃',
          'examples': [
            {'en': 'She gave up her old habits.', 'zh': '她放弃了旧习惯。'}
          ]
        }
      ],
      'collocations': [],
    });
    final stub = await Stub.start([StubStep.ok(bad), StubStep.ok(bad)]);
    final outcome = await enrich(
      nb,
      const AiEnrichRequest(
        word: 'abandon',
        feature: AiFeature.enrich,
        expectedPos: ['v.'],
      ),
      client: _client(stub, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    check('7 例句不含该词被判失败并重试', stub.requestCount == 2, stub.requestCount);
    check('7 提示缺例句', outcome.reason.contains('不含'), outcome.reason);
    await stub.stop();
  }

  // ---------- 剧本 8：is_known_word=false -> 不展示卡片 ----------
  {
    final stub = await Stub.start([
      StubStep.ok(json.encode({'word': 'serendipty', 'is_known_word': false})),
    ]);
    final outcome = await enrich(
      nb,
      const AiEnrichRequest(word: 'serendipty', feature: AiFeature.define),
      client: _client(stub, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    check('8 不展示词卡', outcome.card == null);
    check('8 自证为 notAWord', outcome.selfProof == SelfProof.notAWord);
    check('8 提示不是英语单词', outcome.reason.contains('不是英语单词'), outcome.reason);
    check('8 不触发修复重试（只 1 次请求）', stub.requestCount == 1, stub.requestCount);
    await stub.stop();
  }

  // ---------- 剧本 9：canonical 不一致 -> 提示标准拼写 ----------
  {
    final stub = await Stub.start([
      StubStep.ok(json.encode({
        'word': 'serendipity',
        'canonical': 'serendipity',
        'is_known_word': true,
        'translation': 'n. 运气',
        'senses': [
          {
            'pos': 'n.',
            'gloss': '运气',
            'examples': [
              {'en': 'pure serendipity', 'zh': '纯属意外'}
            ]
          }
        ],
      })),
    ]);
    // 换独立词：剧本 8 已为 'serendipty' 写过 valid=false 缓存，
    // 复用会直接命中那条缓存（返回剧本 8 的结论），测不到自证分支。
    final outcome = await enrich(
      nb,
      const AiEnrichRequest(word: 'serendipitee', feature: AiFeature.define),
      client: _client(stub, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    check('9 自证为 misspelled', outcome.selfProof == SelfProof.misspelled);
    check('9 提示标准拼写', outcome.reason.contains('serendipity'), outcome.reason);
    check('9 不展示词卡（不按错误拼写保存）', outcome.card == null);
    await stub.stop();
  }

  // ---------- 剧本 10：429 重试 ----------
  {
    final stub = await Stub.start([
      const StubStep(429, '{"error":"rate limited"}',
          headers: {'retry-after': '1'}),
      StubStep.ok(fullCard(word: 'ratelimit')),
    ]);
    final outcome = await enrich(
      nb,
      const AiEnrichRequest(
          word: 'ratelimit', feature: AiFeature.enrich, expectedPos: ['n.', 'vt.']),
      client: _client(stub, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    check('10 429 后重试成功', outcome.ok, outcome.reason);
    check('10 共 2 次请求', stub.requestCount == 2, stub.requestCount);
    await stub.stop();
  }

  // ---------- 剧本 11：401 不重试 ----------
  {
    final stub = await Stub.start([const StubStep(401, '{"error":"bad key"}')]);
    final outcome = await enrich(
      nb,
      const AiEnrichRequest(
          word: 'autherr', feature: AiFeature.enrich, expectedPos: ['n.']),
      client: _client(stub, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    check('11 401 只 1 次请求（不重试）', stub.requestCount == 1, stub.requestCount);
    check('11 报鉴权失败', outcome.reason.contains('API Key'), outcome.reason);
    await stub.stop();
  }

  // ---------- 剧本 12：畸形 JSON 不进缓存 ----------
  {
    final stub = await Stub.start([
      StubStep.ok('this is not json'),
      StubStep.ok('still not json'),
    ]);
    final outcome = await enrich(
      nb,
      const AiEnrichRequest(
          word: 'malformedx', feature: AiFeature.enrich, expectedPos: ['n.']),
      client: _client(stub, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    check('12 畸形 JSON 报失败', !outcome.ok);
    final con = await databaseFactory.openDatabase(nb,
        options: OpenDatabaseOptions(singleInstance: false));
    final rows = await con.rawQuery(
        'SELECT payload FROM ai_cache WHERE word = ?', ['malformedx']);
    await con.close();
    // 写入了（带 valid=false）但绝不带 card
    final hasCard = rows.any((r) =>
        (r['payload'] as String).contains('"card":{'));
    check('12 不把畸形结果当可用卡', !hasCard);
    await stub.stop();
  }

  // ---------- 剧本 13：词性解析器全量回归（真实词库 3 万词）----------
  {
    final db = await openDict(realDictHome);
    try {
      final rows = await db.rawQuery('SELECT word, translation FROM dict');
      var full = 0, degraded = 0, none = 0;
      final outsideWhitelist = <String>{};
      final tokenRe = RegExp(r'^([A-Za-z]{1,6})\.');
      for (final r in rows) {
        final w = r['word'] as String;
        final t = (r['translation'] as String?) ?? '';
        switch (enrichMode(w, t)) {
          case EnrichMode.full:
            full++;
          case EnrichMode.degraded:
            degraded++;
          case EnrichMode.none:
            none++;
        }
        for (final line in t.split('\n')) {
          final m = tokenRe.firstMatch(line.trim());
          if (m != null && !posWhitelist.contains('${m.group(1)!}.')) {
            outsideWhitelist.add('${m.group(1)!}.');
          }
        }
      }
      check('13 全量 30000 词', rows.length == 30000, rows.length);
      check('13 full 28492', full == 28492, full);
      check('13 degraded 1417', degraded == 1417, degraded);
      check('13 none 91', none == 91, none);
      check('13 三类合计等于总数', full + degraded + none == rows.length);
      // 白名单外的 token 只允许是已知的数据瑕疵 na.
      check('13 白名单外只有 na.（数据瑕疵）',
          outsideWhitelist.every((t) => t == 'na.'), outsideWhitelist);
    } finally {
      await db.close();
    }
  }

  // ---------- 剧本 14：本地词形还原（真实词库）----------
  {
    final db = await openDict(realDictHome);
    try {
      for (final (form, lemma) in [
        ('went', 'go'),
        ('children', 'child'),
        ('bought', 'buy'),
        ('took', 'take'),
        ('mice', 'mouse'),
        ('ran', 'run'),
      ]) {
        final hit = await lookupLemma(db, form);
        check('14 $form -> $lemma', hit?.lemma == lemma, hit?.lemma);
      }
      check('14 better 精确命中不报还原', await lookupLemma(db, 'better') == null);
      check('14 派生词还原不了（超出 exchange 覆盖）',
          await lookupLemma(db, 'serendipitously') == null);
    } finally {
      await db.close();
    }
  }

  // ---------- 剧本 15：落库（addAiWord / addWord + 旁表 + provenance + 级联）----------
  {
    // 16a: AI 整卡入库
    final stub = await Stub.start([
      StubStep.ok(json.encode({
        'word': 'limerence',
        'canonical': 'limerence',
        'is_known_word': true,
        'phonetic': 'ˈlɪmərəns',
        'translation': 'n. 痴恋',
        'definition': 'the state of being infatuated',
        'pos': ['n.'],
        'senses': [
          {
            'pos': 'n.',
            'gloss': '痴恋',
            'examples': [
              {'en': 'He was in limerence.', 'zh': '他陷入痴恋。'}
            ]
          }
        ],
        'collocations': [
          {
            'phrase': 'pure limerence',
            'gloss': '纯粹痴恋',
            'examples': [
              {'en': 'It was pure limerence.', 'zh': '纯属痴恋。'}
            ]
          }
        ],
      })),
    ]);
    final o = await enrich(
      nb,
      const AiEnrichRequest(word: 'limerence', feature: AiFeature.define),
      client: _client(stub, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    await stub.stop();
    check('16a 整卡生成 ok', o.ok, o.reason);

    final noteId = await addAiWord(nb, 'limerence', o.card!, 'ai',
        provider: 'deepseek/$model', promptVersion: 1);
    check('16a addAiWord 返回 noteId', noteId > 0, noteId);

    final con = await databaseFactory.openDatabase(nb,
        options: OpenDatabaseOptions(singleInstance: false));
    final note = (await con.rawQuery(
            'SELECT flds, sfld, data FROM notes WHERE id = ?', [noteId]))
        .first;
    final groups = await con.rawQuery(
        'SELECT kind, ordinal, label, gloss FROM word_ai_groups '
        'WHERE note_id = ? ORDER BY kind, ordinal',
        [noteId]);
    final exCount = (await con.rawQuery(
            'SELECT COUNT(*) c FROM word_ai_examples e JOIN word_ai_groups g '
            'ON g.id = e.group_id WHERE g.note_id = ?',
            [noteId]))
        .first['c'] as int;
    await con.close();

    // flds 仍是 5 段（例句走旁表，未扩展 flds）
    check('16a flds 仍为 5 段',
        (note['flds'] as String).split('\x1f').length == 5,
        (note['flds'] as String).split('\x1f').length);
    check('16a 旁表落库两组（sense + collocation）',
        groups.length == 2, groups.length);
    check('16a 旁表例句落库', exCount == 2, exCount);
    check('16a sense 组的 label 是词性',
        groups.any((g) => g['kind'] == 'sense' && g['label'] == 'n.'),
        groups.map((g) => '${g['kind']}:${g['label']}').join(','));
    check('16a collocation 组的 label 是搭配',
        groups.any((g) =>
            g['kind'] == 'collocation' && g['label'] == 'pure limerence'));
    check('16a notes.data 含来源 ai',
        (note['data'] as String).contains('"source":"ai"'), note['data']);

    // 16b: 读回时按词性分组
    final entries = await listWords(nb, limit: 100);
    final lim = entries.firstWhere((e) => e.word == 'limerence');
    check('16b 读回含 AI 组', lim.hasAi && lim.aiGroups.length == 2);
    check('16b aiSenses 只含词性组',
        lim.aiSenses.length == 1 && lim.aiSenses.single.label == 'n.');
    check('16b aiCollocations 只含搭配组',
        lim.aiCollocations.length == 1 &&
            lim.aiCollocations.single.label == 'pure limerence');
    check('16b 例句顺序与内容保持',
        lim.aiSenses.single.examples.single.en == 'He was in limerence.',
        lim.aiSenses.single.examples.single.en);
    check('16b 来源标记为 ai', lim.source == NoteSource.ai, lim.source);

    // 16c: 词库词来源标记为 dict
    await addWord(nb, dictDb, 'abandon', 'w');
    final e2 = (await listWords(nb, limit: 100))
        .firstWhere((e) => e.word.toLowerCase() == 'abandon');
    check('16c 词库词来源为 dict', e2.source == NoteSource.dict, e2.source);
    check('16c 词库词无 AI 组', !e2.hasAi);

    // 16d: 重新生成会替换旁表而非追加
    await replaceAiGroups(nb, noteId, o.card!, provider: 'deepseek/$model', promptVersion: 1);
    final con2 = await databaseFactory.openDatabase(nb,
        options: OpenDatabaseOptions(singleInstance: false));
    final g2 = (await con2.rawQuery(
            'SELECT COUNT(*) c FROM word_ai_groups WHERE note_id = ?',
            [noteId]))
        .first['c'] as int;
    await con2.close();
    check('16d 替换不追加（仍为 2 组）', g2 == 2, g2);

    // 16e: 删笔记级联清旁表（_openNb 已开 PRAGMA foreign_keys）
    await removeWord(nb, 'limerence');
    final con3 = await databaseFactory.openDatabase(nb,
        options: OpenDatabaseOptions(singleInstance: false));
    final leftG = (await con3.rawQuery(
            'SELECT COUNT(*) c FROM word_ai_groups WHERE note_id = ?', [noteId]))
        .first['c'] as int;
    final leftE = (await con3.rawQuery(
            'SELECT COUNT(*) c FROM word_ai_examples e LEFT JOIN word_ai_groups g '
            'ON g.id = e.group_id WHERE g.id IS NULL'))
        .first['c'] as int;
    await con3.close();
    check('16e 删笔记后无残留组', leftG == 0, leftG);
    check('16e 无孤儿例句', leftE == 0, leftE);
  }

  // ---------- 剧本 17：清理 AI 缓存不影响已保存的例句 ----------
  {
    final stub = await Stub.start([StubStep.ok(fullCard(word: 'cleanup'))]);
    await enrich(
      nb,
      const AiEnrichRequest(
          word: 'cleanup', feature: AiFeature.enrich, expectedPos: ['n.', 'vt.']),
      client: _client(stub, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    await stub.stop();
    final before = await aiCacheStats(nb);
    check('17 清理前有缓存', before.count > 0, before.count);
    final removed = await clearAiCache(nb);
    final after = await aiCacheStats(nb);
    check('17 清理后归零', after.count == 0 && removed > 0, '$removed/$after');

    // 已保存的例句必须在（清缓存不是删用户数据）
    final stub2 = await Stub.start([StubStep.ok(fullCard(word: 'keepme'))]);
    final o2 = await enrich(
      nb,
      const AiEnrichRequest(
          word: 'keepme', feature: AiFeature.enrich, expectedPos: ['n.', 'vt.']),
      client: _client(stub2, model),
      provider: provider,
      model: model,
      sleep: _noSleep,
    );
    await stub2.stop();
    final nid = await addAiWord(nb, 'keepme', o2.card!, '',
        provider: 'deepseek/$model', promptVersion: 1);
    await clearAiCache(nb);
    final kept = (await listWords(nb, limit: 100))
        .firstWhere((e) => e.word == 'keepme');
    check('17 清缓存后已保存例句仍在',
        kept.hasAi && kept.aiSenses.isNotEmpty, kept.aiGroups.length);
    await removeWord(nb, 'keepme');
    check('17 noteId 已落库', nid > 0);
  }

  clearConfigHomeOverride();
  clearDataHomeOverride();
  await cfgHome.delete(recursive: true);
  await dataHome.delete(recursive: true);

  stdout.writeln('');
  stdout.writeln('PASS $_pass / FAIL $_fail');
  if (_fail > 0) exitCode = 1;
}

AiClient _client(Stub stub, String model) => AiClient(AiConfig(
      baseUrl: stub.baseUrl,
      apiKey: 'stub-key',
      model: model,
    ));

Future<void> _noSleep(Duration _) async {}

// ============================ live 模式 ============================

/// 真实 API 模式（design D8）：stub 测不出提示词质量，这一模式专门测它。
///
/// 输出四项指标：L2 覆盖率、L5 通过率、平均请求次数、前缀缓存命中率。
Future<void> _runLive(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('用法: dart run tool/verify_ai.dart --live <api-key> [model]');
    exitCode = 1;
    return;
  }
  final key = args[0];
  final model = args.length > 1 ? args[1] : 'deepseek-flash';
  stdout.writeln('== Lupa AI live 验证（真实 API，model=$model）==');

  // 与 stub 模式同理：先记下真实词库路径。setDataHomeOverride 会把
  // dictDbPath() 也指到临时目录，而 live 模式需要真实词库的释义与词形。
  final realDictHome = Directory(p.dirname(dictDbPath()));
  final dataHome = await Directory.systemTemp.createTemp('lupa_ai_live_');
  setDataHomeOverride(dataHome.path);
  final nb = p.join(dataHome.path, 'notebook.sqlite');
  await ensureNotebookDb(nb);

  // 覆盖四个分支：多词性 full 补齐 / 降级补齐 / 真未收录的整卡 / 拼写错误自证。
  // 注意 define 用例必须是**词库里真的没有**的词 —— `serendipity` 在词库里
  // （translation 有 'n.' 前缀），拿它当 define 用例测不到未命中路径。
  final words = <(String, AiFeature, List<String>)>[
    ('record', AiFeature.enrich, ['n.', 'vt.', 'vi.', 'a.']),
    ('present', AiFeature.enrich, ['n.', 'a.', 'vt.', 'vi.']),
    ('abandon', AiFeature.enrich, ['vt.', 'n.']),
    ('serene', AiFeature.enrich, ['a.', 'n.']),
    ('go', AiFeature.enrich, ['i.', 'p.', 'd.', '3.', 's.']),
    ('online', AiFeature.enrichPlain, []),
    ('limerence', AiFeature.define, []), // 未收录
    ('recieve', AiFeature.define, []), // 拼写错误：应提示 canonical=receive
  ];

  var l2Pass = 0, l2Total = 0, l5Pass = 0, l5Total = 0, requests = 0;
  var cacheHit = 0, promptTokens = 0;

  final db = await openDict(realDictHome);
  try {
    for (final (word, feature, pos) in words) {
      final rows = await db
          .rawQuery('SELECT translation, exchange FROM dict WHERE word = ?', [word]);
      final translation = rows.isEmpty ? '' : (rows.first['translation'] as String);
      final knownForms = rows.isEmpty
          ? <String>[]
          : parseExchange((rows.first['exchange'] as String?) ?? '').keys.toList();
      final outcome = await enrich(
        nb,
        AiEnrichRequest(
          word: word,
          feature: feature,
          expectedPos: pos,
          knownForms: knownForms,
          existingTranslation: translation,
        ),
        client: AiClient(
            AiConfig(baseUrl: 'https://api.deepseek.com', apiKey: key, model: model)),
        provider: 'deepseek',
        model: model,
      );
      requests += outcome.requests;

      if (feature == AiFeature.enrich && pos.isNotEmpty) {
        l2Total++;
        final got = outcome.card?.senseLabels ?? const <String>{};
        final covered = pos.every(got.contains);
        if (covered) l2Pass++;
        stdout.writeln('  $word: L2 ${covered ? "PASS" : "MISS ${pos.where((x) => !got.contains(x)).toList()}"}'
            '  requests=${outcome.requests}  ${outcome.ok ? "" : "partial=${outcome.partial} ${outcome.reason}"}');
      } else if (feature == AiFeature.define) {
        final proof = outcome.selfProof?.name ?? '-';
        stdout.writeln('  $word: selfProof=$proof  '
            '${outcome.ok ? "ok" : "reason=${outcome.reason}"}'
            '  requests=${outcome.requests}');
      } else {
        stdout.writeln('  $word: ${outcome.ok ? "ok" : "FAIL ${outcome.reason}"}'
            '  requests=${outcome.requests}');
      }

      // L5：逐条例句检查是否含该词或其已知词形
      final forms = <String>[word, ...knownForms];
      for (final e in outcome.card?.allExamples ?? const <AiExample>[]) {
        l5Total++;
        if (forms.any((f) =>
            RegExp(r'\b' + RegExp.escape(f) + r'\b', caseSensitive: false)
                .hasMatch(e.en))) {
          l5Pass++;
        } else {
          stdout.writeln('    L5 MISS: ${e.en}');
        }
      }
    }
  } finally {
    await db.close();
  }

  // 缓存命中与 token：从库里汇总
  final con = await databaseFactory.openDatabase(nb,
      options: OpenDatabaseOptions(singleInstance: false));
  final agg = (await con.rawQuery(
          'SELECT COALESCE(SUM(hit_count),0) h, COALESCE(SUM(prompt_tokens),0) pt, '
          'COALESCE(SUM(cache_hit_tokens),0) ch, COUNT(*) c FROM ai_cache'))
      .first;
  await con.close();
  cacheHit = agg['h'] as int;
  promptTokens = agg['pt'] as int;
  final hitTokens = agg['ch'] as int;

  stdout.writeln('');
  stdout.writeln('L2 词性覆盖: $l2Pass/$l2Total');
  stdout.writeln('L5 例句含词: $l5Pass/$l5Total');
  stdout.writeln('平均请求次数: ${(requests / words.length).toStringAsFixed(2)}'
      '（> 1.5 说明提示词需要改）');
  stdout.writeln('前缀缓存命中: $hitTokens/$promptTokens token'
      '${promptTokens > 0 ? "（${(100 * hitTokens / promptTokens).toStringAsFixed(1)}%）" : ""}');
  stdout.writeln('缓存条目: ${agg['c']}  累计命中: $cacheHit');

  clearDataHomeOverride();
  await dataHome.delete(recursive: true);
}
