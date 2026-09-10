// Lupa 应用外壳：左侧导航 + 页面路由 + 全局快捷键。
// 键盘优先：Ctrl+F 查词 / Ctrl+B 生词本 / Ctrl+R 复习 / Ctrl+I 短语集 / Ctrl+E 导出。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lupa/pages/export_page.dart';
import 'package:lupa/pages/notebook_page.dart';
import 'package:lupa/pages/phrase_page.dart';
import 'package:lupa/pages/phrase_review_page.dart';
import 'package:lupa/pages/review_page.dart';
import 'package:lupa/pages/search_page.dart';
import 'package:lupa/pages/settings_page.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/theme/lupa_theme.dart';
import 'package:lupa/version.dart';

class AppShell extends StatefulWidget {
  final AppState state;
  const AppShell({super.key, required this.state});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // 0=查词 1=生词本 2=复习 3=短语集 4=短语复习 5=导出 6=设置
  int _page = 0;

  static const _items = [
    (Icons.search, '查词', 'Ctrl+F', 0),
    (Icons.auto_stories_outlined, '生词本', 'Ctrl+B', 1),
    (Icons.style_outlined, '单词复习', 'Ctrl+R', 2),
    (Icons.forum_outlined, '短语集', 'Ctrl+I', 3),
    (Icons.ios_share, '导出', 'Ctrl+E', 5),
  ];

  void _go(int i) => setState(() => _page = i);

  @override
  Widget build(BuildContext context) {
    final pages = [
      SearchPage(state: widget.state, isActive: _page == 0),
      NotebookPage(state: widget.state, onGotoReview: () => _go(2)),
      ReviewPage(state: widget.state, isActive: _page == 2),
      PhrasePage(
        state: widget.state,
        isActive: _page == 3,
        onGotoReview: () => _go(4),
      ),
      PhraseReviewPage(state: widget.state, isActive: _page == 4),
      ExportPage(state: widget.state),
      SettingsPage(state: widget.state),
    ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _go(0),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true): () => _go(2),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () => _go(3),
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): () => _go(5),
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
      final (icon, label, shortcut, target) = _items[i];
      final selected = _page == target;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Material(
          color: selected
              ? (isDark ? const Color(0xFF1E3A34) : const Color(0xFFE7F2EF))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _go(target),
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
          // ---- 设置入口（主题等统一进设置页）----
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Material(
              color: _page == 6
                  ? (isDark
                      ? const Color(0xFF1E3A34)
                      : const Color(0xFFE7F2EF))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _go(6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(children: [
                    Icon(Icons.settings_outlined, size: 19,
                        color: _page == 6 ? scheme.primary : scheme.outline),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('设置',
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight:
                                  _page == 6 ? FontWeight.w600 : FontWeight.w500,
                              color: _page == 6
                                  ? scheme.primary
                                  : text.bodyMedium!.color)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 16),
            child: Text('v$lupaVersion · 本地优先', style: text.labelSmall),
          ),
        ],
      ),
    );
  }
}
