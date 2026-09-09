// 标签胶囊 —— 查词详情卡与生词本详情弹窗共用（设计稿 TagBadge）。
// 按类型配色：考试标签主色、柯林斯琥珀、牛津紫、词频/自定义灰。
import 'package:flutter/material.dart';

import 'package:lupa/theme/lupa_theme.dart';

/// 标签配色类型。
enum TagKind { exam, collins, oxford, freq, plain }

class TagChip extends StatelessWidget {
  final String label;
  final TagKind kind;
  const TagChip({super.key, required this.label, this.kind = TagKind.plain});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (fg, bg) = _palette(isDark);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg),
      ),
    );
  }

  /// 返回 (文字色, 底色)。语义色按明暗取设计稿对应值，底色用同色低透明度铺底。
  (Color, Color) _palette(bool isDark) {
    switch (kind) {
      case TagKind.exam:
        final c = isDark ? LupaColors.jadeDark : LupaColors.jade;
        return (c, c.withValues(alpha: isDark ? 0.20 : 0.12));
      case TagKind.collins:
        final c = isDark ? LupaColors.warningDark : LupaColors.warningLight;
        return (c, c.withValues(alpha: isDark ? 0.20 : 0.14));
      case TagKind.oxford:
        final c = isDark ? LupaColors.violetDark : LupaColors.violetLight;
        return (c, c.withValues(alpha: isDark ? 0.22 : 0.12));
      case TagKind.freq:
      case TagKind.plain:
        final fg = isDark ? LupaColors.tx3Dark : LupaColors.tx3Light;
        final bg = isDark ? const Color(0xFF2B2E2B) : const Color(0xFFEFEEE9);
        return (fg, bg);
    }
  }
}
