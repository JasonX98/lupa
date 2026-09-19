// 用真实词库 + 真实 AI 卡片内容验证渲染（不联网：直接构造 hoax 的 AI 卡）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupa/ai/card.dart';
import 'package:lupa/ai/enrich.dart';
import 'package:lupa/widgets/word_bits.dart';

void main() {
  testWidgets('hoax 这类多组内容在小窗口下可滚动（回归：曾溢出 547px）', (tester) async {
    // 小窗口：800x600（默认）
    final card = parseAiCard(
        '{"word":"hoax","is_known_word":true,'
        '"senses":[{"pos":"vt.","gloss":"欺骗，哄骗，愚弄","examples":['
        '{"en":"The students hoaxed their teacher by hiding all the chalk.","zh":"学生们把所有的粉笔都藏了起来，以此戏弄老师。"},'
        '{"en":"He was hoaxed into believing the story.","zh":"他受骗相信了那个故事。"}]},'
        '{"pos":"n.","gloss":"愚弄人，恶作剧","examples":['
        '{"en":"The whole thing turned out to be a hoax.","zh":"整件事原来是一场骗局。"}]}],'
        '"collocations":[{"phrase":"a hoax call","gloss":"恶作剧电话","examples":['
        '{"en":"Police treated it as a hoax call.","zh":"警方把它当作恶作剧电话处理。"}]},'
        '{"phrase":"elaborate hoax","gloss":"精心设计的骗局","examples":['
        '{"en":"It was an elaborate hoax.","zh":"那是一个精心设计的骗局。"}]}]}')
        .card!;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: AiSection(outcome: AiOutcome(card: card))))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    // 内容确实渲染出来了
    expect(find.text('vt.'), findsOneWidget);
    expect(find.text('n.'), findsOneWidget);
    expect(find.text('常用搭配'), findsOneWidget);
    expect(find.text('a hoax call'), findsOneWidget);
    expect(find.text('elaborate hoax'), findsOneWidget);
  });
}
