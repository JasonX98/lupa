// Lupa 开关 —— 设计规范的拨动开关：38×22，滑块 16px 带 1px 投影，拨动 200ms。
// 与《Lupa 桌面版 UI 设计方案》组件库 Switch（38×22）对齐。
import 'package:flutter/material.dart';

class LupaSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  const LupaSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on = value ? scheme.primary : scheme.surfaceContainerHighest;
    final thumb = Colors.white;
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: GestureDetector(
        onTap: enabled ? () => onChanged(!value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: 38,
          height: 22,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: on,
            borderRadius: BorderRadius.circular(11),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment:
                value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: thumb,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
