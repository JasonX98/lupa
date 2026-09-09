// FlipCard：翻面切换正/背面；减少动效时交叉淡入；点击触发 onTap。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupa/widgets/flip_card.dart';

void main() {
  Widget build(bool showBack, {VoidCallback? onTap}) => MaterialApp(
        home: Scaffold(
          body: FlipCard(
            showBack: showBack,
            onTap: onTap,
            front: const Text('FRONT'),
            back: const Text('BACK'),
          ),
        ),
      );

  testWidgets('翻面：showBack 从 false→true 后显示背面', (tester) async {
    await tester.pumpWidget(build(false));
    expect(find.text('FRONT'), findsOneWidget);
    expect(find.text('BACK'), findsNothing);

    await tester.pumpWidget(build(true));
    await tester.pumpAndSettle(); // 480ms 3D 翻面
    expect(find.text('BACK'), findsOneWidget);
    expect(find.text('FRONT'), findsNothing);
  });

  testWidgets('减少动效：交叉淡入仍切到背面', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(800, 600), disableAnimations: true),
        child: Scaffold(
          body: FlipCard(
            showBack: true,
            front: const Text('F'),
            back: const Text('B'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('点击触发 onTap（翻面）', (tester) async {
    var tapped = false;
    await tester.pumpWidget(build(false, onTap: () => tapped = true));
    await tester.tap(find.byType(FlipCard));
    await tester.pump();
    expect(tapped, true);
  });
}
