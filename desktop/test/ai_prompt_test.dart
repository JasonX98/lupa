// 提示词纯函数测试。
//
// 重点守两条不变式（design D10）：
//   1) 同一 feature 的 system 段**逐字稳定** —— 它是 DeepSeek 前缀缓存的匹配单元，
//      任何随调用变化的插值都会让缓存永久失效
//   2) 三套 system 段互不相同 —— 一个 feature 一个前缀单元
import 'package:flutter_test/flutter_test.dart';

import 'package:lupa/ai/card.dart';
import 'package:lupa/ai/prompt.dart';

void main() {
  group('system 段逐字稳定（前缀缓存的前提）', () {
    test('同一 feature 多次调用结果完全相同', () {
      for (final f in AiFeature.values) {
        expect(systemPromptFor(f), systemPromptFor(f), reason: f.name);
      }
    });

    test('system 段不含随调用变化的插值（无占位符残留）', () {
      for (final f in AiFeature.values) {
        final s = systemPromptFor(f);
        expect(s.contains('{word}'), isFalse, reason: f.name);
        expect(s.contains('\$word'), isFalse, reason: f.name);
        expect(s.contains('{pos}'), isFalse, reason: f.name);
      }
    });

    test('system 段长度足够（长前缀才有缓存收益）', () {
      for (final f in AiFeature.values) {
        expect(systemPromptFor(f).length, greaterThan(300), reason: f.name);
      }
    });
  });

  group('三套 system 段互不相同', () {
    test('两两不等', () {
      final s = AiFeature.values.map(systemPromptFor).toList();
      expect(s.toSet().length, AiFeature.values.length);
    });

    test('enrich 要求覆盖词性清单，enrich-plain 明确要求不分组', () {
      expect(enrichSystem, contains('每一个'));
      expect(enrichSystem, contains('senses'));
      expect(enrichPlainSystem, contains('不要按词性分组'));
      expect(enrichPlainSystem, contains('senses 留空'));
    });

    test('define 要求给出 phonetic / translation / pos', () {
      expect(defineSystem, contains('phonetic'));
      expect(defineSystem, contains('translation'));
      expect(defineSystem, contains('"pos"'));
    });
  });

  group('输出契约与解析器一致', () {
    test('解析器读取的字段名都在某套提示词里被要求', () {
      // phonetic / translation / definition 只在 define 的 system 段里
      // （只有整卡需要模型给出释义），所以这里断言的是三套提示词的**并集**。
      final all = AiFeature.values.map(systemPromptFor).join('\n');
      for (final key in [
        'word', 'is_known_word', 'canonical', 'senses', 'collocations',
        'examples', 'pos', 'phonetic', 'translation', 'definition',
        'gloss', 'en', 'zh', 'phrase',
      ]) {
        expect(all.contains('"$key"'), isTrue, reason: key);
      }
    });

    test('解析器读取的字段名与提示词的要求一一对应', () {
      // 反向：提示词里出现的中文字段名，解析器都要真的读
      final c = parseAiCard('{"word":"go","is_known_word":true,"canonical":"go",'
          '"phonetic":"gəʊ","translation":"v. 去","definition":"to move",'
          '"pos":["v."],'
          '"senses":[{"pos":"v.","gloss":"去","examples":[{"en":"I go.","zh":"我去"}]}],'
          '"collocations":[{"phrase":"go home","gloss":"回家","examples":[{"en":"I go home.","zh":""}]}]}').card!;
      expect(c.phonetic, 'gəʊ');
      expect(c.translation, 'v. 去');
      expect(c.definition, 'to move');
      expect(c.pos, ['v.']);
      expect(c.senses.single.gloss, '去');
      expect(c.senses.single.examples.single.zh, '我去');
      expect(c.collocations.single.label, 'go home');
    });

    test('契约里的字段名与 card.dart 的 AiGroup/AiExample 契约一致', () {
      // 词性组用 pos，搭配组用 phrase（与 _groups 的读取逻辑一致）
      expect(AiGroup.kindSense, 'sense');
      expect(AiGroup.kindCollocation, 'collocation');
      expect(enrichSystem, contains('"pos"'));
      expect(enrichSystem, contains('"phrase"'));
    });

    test('promptVersion 是正整数（0 会让旧缓存无法与「无版本」区分）', () {
      expect(promptVersion, greaterThan(0));
    });
  });

  group('userPromptFor', () {
    test('总是包含词本身', () {
      for (final f in AiFeature.values) {
        expect(userPromptFor(f, 'record'), contains('record'));
      }
    });

    test('full 补齐带上必须覆盖的词性清单', () {
      final u = userPromptFor(AiFeature.enrich, 'record',
          pos: ['n.', 'vt.', 'vi.', 'a.']);
      expect(u, contains('必须覆盖的词性'));
      for (final p in ['n.', 'vt.', 'vi.', 'a.']) {
        expect(u, contains(p));
      }
    });

    test('降级与整卡不要求词性清单', () {
      expect(userPromptFor(AiFeature.enrichPlain, 'online', pos: ['n.']),
          isNot(contains('必须覆盖的词性')));
      expect(userPromptFor(AiFeature.define, 'serendipity', pos: ['n.']),
          isNot(contains('必须覆盖的词性')));
    });

    test('带已知词形时列出，便于模型判断例句是否合格', () {
      final u = userPromptFor(AiFeature.enrich, 'go',
          knownForms: ['went', 'gone', 'goes', 'going']);
      expect(u, contains('已知词形变化'));
      expect(u, contains('went'));
    });

    test('带已有释义时一并给出，要求对齐义项', () {
      final u = userPromptFor(AiFeature.enrich, 'record',
          existingTranslation: 'n. 记录\nvt. 记录');
      expect(u, contains('词库已有释义'));
      expect(u, contains('不要另立无关义项'));
    });

    test('缺省参数时不出现空标题行', () {
      final u = userPromptFor(AiFeature.enrich, 'record');
      expect(u, isNot(contains('已知词形变化')));
      expect(u, isNot(contains('词库已有释义')));
      expect(u.trim(), '单词：record');
    });

    test('user 段随词变化（与 system 段相反）', () {
      expect(userPromptFor(AiFeature.enrich, 'a'),
          isNot(userPromptFor(AiFeature.enrich, 'b')));
    });
  });
}
