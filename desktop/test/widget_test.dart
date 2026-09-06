// Lupa 冒烟测试：主题 token 可生成、外壳类型存在。
// AppState 依赖 sqlite/网络，UI 全流程验证走 tool/verify_e2e.dart（headless）。
import 'package:flutter_test/flutter_test.dart';

import 'package:lupa/theme/lupa_theme.dart';
import 'package:lupa/widgets/app_shell.dart';
import 'package:lupa/widgets/word_bits.dart';

void main() {
  test('主题：明暗两套可生成，强调色一致策略', () {
    final light = lupaLightTheme;
    final dark = lupaDarkTheme;
    expect(light.scaffoldBackgroundColor, isNot(dark.scaffoldBackgroundColor));
    // 玉青 token：浅色 #0E7C6B / 深色 #4DC2AB
    expect(light.colorScheme.primary.toARGB32(), 0xFF0E7C6B);
    expect(dark.colorScheme.primary.toARGB32(), 0xFF4DC2AB);
  });

  test('word_bits：词形解析与到期文案', () {
    expect(exchangeLines('d:abandoned/p:abandoned/i:abandoning'),
        [('过去式', 'abandoned'), ('过去分词', 'abandoned'), ('现在分词', 'abandoning')]);
    expect(exchangeLines(''), isEmpty);
    expect(collinsStars(3), '★★★');
    expect(collinsStars(0), '');
    expect(tagList('zk gk cet4'), ['zk', 'gk', 'cet4']);
    // type=0 一律新词；过期时间戳 -> 今天
    expect(dueLabel(0, 0), '新词');
    expect(dueLabel(2, 1000), '今天');
  });

  test('AppShell 类型存在', () {
    expect(AppShell, isNotNull);
  });
}
