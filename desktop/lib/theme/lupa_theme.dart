// Lupa 主题 — 「纸感 + 玉色」设计 token 的 Flutter 落地。
// 与《Lupa 桌面版 UI 设计方案》对齐：暖砂底 + 玉青单强调色，衬线字体仅用于词条标题。
// 文本色为 WCAG AA 校准值（tx1/tx2/tx3 = 17.2 / 7.8 / 4.8:1）。
import 'package:flutter/material.dart';

/// 设计 token（与原型 HTML 一致）
class LupaColors {
  LupaColors._();

  // ---- light ----
  static const bgLight = Color(0xFFF7F6F3); // 暖砂底
  static const surfaceLight = Color(0xFFFFFFFF);
  static const borderLight = Color(0xFFE4E2DD);
  static const tx1Light = Color(0xFF191C19);
  static const tx2Light = Color(0xFF4F544E);
  static const tx3Light = Color(0xFF6E736D);

  // ---- dark ----
  static const bgDark = Color(0xFF1C1E1C);
  static const surfaceDark = Color(0xFF242724);
  static const borderDark = Color(0xFF33362F);
  static const tx1Dark = Color(0xFFECEDEA);
  static const tx2Dark = Color(0xFFB7BBB4);
  static const tx3Dark = Color(0xFF9BA09A);

  // ---- accent（玉青，「璐」本义美玉）----
  static const jade = Color(0xFF0E7C6B);
  static const jadeDark = Color(0xFF4DC2AB); // 深色主题下提亮保对比度
  static const jadeSoftLight = Color(0xFFE7F2EF); // 选中态浅底
  static const jadeSoftDark = Color(0xFF1E3A34);
  static const onJadeLight = Color(0xFFFFFFFF);
  static const onJadeDark = Color(0xFF0F2C26);

  // ---- semantic（设计稿 3.1 语义色；深色取提亮值保对比度）----
  static const dangerLight = Color(0xFFB3452E);
  static const dangerDark = Color(0xFFE08D77);
  static const successLight = Color(0xFF1F7A4D);
  static const successDark = Color(0xFF5DBE8E);
  static const warningLight = Color(0xFFA96008); // 柯林斯星级徽章
  static const warningDark = Color(0xFFE0A34A);
  static const violetLight = Color(0xFF5B4FCF); // 牛津 3000 徽章
  static const violetDark = Color(0xFFA99BF0);
  static const infoLight = Color(0xFF3C5BA9); // CSV / 提示
  static const infoDark = Color(0xFF7FA3E0);
}

/// 词条标题用衬线（Windows 自带 Georgia）——全站唯一"装饰"。
const String wordFontFamily = 'Georgia';

ThemeData _buildLupaTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final bg = isDark ? LupaColors.bgDark : LupaColors.bgLight;
  final surface = isDark ? LupaColors.surfaceDark : LupaColors.surfaceLight;
  final border = isDark ? LupaColors.borderDark : LupaColors.borderLight;
  final tx1 = isDark ? LupaColors.tx1Dark : LupaColors.tx1Light;
  final tx2 = isDark ? LupaColors.tx2Dark : LupaColors.tx2Light;
  final tx3 = isDark ? LupaColors.tx3Dark : LupaColors.tx3Light;
  final accent = isDark ? LupaColors.jadeDark : LupaColors.jade;
  final onAccent = isDark ? LupaColors.onJadeDark : LupaColors.onJadeLight;
  final danger = isDark ? LupaColors.dangerDark : LupaColors.dangerLight;

  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: accent,
        onPrimary: onAccent,
        secondary: accent,
        onSecondary: onAccent,
        surface: surface,
        onSurface: tx1,
        error: danger,
        onError: Colors.white,
        outline: border,
        surfaceContainerHighest: isDark ? const Color(0xFF2B2E2B) : const Color(0xFFEFEEE9),
      );

  OutlineInputBorder box(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: w),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    dividerColor: border,
    iconTheme: IconThemeData(color: tx2, size: 20),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: tx1, fontSize: 15, height: 1.55),
      bodyMedium: TextStyle(color: tx2, fontSize: 14, height: 1.5),
      bodySmall: TextStyle(color: tx3, fontSize: 12.5, height: 1.45),
      titleLarge: TextStyle(color: tx1, fontSize: 18, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: tx1, fontSize: 15.5, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(color: tx3, fontSize: 11),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: TextStyle(color: tx3),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: box(border),
      enabledBorder: box(border),
      focusedBorder: box(accent, 1.6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tx2,
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: accent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? LupaColors.surfaceDark : LupaColors.tx1Light,
      contentTextStyle: TextStyle(
        color: isDark ? LupaColors.tx1Dark : LupaColors.bgLight,
        fontSize: 13.5,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? LupaColors.surfaceDark : LupaColors.tx1Light,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(
        color: isDark ? LupaColors.tx1Dark : LupaColors.bgLight,
        fontSize: 12,
      ),
      waitDuration: const Duration(milliseconds: 500),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titleTextStyle: TextStyle(color: tx1, fontSize: 16, fontWeight: FontWeight.w600),
      contentTextStyle: TextStyle(color: tx2, fontSize: 14, height: 1.5),
    ),
  );
}

ThemeData get lupaLightTheme => _buildLupaTheme(Brightness.light);
ThemeData get lupaDarkTheme => _buildLupaTheme(Brightness.dark);
