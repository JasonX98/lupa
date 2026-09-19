// AI 词卡解析与校验纯函数测试。用例形态参照 DeepSeek JSON 模式的真实输出。
import 'package:flutter_test/flutter_test.dart';

import 'package:lupa/ai/card.dart';

/// 造一个结构合法的 full 模式返回体。
///
/// 注意例句刻意都用原形 `record`（而非 `recorded`）：L5 要求例句含该词或其
/// **已传入的**词形，而 `knownForms` 默认不传，所以用变形词会让这份夹具
/// 自己撞上 L5。需要测词形时应显式传 `knownForms`。
String fullJson({
  String word = 'record',
  List<Map<String, Object?>>? senses,
  List<Map<String, Object?>>? collocations,
}) =>
    '{"word":"$word","canonical":"$word","is_known_word":true,'
    '"senses":${_j(senses ?? [
          {
            'pos': 'n.',
            'gloss': '记录',
            'examples': [
              {'en': 'He kept a record of everything.', 'zh': '他记录下了一切。'}
            ]
          },
          {
            'pos': 'vt.',
            'gloss': '记录',
            'examples': [
              {'en': 'She will record the meeting.', 'zh': '她会录下会议。'}
            ]
          },
        ])},'
    '"collocations":${_j(collocations ?? [
          {
            'phrase': 'record a video',
            'gloss': '录制视频',
            'examples': [
              {'en': 'They record a video every week.', 'zh': '他们每周录一段视频。'}
            ]
          }
        ])}}';

String _j(Object? v) {
  if (v is String) return '"$v"';
  if (v is num || v is bool) return '$v';
  if (v is List) return '[${v.map(_j).join(',')}]';
  if (v is Map) {
    return '{${v.entries.map((e) => '"${e.key}":${_j(e.value)}').join(',')}}';
  }
  return 'null';
}

void main() {
  group('parseAiCard：正常解析', () {
    test('解析出词性组、搭配与例句', () {
      final o = parseAiCard(fullJson());
      expect(o.ok, isTrue);
      final c = o.card!;
      expect(c.word, 'record');
      expect(c.senses.length, 2);
      expect(c.senseLabels, {'n.', 'vt.'});
      expect(c.collocations.single.label, 'record a video');
      expect(c.collocations.single.gloss, '录制视频');
      expect(c.allExamples.length, 3);
      expect(c.allExamples.first.zh, isNotEmpty);
    });

    test('容忍例句写成纯字符串数组', () {
      final o = parseAiCard(
          '{"word":"go","examples":["I go to school."],"is_known_word":true}');
      expect(o.ok, isTrue);
      expect(o.card!.examples.single.en, 'I go to school.');
      expect(o.card!.examples.single.zh, '');
    });

    test('空例句被丢弃，但不导致整体失败', () {
      final o = parseAiCard(
          '{"word":"go","examples":[{"en":"","zh":"x"},{"en":"I go.","zh":""}],'
          '"is_known_word":true}');
      expect(o.ok, isTrue);
      expect(o.card!.examples.length, 1);
      expect(o.card!.examples.single.en, 'I go.');
    });

    test('标签字段名容错：搭配组用 phrase 或 label 都认', () {
      final o = parseAiCard('{"word":"go","is_known_word":true,"collocations":'
          '[{"label":"go home","examples":[{"en":"I go home.","zh":""}]}]}');
      expect(o.ok, isTrue);
      expect(o.card!.collocations.single.label, 'go home');
    });
  });

  group('parseAiCard：畸形输入不抛异常', () {
    test('不是 JSON', () {
      final o = parseAiCard('not json at all');
      expect(o.ok, isFalse);
      expect(o.error, isNotNull);
    });

    test('顶层是数组', () {
      final o = parseAiCard('[1,2,3]');
      expect(o.ok, isFalse);
      expect(o.error, contains('顶层'));
    });

    test('空字符串', () {
      expect(parseAiCard('').ok, isFalse);
    });

    test('缺少 word 字段', () {
      final o = parseAiCard('{"senses":[]}');
      expect(o.ok, isFalse);
      expect(o.error, contains('word'));
    });

    test('字段类型错误：word 是数字', () {
      final o = parseAiCard('{"word":123}');
      // 数字被 _str 转成 '123'，不算缺字段 —— 契约是「不抛异常」
      expect(o.ok, isTrue);
      expect(o.card!.word, '123');
    });

    test('字段类型错误：senses 是字符串', () {
      final o = parseAiCard('{"word":"go","senses":"oops"}');
      expect(o.ok, isTrue);
      expect(o.card!.senses, isEmpty);
    });

    test('字段类型错误：is_known_word 是字符串 "false"', () {
      final o = parseAiCard('{"word":"go","is_known_word":"false"}');
      expect(o.ok, isTrue);
      expect(o.card!.isKnownWord, isFalse);
    });

    test('嵌套结构缺 examples', () {
      final o = parseAiCard('{"word":"go","is_known_word":true,'
          '"senses":[{"pos":"n.","gloss":"走"}]}');
      expect(o.ok, isTrue);
      expect(o.card!.senses.single.examples, isEmpty);
    });

    test('嵌套结构缺 label（pos 与 label 都没有）被丢弃', () {
      final o = parseAiCard('{"word":"go","is_known_word":true,'
          '"senses":[{"gloss":"走","examples":[{"en":"I go.","zh":""}]}]}');
      expect(o.ok, isTrue);
      expect(o.card!.senses, isEmpty);
    });
  });

  group('L1 结构校验', () {
    test('无任何例句 -> 结构违规', () {
      final c = parseAiCard('{"word":"go","is_known_word":true}').card!;
      final v = validateAiCard(c, feature: AiFeature.enrich);
      expect(v.ok, isFalse);
      expect(v.violations.map((e) => e.kind),
          contains(AiViolationKind.structure));
    });

    test('某一组没有例句 -> 结构违规并指出组名', () {
      final c = parseAiCard('{"word":"go","is_known_word":true,"senses":'
          '[{"pos":"n.","gloss":"走","examples":[]},'
          '{"pos":"v.","gloss":"去","examples":[{"en":"I go.","zh":""}]}]}')
          .card!;
      final v = validateAiCard(c, feature: AiFeature.enrich);
      expect(v.ok, isFalse);
      expect(v.repairHint, contains('n.'));
    });

    test('define 缺释义 -> 结构违规', () {
      final c = parseAiCard('{"word":"serendipity","is_known_word":true,'
          '"senses":[{"pos":"n.","gloss":"","examples":[{"en":"a serendipity","zh":""}]}]}')
          .card!;
      final v = validateAiCard(c, feature: AiFeature.define);
      expect(v.violations.any((e) => e.message.contains('释义')), isTrue);
    });

    test('enrichPlain 缺通用例句 -> 结构违规', () {
      final c = parseAiCard('{"word":"online","is_known_word":true}').card!;
      final v = validateAiCard(c, feature: AiFeature.enrichPlain);
      expect(v.ok, isFalse);
      expect(v.repairHint, contains('通用例句'));
    });
  });

  group('L2 覆盖校验（仅 full 模式）', () {
    test('缺少本地词性 -> 覆盖违规且提示缺哪些', () {
      final c = parseAiCard(fullJson(senses: [
        {
          'pos': 'n.',
          'gloss': '记录',
          'examples': [
            {'en': 'a record', 'zh': ''}
          ]
        }
      ])).card!;
      final v = validateAiCard(c,
          feature: AiFeature.enrich, expectedPos: ['n.', 'vt.', 'vi.']);
      expect(v.ok, isFalse);
      final cov = v.violations
          .firstWhere((e) => e.kind == AiViolationKind.coverage);
      expect(cov.message, contains('vt.'));
      expect(cov.message, contains('vi.'));
    });

    test('完全覆盖 -> 通过', () {
      final c = parseAiCard(fullJson()).card!;
      final v = validateAiCard(c,
          feature: AiFeature.enrich, expectedPos: ['n.', 'vt.']);
      expect(v.ok, isTrue);
    });

    test('expectedPos 为空 -> L2 不生效', () {
      final c = parseAiCard(fullJson(senses: [
        {
          'pos': 'n.',
          'gloss': 'x',
          'examples': [
            {'en': 'a record', 'zh': ''}
          ]
        }
      ])).card!;
      final v = validateAiCard(c,
          feature: AiFeature.enrich, expectedPos: const []);
      expect(v.ok, isTrue);
    });

    test('degraded 模式不做 L2', () {
      final c = parseAiCard('{"word":"online","is_known_word":true,'
          '"examples":[{"en":"I am online.","zh":""}]}').card!;
      final v = validateAiCard(c,
          feature: AiFeature.enrichPlain, expectedPos: ['n.', 'v.']);
      expect(v.ok, isTrue);
    });
  });

  group('L3 自洽校验（仅 define 模式）', () {
    test('自报词性没有对应分组 -> 违规', () {
      final c = parseAiCard('{"word":"serendipity","is_known_word":true,'
          '"translation":"n. 意外发现珍奇事物的运气","pos":["n.","v."],'
          '"senses":[{"pos":"n.","gloss":"运气","examples":[{"en":"serendipity came","zh":""}]}]}')
          .card!;
      final v = validateAiCard(c, feature: AiFeature.define);
      expect(v.ok, isFalse);
      expect(v.violations.single.kind, AiViolationKind.selfConsistency);
      expect(v.violations.single.message, contains('v.'));
    });

    test('自报词性与分组一致 -> 通过', () {
      final c = parseAiCard('{"word":"serendipity","is_known_word":true,'
          '"translation":"n. 运气","pos":["n."],'
          '"senses":[{"pos":"n.","gloss":"运气","examples":[{"en":"serendipity","zh":""}]}]}')
          .card!;
      expect(validateAiCard(c, feature: AiFeature.define).ok, isTrue);
    });

    test('enrich 模式不做 L3', () {
      final c = parseAiCard('{"word":"record","is_known_word":true,"pos":["zzz."],'
          '"senses":[{"pos":"n.","gloss":"x","examples":[{"en":"a record","zh":""}]}]}')
          .card!;
      expect(
          validateAiCard(c,
                  feature: AiFeature.enrich, expectedPos: ['n.'])
              .ok,
          isTrue);
    });
  });

  group('L5 例句必须含该词或其已知词形', () {
    test('例句完全不含该词 -> 违规', () {
      final c = parseAiCard(fullJson(senses: [
        {
          'pos': 'n.',
          'gloss': 'x',
          'examples': [
            {'en': 'She decided to give up her old habits.', 'zh': '她决定放弃旧习惯。'}
          ]
        }
      ], collocations: [
        {
          'phrase': 'x',
          'gloss': '',
          'examples': [
            {'en': 'She decided to give up her old habits.', 'zh': ''}
          ]
        }
      ])).card!;
      final v = validateAiCard(c, feature: AiFeature.enrich);
      expect(v.ok, isFalse);
      expect(v.violations.any((e) => e.kind == AiViolationKind.exampleMissingWord),
          isTrue);
    });

    test('例句含已知词形（abandoned）-> 通过', () {
      final c = parseAiCard('{"word":"abandon","is_known_word":true,'
          '"senses":[{"pos":"v.","gloss":"放弃","examples":[{"en":"They abandoned the plan.","zh":""}]}]}')
          .card!;
      final v = validateAiCard(c,
          feature: AiFeature.enrich,
          expectedPos: ['v.'],
          knownForms: ['abandoned', 'abandoning']);
      expect(v.ok, isTrue);
    });

    test('词形未传入时，变形例句会被判违规（证明词形来自 exchange 而非宽松匹配）', () {
      final c = parseAiCard('{"word":"abandon","is_known_word":true,'
          '"senses":[{"pos":"v.","gloss":"放弃","examples":[{"en":"They abandoned the plan.","zh":""}]}]}')
          .card!;
      final v = validateAiCard(c,
          feature: AiFeature.enrich, expectedPos: ['v.']);
      expect(v.ok, isFalse);
    });

    test('大小写不敏感', () {
      final c = parseAiCard('{"word":"abandon","is_known_word":true,'
          '"senses":[{"pos":"v.","gloss":"x","examples":[{"en":"Abandon ship!","zh":""}]}]}')
          .card!;
      expect(validateAiCard(c, feature: AiFeature.enrich).ok, isTrue);
    });

    test('短词用词边界匹配：词 a 不会被 "a cat" 之外的词误命中', () {
      final c = parseAiCard('{"word":"a","is_known_word":true,'
          '"senses":[{"pos":"art.","gloss":"一个","examples":[{"en":"That is an apple.","zh":""}]}]}')
          .card!;
      final v = validateAiCard(c, feature: AiFeature.enrich);
      expect(v.ok, isFalse, reason: 'an apple 不含独立的词 a');
    });

    test('短词命中自身词边界', () {
      final c = parseAiCard('{"word":"a","is_known_word":true,'
          '"senses":[{"pos":"art.","gloss":"一个","examples":[{"en":"I saw a cat.","zh":""}]}]}')
          .card!;
      expect(validateAiCard(c, feature: AiFeature.enrich).ok, isTrue);
    });
  });

  group('L4 自证（独立于校验与修复重试）', () {
    AiCard card({required bool known, String canonical = ''}) =>
        AiCard(word: 'serendipty', isKnownWord: known, canonical: canonical);

    test('不是英语词 -> notAWord', () {
      expect(selfProofOf(card(known: false), 'serendipty'), SelfProof.notAWord);
    });

    test('拼写不同 -> misspelled', () {
      expect(selfProofOf(card(known: true, canonical: 'serendipity'), 'serendipty'),
          SelfProof.misspelled);
    });

    test('拼写一致 -> known', () {
      expect(selfProofOf(card(known: true, canonical: 'serendipity'), 'serendipity'),
          SelfProof.known);
    });

    test('canonical 为空 -> known（不因缺字段而误报拼写问题）', () {
      expect(selfProofOf(card(known: true), 'serendipty'), SelfProof.known);
    });

    test('拼写比较大小写不敏感', () {
      expect(selfProofOf(card(known: true, canonical: 'Abandon'), 'abandon'),
          SelfProof.known);
    });

    test('notAWord 优先于拼写判定', () {
      expect(selfProofOf(card(known: false, canonical: 'other'), 'x'),
          SelfProof.notAWord);
    });
  });

  group('例句数上限截断（多给不算错）', () {
    test('超过 2 条被截断', () {
      final c = parseAiCard('{"word":"go","is_known_word":true,"senses":'
          '[{"pos":"v.","gloss":"去","examples":['
          '{"en":"I go.","zh":""},{"en":"You go.","zh":""},'
          '{"en":"We go.","zh":""},{"en":"They go.","zh":""}]}]}').card!;
      final t = truncateExamples(c);
      expect(t.senses.single.examples.length, 2);
      expect(t.senses.single.examples.first.en, 'I go.');
    });

    test('截断后仍通过校验（不因多给而判失败）', () {
      final c = parseAiCard('{"word":"go","is_known_word":true,"senses":'
          '[{"pos":"v.","gloss":"去","examples":['
          '{"en":"I go.","zh":""},{"en":"You go.","zh":""},{"en":"We go.","zh":""}]}]}')
          .card!;
      expect(validateAiCard(truncateExamples(c), feature: AiFeature.enrich).ok,
          isTrue);
    });

    test('未超上限时原样返回', () {
      final c = parseAiCard(fullJson()).card!;
      final t = truncateExamples(c);
      expect(t.senses.length, c.senses.length);
      expect(t.collocations.single.examples.length, 1);
    });
  });

  group('AiFeature 契约', () {
    test('缓存 feature 段取值', () {
      expect(AiFeature.enrich.cacheFeature, 'enrich');
      expect(AiFeature.enrichPlain.cacheFeature, 'enrich-plain');
      expect(AiFeature.define.cacheFeature, 'define');
    });

    test('三种 feature 段互不相同', () {
      final s = AiFeature.values.map((f) => f.cacheFeature).toSet();
      expect(s.length, AiFeature.values.length);
    });

    test('只有降级补齐不要求词性分组', () {
      expect(AiFeature.enrich.requiresPosGroups, isTrue);
      expect(AiFeature.define.requiresPosGroups, isTrue);
      expect(AiFeature.enrichPlain.requiresPosGroups, isFalse);
    });
  });
}
