// 界面前景色对比度审计（openspec change fix-ui-contrast-and-reachability 任务 4.1）。
//
// 为什么要有这个文件：`scheme.outline` 被映射到**边框色**（浅 #E4E2DD 对白底
// 1.29:1、深 #33362F 对 #242724 1.23:1）。它只看「与底色可区分」就够了，但被
// 当成文字/图标前景色时等于不可见 —— 这类 bug 是视觉层的，却可机械化验证。
// 本项目上一轮（add-ai-word-enrichment）已用同一手法在 AI 区域抓到过它，
// 本文件把那套审计扩到外壳与三个空状态页。
//
// 三条设计原则（与 test/ai_text_contrast_test.dart 一致）：
//   1) 不断言「颜色等于某值」（改个色号就碎），而是按 WCAG 2.x 公式算对比度。
//   2) 文字 4.5:1、图标等非文字 UI 组件 3:1（WCAG 2.x AA）。
//   3) 背景色**逐元素**从祖先解析，不用全场景常量 —— 否则按钮/卡片这类自带
//      底色的控件会误报（白字配玉青底被拿去和白底比 → 假失败）。
//
// **断言边界（重要）**：本文件守住的是「本次修复涉及的站点全部达标」，而不是
// 「全应用所有文字都达标」—— 后者在浅色主题下今天**不成立**（实测 15 处，分布在
// 4 个 (前景, 背景) 组合上，全部是既有问题）。这 4 类在 `_exceptionsFor` 里**逐条
// 显式登记**（带实测值与来源），并在文件末尾断言「每条登记都必须仍被命中」。
// 因此：
//   * 新增违例 → 红（不会被静默放过）；
//   * 登记过的例外被修好 → 红（催你删掉那条登记，清单不会靡烂）；
//   * 例外的色值漂移 → 红（催你重新评估那条豁免）。
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lupa/data/config.dart';
import 'package:lupa/data/data_home.dart';
import 'package:lupa/data/notebook_db.dart';
import 'package:lupa/pages/notebook_page.dart';
import 'package:lupa/pages/phrase_page.dart';
import 'package:lupa/pages/search_page.dart';
import 'package:lupa/state/app_state.dart';
import 'package:lupa/theme/lupa_theme.dart';
import 'package:lupa/widgets/app_shell.dart';

// ---------------------------------------------------------------------------
// WCAG 2.x
// ---------------------------------------------------------------------------

/// 相对亮度。
///
/// 注意是 **2.4 次幂**，不是平方 —— 写成平方会让所有对比度算成偏小值从而误报
/// （`ai_text_contrast_test.dart` 的第一版踩过这个坑）。Flutter 的 Color.r/g/b
/// 已归一化到 0..1，且是 sRGB 编码值（不是线性值）。
double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// WCAG 对比度（1..21）。
double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

// ---------------------------------------------------------------------------
// 前景 / 背景解析
// ---------------------------------------------------------------------------

/// 元素的实际背景色：从它往上找**最近的不透明底色**。
///
/// 认三种载体：`Material.color`、`ColoredBox.color`、`DecoratedBox` 的
/// `BoxDecoration.color`（`Container` 会展开成后两者之一）。透明（a == 0）
/// 的跳过 —— 侧栏未选中项正是 `Material(color: Colors.transparent)`，
/// 它不该被当成自己的底色。
Color? _bgOf(Element e) {
  Color? found;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Material && w.color != null && w.color!.a >= 0.99) {
      found = w.color;
      return false;
    }
    if (w is ColoredBox && w.color.a >= 0.99) {
      found = w.color;
      return false;
    }
    if (w is DecoratedBox) {
      final d = w.decoration;
      if (d is BoxDecoration && d.color != null && d.color!.a >= 0.99) {
        found = d.color;
        return false;
      }
    }
    return true;
  });
  return found;
}

/// 元素是否处于**禁用**控件内（WCAG 不要求非激活控件满足对比度）。
bool _isDisabled(Element e) {
  var disabled = false;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is ButtonStyleButton && w.onPressed == null && w.onLongPress == null) {
      disabled = true;
      return false;
    }
    if (w is IconButton && w.onPressed == null) {
      disabled = true;
      return false;
    }
    // 其余按钮类（TextButton/OutlinedButton/FilledButton）都是 ButtonStyleButton 子类
    return true;
  });
  return disabled;
}

// ---------------------------------------------------------------------------
// 审计
// ---------------------------------------------------------------------------

/// 一条**已知、本次不修**的既有例外（浅色主题）。
///
/// 为什么用「登记 + 必须命中」而不是直接放宽阈值：本文件末尾的用例要求每条登记
/// 都真的被命中过，所以既不会静默扩大例外，也不会留下已经失效的条目。
///
/// 来源：
///  * **E1** —— proposal「顺延」节已明确接受：`tx3` 在**页面底色**（非卡片底色）上
///    4.48:1，比正文阈值低 0.02；主题是按卡片底色 surface 校准的。
///  * **E2/E3/E4** —— 本次对比度审计**新发现**，已登记到 design / proposal 的
///    「顺延」节，留给后续独立变更。三处都属本 change 的非目标
///    （「不重做配色方案…tx1/tx2/tx3 不动」），其中 E3/E4 要动的正是任务 2.1
///    要求「选中态保持 primary」与高亮 chip 底色那一支。
typedef _Exception = ({String id, Color fg, Color bg, double ratio, String why});

/// 浅色主题的已登记例外；深色主题实测**零违例**，因此为空。
List<_Exception> _exceptionsFor(ThemeData theme) {
  if (theme.brightness == Brightness.dark) return const [];
  return [
    (
      id: 'E1',
      fg: LupaColors.tx3Light,
      bg: LupaColors.bgLight,
      ratio: 4.48,
      why: 'tx3 在页面底色上（proposal「顺延」已接受）'
    ),
    (
      id: 'E2',
      fg: LupaColors.tx3Light,
      bg: theme.colorScheme.surfaceContainerHighest,
      ratio: 4.17,
      why: '「词频」徽章（tag_chip 的 freq / plain）'
    ),
    (
      id: 'E3',
      fg: LupaColors.jade,
      bg: LupaColors.jadeSoftLight,
      ratio: 4.46,
      why: '侧栏选中态导航项（评审要求保持 primary）'
    ),
    (
      id: 'E4',
      fg: LupaColors.tx3Light,
      bg: LupaColors.jadeSoftLight,
      ratio: 4.23,
      why: '高亮统计 chip「今日到期」'
    ),
  ];
}

/// 本次运行中被命中过的例外 id（供文件末尾的「清单不得靡烂」用例检查）。
final Set<String> _hits = <String>{};

/// 审计当前渲染树中所有可见文字与图标。
///
/// 一次收集**全部**违例再断言，这样失败信息能列出所有站点（而不是只报第一处）。
/// 命中 [exceptions] 的违例不算失败，但会被记入 [_hits] 并标注在输出里。
void _audit(WidgetTester tester,
    {required String where, List<_Exception> exceptions = const []}) {
  final unexpected = <String>[];
  final lines = <String>[];
  var nText = 0, nIcon = 0, nSkipped = 0;

  void judge(Element e, Color? fg, double min, String what) {
    if (fg == null || fg.a < 0.99) {
      nSkipped++;
      return;
    }
    if (_isDisabled(e)) {
      nSkipped++;
      return;
    }
    final bg = _bgOf(e);
    if (bg == null) {
      unexpected.add('$what：找不到背景色（无法审计）');
      return;
    }
    final r = _contrast(fg, bg);
    final pair = 'fg=${_hex(fg)} bg=${_hex(bg)}';
    if (r >= min) {
      lines.add('✓ ${r.toStringAsFixed(2)}:1  $what  $pair');
      return;
    }
    _Exception? ex;
    for (final x in exceptions) {
      if (x.fg.toARGB32() == fg.toARGB32() && x.bg.toARGB32() == bg.toARGB32()) {
        ex = x;
        break;
      }
    }
    if (ex == null) {
      unexpected.add('$what  $pair = ${r.toStringAsFixed(2)}:1 < $min:1');
      lines.add('✗ ${r.toStringAsFixed(2)}:1  $what  $pair');
      return;
    }
    _hits.add(ex.id);
    final drifted = (r - ex.ratio).abs() > 0.02;
    lines.add('${drifted ? '!' : '~'} ${r.toStringAsFixed(2)}:1  $what  $pair'
        '  ← 已登记例外 ${ex.id}（记录 ${ex.ratio.toStringAsFixed(2)}:1，${ex.why}）');
    if (drifted) {
      unexpected.add('已登记例外 ${ex.id} 的实测值从 '
          '${ex.ratio.toStringAsFixed(2)}:1 变为 ${r.toStringAsFixed(2)}:1'
          ' —— 该豁免条款需重新评估（$what）');
    }
  }

  for (final e in find.byType(Text).evaluate()) {
    final w = e.widget as Text;
    final fg = w.style?.color ?? DefaultTextStyle.of(e).style.color;
    final label = (w.data ?? w.textSpan?.toPlainText() ?? '').trim();
    nText++;
    judge(e, fg, 4.5, '文字「${label.length > 24 ? '${label.substring(0, 24)}…' : label}」');
  }

  for (final e in find.byType(Icon).evaluate()) {
    final w = e.widget as Icon;
    // Icon 的 color 为 null 时实际取的是祖先 IconTheme 的值（主题里是 tx2）。
    final fg = w.color ?? IconTheme.of(e).color;
    nIcon++;
    judge(e, fg, 3.0, '图标 ${w.icon?.codePoint ?? w.icon} ${w.size ?? ''}px');
  }

  expect(nText + nIcon, greaterThan(0), reason: '$where：没有审计到任何元素（用例失效）');
  expect(unexpected, isEmpty,
      reason: '$where：${unexpected.length} 处前景色未达阈值且不在已登记例外内'
          '（文字 4.5:1 / 图标 3:1）；未解析到背景而被跳过 $nSkipped 处\n'
          '${unexpected.join('\n')}\n--- 全部受检项 ---\n${lines.join('\n')}');
}

// ---------------------------------------------------------------------------
// 夹具
// ---------------------------------------------------------------------------

Directory _tmp(String tag) => Directory(p.join(
    Directory.systemTemp.path,
    'lupa_contrast_${tag}_${DateTime.now().microsecondsSinceEpoch}'))
  ..createSync(recursive: true);

/// 建一个最小 `dict.sqlite`（只建 `dict` 表 + 一条词条）。
///
/// 这样「收藏星标」这类需要**词库命中**才渲染的站点不依赖外部 `LUPA_HOME`
/// （否则 CI 上会静默跳过，等于没测）。
Future<void> _writeFakeDict(String dir) async {
  initDatabaseFactory(); // 幂等；本函数跑在 AppState.init() 之前，得自己先初始化
  final db = await databaseFactory
      .openDatabase(p.absolute(p.join(dir, 'dict.sqlite')));
  await db.execute('''
CREATE TABLE dict (
  word TEXT, sw TEXT, phonetic TEXT, definition TEXT, translation TEXT,
  pos TEXT, collins INTEGER, oxford INTEGER, tag TEXT, bnc INTEGER,
  frq INTEGER, exchange TEXT, audio TEXT
)''');
  await db.insert('dict', {
    'word': 'abandon',
    'sw': 'abandon',
    'phonetic': 'əˈbændən',
    'definition': 'to leave somebody/something',
    'translation': 'vt. 放弃；抛弃\nn. 放任',
    'pos': 'v:1/n:1',
    'collins': 3,
    'oxford': 1,
    'tag': 'zk cet4',
    'bnc': 1000,
    'frq': 1000,
    'exchange': 'd:abandoned/p:abandoned/i:abandoning/3:abandons',
    'audio': '',
  });
  await db.close();
}

Future<AppState> _initState(Directory cfg, Directory data) async {
  setConfigHomeOverride(cfg.path);
  setDataHomeOverride(data.path);
  File(p.join(cfg.path, configFile)).writeAsStringSync(json.encode({
    'default_provider': 'youdao',
    'providers': {'youdao': {'phonetic_url': 'u', 'tts_url': 't'}},
    'settings': {
      'theme': 'system',
      'ai': {'enabled': false},
    },
  }), encoding: utf8);
  await _writeFakeDict(data.path); // 必须在 state.init() 之前建好
  final state = AppState();
  await state.init();
  return state;
}

void main() {
  late Directory cfg;
  late Directory data;

  setUp(() {
    cfg = _tmp('cfg');
    data = _tmp('data');
  });

  tearDown(() {
    clearConfigHomeOverride();
    clearDataHomeOverride();
    for (final d in [cfg, data]) {
      try {
        if (d.existsSync()) d.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  for (final (themeName, theme) in [
    ('浅色', lupaLightTheme),
    ('深色', lupaDarkTheme),
  ]) {
    Future<AppState> boot(WidgetTester tester) async =>
        (await tester.runAsync(() => _initState(cfg, data)))!;

    void canvas(WidgetTester tester) {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('$themeName：外壳侧栏 + 查词空状态', (tester) async {
      canvas(tester);
      final state = await boot(tester);
      await tester.pumpWidget(MaterialApp(theme: theme, home: AppShell(state: state)));
      await tester.pump();
      // 前提：确认真的渲染出了侧栏与空状态（否则审计的是个空壳）
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('查一个词，看清它'), findsOneWidget);
      _audit(tester,
          where: '$themeName 外壳侧栏 + 查词空状态',
          exceptions: _exceptionsFor(theme));
    });

    testWidgets('$themeName：查词结果卡（含未收藏星标）', (tester) async {
      canvas(tester);
      final state = await boot(tester);
      await tester.pumpWidget(
          MaterialApp(theme: theme, home: Scaffold(body: SearchPage(state: state))));
      await tester.pump();
      await tester.runAsync(() async {
        await tester.enterText(find.byType(TextField).first, 'abandon');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();
      // 前提：词库命中且星标处于**未收藏**态（未收藏才是本 change 修的那一支）
      expect(find.text('abandon'), findsWidgets);
      expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      _audit(tester,
          where: '$themeName 查词结果卡（未收藏星标）',
          exceptions: _exceptionsFor(theme));
    });

    testWidgets('$themeName：生词本空状态', (tester) async {
      canvas(tester);
      final state = await boot(tester);
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
              body: NotebookPage(state: state, onGotoReview: () {}))));
      await tester.pump();
      expect(find.text('生词本还是空的'), findsOneWidget);
      _audit(tester,
          where: '$themeName 生词本空状态', exceptions: _exceptionsFor(theme));
    });

    testWidgets('$themeName：短语集空状态', (tester) async {
      canvas(tester);
      final state = await boot(tester);
      await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
              body: PhrasePage(
                  state: state, isActive: true, onGotoReview: () {}))));
      await tester.pump();
      expect(find.text('短语集还是空的'), findsOneWidget);
      _audit(tester,
          where: '$themeName 短语集空状态', exceptions: _exceptionsFor(theme));
    });
  }

  // ---- 根因 token 的下限（不渲染，任何主题改动都绕不过去）----
  for (final (themeName, theme) in [
    ('浅色', lupaLightTheme),
    ('深色', lupaDarkTheme),
  ]) {
    test('$themeName：弱化前景色 token（onSurfaceVariant）对两种底色都达文字阈值', () {
      final scheme = theme.colorScheme;
      for (final bg in [
        theme.scaffoldBackgroundColor,
        scheme.surface,
        scheme.surfaceContainerHighest,
      ]) {
        final r = _contrast(scheme.onSurfaceVariant, bg);
        expect(r, greaterThanOrEqualTo(4.5),
            reason: '$themeName：onSurfaceVariant ${_hex(scheme.onSurfaceVariant)} '
                '对 ${_hex(bg)} 只有 ${r.toStringAsFixed(2)}:1');
      }
    });

    test('$themeName：描边色 outline 不得被当作前景色（远低于任何阈值）', () {
      final scheme = theme.colorScheme;
      final r = _contrast(scheme.outline, scheme.surface);
      expect(r, lessThan(3.0),
          reason: '$themeName：outline ${_hex(scheme.outline)} 对 surface '
              '已有 ${r.toStringAsFixed(2)}:1 —— 若它变了，'
              '「不得当前景色」这条前提要重新评估；'
              '注意 theme.border 常量 ${_hex(LupaColors.borderLight)} / '
              '${_hex(LupaColors.borderDark)} 才是描边的定义值');
      // 显式映射后 outline 必须仍是描边色（不是被顺手改成了深色）
      expect(scheme.outline.toARGB32(),
          (theme.brightness == Brightness.dark
                  ? LupaColors.borderDark
                  : LupaColors.borderLight)
              .toARGB32());
    });
  }

  // ---- 允许清单自身的守门员 ----
  // 放在文件末尾（Dart 同文件内的用例按声明顺序跑）：前一组用例全部跑完后再查。
  test('允许清单不得腐烂：每条已登记例外都必须仍被命中', () {
    final expected = _exceptionsFor(lupaLightTheme).map((e) => e.id).toList()
      ..sort();
    final actual = _hits.toList()..sort();
    expect(actual, expected,
        reason: '实际命中 $_hits，期望 $expected。'
            '有登记未被命中 = 该处颜色已达标/站点已消失 —— 请从 _exceptionsFor 里删掉它；'
            '有命中未登记 = 有人加了新豁免却没写进清单。');
  });
}
