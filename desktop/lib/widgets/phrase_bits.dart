// 短语集 UI 小工具：到期文案、筛选分段控件、例句编辑行、例句展示。
// 与单词生词本组件风格保持一致（widgets/word_bits.dart、tag_chip.dart）。
import 'package:flutter/material.dart';

import 'package:lupa/theme/lupa_theme.dart';

/// 短语 due 展示文案：新短语 / 今天 / MM-dd（与 dueLabel 同规则）。
String phraseDueLabel(int state, int dueUnixSeconds, {DateTime? now}) {
  if (state == 0) return '新短语';
  final n = now ?? DateTime.now();
  final d = DateTime.fromMillisecondsSinceEpoch(dueUnixSeconds * 1000);
  if (d.isBefore(n)) return '今天';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.month)}-${two(d.day)}';
}

/// 筛选分段控件（对齐原型 .chips/.chip：单容器 + 分段，选中段玉青实心）。
class PhraseFilterSegment {
  final String value;
  final String label;
  final int count;
  final Color? dot;
  const PhraseFilterSegment({
    required this.value,
    required this.label,
    required this.count,
    this.dot,
  });
}

/// 标签圆点颜色（按索引循环，明暗各一套；对齐原型 .st-new/.st-review 双色）。
Color phraseDotColor(int index, bool isDark) {
  const light = [
    Color(0xFF8B908A),
    LupaColors.jade,
    LupaColors.violetLight,
    LupaColors.warningLight,
  ];
  const dark = [
    Color(0xFF8B908A),
    LupaColors.jadeDark,
    LupaColors.violetDark,
    LupaColors.warningDark,
  ];
  return (isDark ? dark : light)[index % 4];
}

class PhraseFilterBar extends StatelessWidget {
  final List<PhraseFilterSegment> segments;
  final String selected;
  final ValueChanged<String> onSelect;

  const PhraseFilterBar({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [for (final s in segments) _segment(context, s)],
      ),
    );
  }

  Widget _segment(BuildContext context, PhraseFilterSegment s) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onAccent = isDark ? LupaColors.onJadeDark : LupaColors.onJadeLight;
    final isSelected = s.value == selected;
    final fg = isSelected ? onAccent : theme.colorScheme.onSurface;

    return Material(
      color: isSelected ? theme.colorScheme.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onSelect(s.value),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              if (s.dot != null)
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: isSelected ? onAccent : s.dot,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(s.label,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
              Text('${s.count}',
                  style: TextStyle(
                      fontSize: 10, color: fg.withValues(alpha: 0.7))),
            ],
          ),
        ),
      ),
    );
  }
}

/// 例句编辑行控制器：由父表单持有，便于读取/销毁。
class ExampleEditRowController {
  final TextEditingController en;
  final TextEditingController zh;
  ExampleEditRowController({String enText = '', String zhText = ''})
      : en = TextEditingController(text: enText),
        zh = TextEditingController(text: zhText);
  void dispose() {
    en.dispose();
    zh.dispose();
  }
}

/// 例句编辑行（英文句 + 中文翻译 + 删除）。
class ExampleEditRow extends StatelessWidget {
  final ExampleEditRowController controller;
  final VoidCallback onRemove;
  const ExampleEditRow({
    super.key,
    required this.controller,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(children: [
            TextField(
              controller: controller.en,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'English sentence',
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: controller.zh,
              decoration: const InputDecoration(
                isDense: true,
                hintText: '中文翻译',
              ),
            ),
          ]),
        ),
        IconButton(
          tooltip: '删除例句',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ]),
    );
  }
}

/// 场景编辑行控制器：由父表单持有，便于读取 / 聚焦 / 销毁。
class SceneEditRowController {
  final TextEditingController scene;
  final FocusNode focus;
  SceneEditRowController({String sceneText = ''})
      : scene = TextEditingController(text: sceneText),
        focus = FocusNode();
  void dispose() {
    scene.dispose();
    focus.dispose();
  }
}

/// 使用场景编辑行：一条场景（可视觉换行，但不产生行内换行）+ 删除。
///
/// 回车 = 新增下一条场景：`textInputAction: done` 让引擎把回车翻成 done action
/// 而**不是**插入换行，onSubmitted 里再新增一行（契约见
/// openspec/changes/phrase-scene-list design D2/D3）。
///
/// `onEditingComplete` 必须给：否则 EditableText 会在 done 时先 unfocus，
/// 中文输入法组字中被夺焦会中断候选。组字中（composing 有效）直接放行，
/// 交给输入法确认候选。
class SceneEditRow extends StatelessWidget {
  final SceneEditRowController controller;
  final VoidCallback onRemove;
  final VoidCallback onSubmit;
  const SceneEditRow({
    super.key,
    required this.controller,
    required this.onRemove,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            controller: controller.scene,
            focusNode: controller.focus,
            minLines: 1,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.done,
            onEditingComplete: () {},
            onSubmitted: (_) {
              if (controller.scene.value.composing.isValid) return;
              onSubmit();
            },
            decoration: const InputDecoration(
              isDense: true,
              hintText: '什么场合用？对谁说？（回车加下一条）',
            ),
          ),
        ),
        IconButton(
          tooltip: '删除场景',
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ]),
    );
  }
}

/// 收录日期 YYYY-MM-DD（详情弹窗「收录于 …」用）。
String formatAddedDate(int unixSeconds) {
  final d = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// 虚线分隔线（例句之间，对应原型 .ex-item 的 dashed 下边框）。
class PhraseDashedDivider extends StatelessWidget {
  const PhraseDashedDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedLinePainter(color: Theme.of(context).dividerColor),
      size: const Size(double.infinity, 1),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 5.0, gap = 4.0;
    final y = size.height / 2;
    var x = 0.0;
    while (x < size.width) {
      final x2 = (x + dash) > size.width ? size.width : x + dash;
      canvas.drawLine(Offset(x, y), Offset(x2, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 例句展示（英文 + 中文，中文用 tx2 保证可读性）。
class PhraseExampleView extends StatelessWidget {
  final String en;
  final String zh;
  const PhraseExampleView({super.key, required this.en, required this.zh});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final zhColor = isDark ? LupaColors.tx2Dark : LupaColors.tx2Light;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(en, style: text.bodyMedium),
        if (zh.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(zh, style: text.bodySmall!.copyWith(color: zhColor)),
          ),
      ]),
    );
  }
}
