// Lupa 应用外壳：左侧导航 + 页面路由 + 全局快捷键。
// 键盘优先：Ctrl+F 查词 / Ctrl+B 生词本 / Ctrl+R 复习 / Ctrl+E 导出。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lupa/pages/export_page.dart';
import 'package:lupa/pages/notebook_page.dart';
import 'package:lupa/pages/review_page.dart';
import 'package:lupa/pages/search_page.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/theme/lupa_theme.dart';

class AppShell extends StatefulWidget {
  final AppState state;
  const AppShell({super.key, required this.state});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _page = 0; // 0=查词 1=生词本 2=复习 3=导出

  static const _items = [
    (Icons.search, '查词', 'Ctrl+F'),
    (Icons.auto_stories_outlined, '生词本', 'Ctrl+B'),
    (Icons.style_outlined, '复习', 'Ctrl+R'),
    (Icons.ios_share, '导出', 'Ctrl+E'),
  ];

  void _go(int i) => setState(() => _page = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      SearchPage(state: widget.state, isActive: _page == 0),
      NotebookPage(state: widget.state, onGotoReview: () => _go(2)),
      ReviewPage(state: widget.state, isActive: _page == 2),
      ExportPage(state: widget.state),
    ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _go(0),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () => _go(2),
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): () => _go(3),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSidebar(context),
              VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).dividerColor),
              Expanded(child: IndexedStack(index: _page, children: pages)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget navItem(int i) {
      final (icon, label, shortcut) = _items[i];
      final selected = _page == i;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Material(
          color: selected
              ? (isDark ? const Color(0xFF1E3A34) : const Color(0xFFE7F2EF))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _go(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(children: [
                Icon(icon, size: 19,
                    color: selected ? scheme.primary : scheme.outline),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? scheme.primary : text.bodyMedium!.color)),
                ),
                Text(shortcut,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: selected ? scheme.primary : scheme.outline)),
              ]),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: 208,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('Lupa',
                    style: TextStyle(
                        fontFamily: wordFontFamily, fontSize: 22,
                        fontWeight: FontWeight.w700, color: scheme.onSurface)),
                const SizedBox(width: 8),
                Text('璐帕', style: text.bodySmall),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
            child: Text('看清词，留住词', style: text.labelSmall),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < _items.length; i++) ...[
            navItem(i),
            const SizedBox(height: 4),
          ],
          const Spacer(),
          // ---- 主题切换 ----
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.state.toggleTheme,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                child: Row(children: [
                  Icon(
                    switch (widget.state.themeMode) {
                      ThemeMode.light => Icons.light_mode_outlined,
                      ThemeMode.dark => Icons.dark_mode_outlined,
                      ThemeMode.system => Icons.settings_brightness_outlined,
                    },
                    size: 18, color: scheme.outline),
                  const SizedBox(width: 10),
                  Text(widget.state.themeLabel, style: text.bodyMedium),
                  const Spacer(),
                  const Icon(Icons.autorenew, size: 13, color: Colors.transparent),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 16),
            child: Text('v1.0.0 · 本地优先', style: text.labelSmall),
          ),
        ],
      ),
    );
  }
}
