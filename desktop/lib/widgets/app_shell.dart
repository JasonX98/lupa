// Lupa 应用外壳：左侧导航 + 页面路由 + 全局快捷键。
// 键盘优先：Ctrl+F 查词 / Ctrl+B 生词本 / Ctrl+R 复习 / Ctrl+I 短语集 / Ctrl+E 导出。
// 焦点归属：页面用 IndexedStack 常驻，因此切页时由外壳显式收回焦点
//（隐藏页若继续持焦，空格/数字键会落到看不见的卡片上；详见 _go 与复习页注释）。
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

/// 侧栏导航与快捷键的单点定义：提示文案与 bindings 都从 [activator] 派生，
/// 避免「侧栏写着 Ctrl+F、实际绑的是别的键」这种两份手写数据漂移。
typedef _NavEntry = ({
  IconData icon,
  String label,
  ShortcutActivator activator,
  int page,
});

class _AppShellState extends State<AppShell> {
  // 0=查词 1=生词本 2=复习 3=短语集 4=短语复习 5=导出 6=设置
  int _page = 0;

  // 外壳焦点：切页时把焦点收回这里，保证 CallbackShortcuts 的继承树上始终有人持焦
  //（它只在「其后代持有焦点」时才拦按键）。
  final _shellFocus = FocusNode(debugLabel: 'AppShell');

  static const _nav = <_NavEntry>[
    (
      icon: Icons.search,
      label: '查词',
      activator: SingleActivator(LogicalKeyboardKey.keyF, control: true),
      page: 0,
    ),
    (
      icon: Icons.auto_stories_outlined,
      label: '生词本',
      activator: SingleActivator(LogicalKeyboardKey.keyB, control: true),
      page: 1,
    ),
    (
      icon: Icons.style_outlined,
      label: '单词复习',
      activator: SingleActivator(LogicalKeyboardKey.keyR, control: true),
      page: 2,
    ),
    (
      icon: Icons.forum_outlined,
      label: '短语集',
      activator: SingleActivator(LogicalKeyboardKey.keyI, control: true),
      page: 3,
    ),
    (
      icon: Icons.ios_share,
      label: '导出',
      activator: SingleActivator(LogicalKeyboardKey.keyE, control: true),
      page: 5,
    ),
  ];

  /// 提示文案由 activator 派生（如 `Ctrl+F`），不再单独手写。
  static String _hintOf(ShortcutActivator a) {
    if (a is! SingleActivator) return '';
    final label = a.trigger.keyLabel;
    final key = label.length == 1 ? label.toUpperCase() : label;
    return '${a.control ? 'Ctrl+' : ''}$key';
  }

  @override
  void dispose() {
    _shellFocus.dispose();
    super.dispose();
  }

  void _go(int i) {
    setState(() => _page = i);
    // 先把焦点收回外壳：页面在 IndexedStack 里常驻，离开的页不会自动交还焦点，
    // 不收回来则隐藏页继续吃键（空格/数字键落到看不见的卡片上）。
    // 需要自身焦点的页（搜索框 / 复习页）在自己的 didUpdateWidget 里
    // 随后把焦点要走，它们注册的回调晚于本回调。
    _shellFocus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_shellFocus.hasFocus) _shellFocus.requestFocus();
    });
  }

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
      // 绑定与侧栏提示同源：见 _nav
      bindings: {
        for (final e in _nav) e.activator: () => _go(e.page),
      },
      child: Focus(
        focusNode: _shellFocus,
        autofocus: true,
        child: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSidebar(context),
              VerticalDivider(width: 1, thickness: 1, color: Theme.of(context).dividerColor),
              Expanded(
                // 页面常驻（maintainState + maintainInteractivity），隐藏页的控件在控件树上
                // 依然存在——焦点安全靠 _go 收回焦点 + 页面自身的 isActive 守卫，
                // 而不是靠隐藏页不可聚焦（曾用 ExcludeFocus，实测它拦不住程序化
                // requestFocus，已按反假测试结论移除）。
                child: IndexedStack(
                  index: _page,
                  children: pages,
                ),
              ),
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
      final e = _nav[i];
      final selected = _page == e.page;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Material(
          color: selected
              ? (isDark ? const Color(0xFF1E3A34) : const Color(0xFFE7F2EF))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _go(e.page),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(children: [
                Icon(e.icon, size: 19,
                    color: selected ? scheme.primary : scheme.outline),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(e.label,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? scheme.primary : text.bodyMedium!.color)),
                ),
                Text(_hintOf(e.activator),
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
          for (var i = 0; i < _nav.length; i++) ...[
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
