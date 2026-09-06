// Lupa 桌面版入口 — 看清词，留住词，归你所有。
// 启动顺序：初始化数据层（配置 + 生词本库）→ 注入 AppState → AppShell。
import 'package:flutter/material.dart';

import 'package:lupa/state/app_state.dart';
import 'package:lupa/theme/lupa_theme.dart';
import 'package:lupa/widgets/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  try {
    await state.init();
  } catch (e) {
    runApp(LupaErrorApp(error: e));
    return;
  }
  runApp(LupaApp(state: state));
}

class LupaApp extends StatelessWidget {
  final AppState state;
  const LupaApp({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: 'Lupa 璐帕',
        debugShowCheckedModeBanner: false,
        theme: lupaLightTheme,
        darkTheme: lupaDarkTheme,
        themeMode: state.themeMode,
        home: AppShell(state: state),
      ),
    );
  }
}

/// 数据层初始化失败（罕见）：给出可操作的错误页，不白屏。
class LupaErrorApp extends StatelessWidget {
  final Object error;
  const LupaErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lupa 璐帕',
      debugShowCheckedModeBanner: false,
      theme: lupaLightTheme,
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('启动失败',
                      style: TextStyle(
                          fontFamily: wordFontFamily, fontSize: 22,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  Text('数据目录初始化出错：\n\n$error',
                      style: const TextStyle(fontSize: 14, height: 1.6)),
                  const SizedBox(height: 12),
                  const Text(
                    '排查：确认 LUPA_HOME 指向含 dict.sqlite 的目录，'
                    '或数据目录（应用旁的 lupa_data/）可写。',
                    style: TextStyle(fontSize: 13, height: 1.6),
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
