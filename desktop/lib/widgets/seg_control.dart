// Lupa 分段选择控件 —— 主题 / 口音 / 调度算法等三档选择。
// 选中态 = 主色浅底 + 主色文字；支持禁用档位（如 FSRS v2）。
// 与《Lupa 桌面版 UI 设计方案》组件库的 segmented 控件对齐。
import 'package:flutter/material.dart';

class SegOption<T> {
  final String label;
  final T value;
  final bool enabled;
  final String? caption; // 可选：档位下的小字标注（如 "v2"）

  const SegOption(this.label, this.value, {this.enabled = true, this.caption});
}

class SegControl<T> extends StatelessWidget {
  final List<SegOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const SegControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final opt in options) _segment(context, opt, scheme, text, isDark),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, SegOption<T> opt, ColorScheme scheme,
      TextTheme text, bool isDark) {
    final isSel = opt.value == selected;
    final fg = opt.enabled
        ? (isSel
            ? (isDark ? scheme.primary : ColorScheme.of(context).onSurface)
            : scheme.onSurfaceVariant)
        : (isSel ? scheme.primary : scheme.onSurfaceVariant);
    return GestureDetector(
      onTap: opt.enabled ? () => onChanged(opt.value) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSel
              ? (opt.enabled
                  ? (isDark
                      ? const Color(0xFF1E3A34)
                      : const Color(0xFFE7F2EF))
                  : Colors.transparent)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              opt.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                color: fg,
              ),
            ),
            if (opt.caption != null) ...[
              const SizedBox(width: 2),
              Text(
                opt.caption!,
                style: TextStyle(fontSize: 10, color: text.bodySmall!.color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
