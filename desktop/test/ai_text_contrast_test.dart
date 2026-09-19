// 对比度审计：AI 区域的文字与图标。
//
// 这类 bug 全是「视觉层的，但可机械化验证」：
//   1) 中文翻译曾用 scheme.outline 当文字色 —— 主题把 outline 映射到**边框色**
//      （0xFFE4E2DD），对比度 1.29:1，实测用户看不清。
//   2) 图标也曾用 outline —— 第一版审计只查 Text，于是这个问题从缝里漏过去。
//      所以本文件同时查文字（阈值 4.5:1）与图标（阈值 3:1）。
//
// 不断言「颜色等于某值」（那种测试改个色号就碎），而是按 WCAG 2.x 算对比度。
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupa/ai/card.dart';
import 'package:lupa/ai/enrich.dart';
import 'package:lupa/theme/lupa_theme.dart';
import 'package:lupa/widgets/word_bits.dart';

/// 相对亮度（WCAG 2.x）。
///
/// 注意是 **2.4 次幂**，不是平方 —— 写错会让所有对比度算成偏小值，从而误报
/// （本文件第一版就踩了这个坑）。另注意 Flutter 的 Color.r/g/b 已归一化到
/// 0..1，且是 sRGB 编码值（不是线性值）。
double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// WCAG 对比度。
double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  late AiCard card;

  setUp(() {
    card = parseAiCard(json.encode({
      'word': 'hoax',
      'is_known_word': true,
      'senses': [
        {
          'pos': 'vt.',
          'gloss': '欺骗，哄骗，愚弄',
          'examples': [
            {'en': 'They hoaxed the teacher.', 'zh': '他们愚弄了老师。'}
          ]
        }
      ],
      'collocations': [
        {
          'phrase': 'a hoax call',
          'gloss': '恶作剧电话',
          'examples': [
            {'en': 'It was a hoax call.', 'zh': '那是一通恶作剧电话。'}
          ]
        }
      ],
    })).card!;
  });

  Future<void> pump(WidgetTester tester, ThemeData theme) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: AiSection(outcome: AiOutcome(card: card)),
        ),
      ),
    ));
    await tester.pump();
  }

  // ---------- 文字 ----------
  for (final (name, dark) in [('浅色', false), ('深色', true)]) {
    testWidgets('$name主题：AI 文字对比度达 WCAG AA（>= 4.5:1）', (tester) async {
      final theme = dark ? lupaDarkTheme : lupaLightTheme;
      await pump(tester, theme);

      final bg = dark ? LupaColors.surfaceDark : LupaColors.surfaceLight;
      // 中文例句翻译、词性释义、搭配释义 —— 用户最常读的三处
      for (final t in ['他们愚弄了老师。', '欺骗，哄骗，愚弄', '恶作剧电话']) {
        final w = tester.widget<Text>(find.text(t));
        final c = w.style?.color;
        expect(c, isNotNull, reason: '「$t」应有显式颜色');
        final ratio = _contrast(c!, bg);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '$name主题「$t」对比度只有 ${ratio.toStringAsFixed(2)}:1'
                '（色 $c，底 $bg）');
      }
    });

    testWidgets('$name主题：AI 正文不得使用 outline（边框色）', (tester) async {
      final theme = dark ? lupaDarkTheme : lupaLightTheme;
      await pump(tester, theme);

      final borderColor = theme.colorScheme.outline;
      for (final t in ['他们愚弄了老师。', '欺骗，哄骗，愚弄', '恶作剧电话']) {
        final w = tester.widget<Text>(find.text(t));
        expect(w.style?.color, isNot(borderColor),
            reason: '「$t」用了 outline（边框色），对比度极低');
      }
    });
  }

  testWidgets('浅色主题：outline 确实是浅边框色（说明为何不能用它当前景色）',
      (tester) async {
    final ratio = _contrast(LupaColors.borderLight, LupaColors.surfaceLight);
    expect(ratio, lessThan(1.6),
        reason: 'outline=border 与白底对比度仅 ${ratio.toStringAsFixed(2)}:1');
  });

  // ---------- 图标（WCAG 非文字 UI 组件，阈值 3:1）----------
  // 成功态没有图标，图标只出现在失败态与 idle 态 —— 所以要逐态检查。
  for (final (name, dark) in [('浅色', false), ('深色', true)]) {
    testWidgets('$name主题：AI 各状态的图标均达 3:1', (tester) async {
      final theme = dark ? lupaDarkTheme : lupaLightTheme;
      final bg = dark ? LupaColors.surfaceDark : LupaColors.surfaceLight;

      final variants = <String, AiOutcome?>{
        '失败': const AiOutcome(reason: 'AI 补齐失败（网络不可用）'),
        '不可用': null,
      };
      var checked = 0;
      for (final v in variants.entries) {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: AiSection(
                outcome: v.value,
                unavailableReason: v.value == null ? 'AI 未启用' : null,
                onRegenerate: v.value != null ? () {} : null,
                onGoSettings: v.value == null ? () {} : null,
              ),
            ),
          ),
        ));
        await tester.pump();
        for (final ic in tester.widgetList<Icon>(find.byType(Icon))) {
          final c = ic.color;
          if (c == null || c.a == 0) continue;
          checked++;
          final ratio = _contrast(c, bg);
          expect(ratio, greaterThanOrEqualTo(3.0),
              reason: '$name主题「${v.key}」态图标对比度只有 '
                  '${ratio.toStringAsFixed(2)}:1（色 $c）');
        }
      }
      expect(checked, greaterThan(0),
          reason: '应至少检查到一个图标（若为 0 说明用例没覆盖到有图标的态）');
    });
  }
}
