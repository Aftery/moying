import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'fade_slide_transitions.dart';

/// 全局主题构建器（按色板生成，暗/浅共用一套结构）
///
/// - [AppPalette.dark] → ColorScheme.dark（原始暗色设计）
/// - [AppPalette.light] → ColorScheme.light（浅色反推）
///
/// 色板经 `extensions` 挂入 ThemeData，widget 内统一用 `context.colors` 取色。
ThemeData buildAppTheme(AppPalette palette) {
  final isDark = palette.background.computeLuminance() < 0.5;
  final colorScheme = isDark
      ? ColorScheme.dark(
          primary: palette.accent,
          secondary: palette.movieEnd,
          surface: palette.surface,
          onPrimary: Colors.white,
          onSurface: palette.textPrimary,
          error: palette.error,
        )
      : ColorScheme.light(
          primary: palette.accent,
          secondary: palette.movieEnd,
          surface: palette.surface,
          onPrimary: Colors.white,
          onSurface: palette.textPrimary,
          error: palette.error,
        );

  return ThemeData(
    useMaterial3: true,
    brightness: isDark ? Brightness.dark : Brightness.light,
    colorScheme: colorScheme,
    extensions: [palette],
    scaffoldBackgroundColor: palette.background,

    // 文字排版
    textTheme: TextTheme(
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: palette.textPrimary,
        letterSpacing: 0.5,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: palette.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: palette.textSecondary,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        color: palette.textMuted,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: palette.textSecondary,
      ),
    ),

    // 卡片默认样式
    cardTheme: CardTheme(
      color: palette.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: palette.textPrimary,
      ),
      iconTheme: IconThemeData(color: palette.textPrimary),
    ),

    // 底部导航
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.surface,
      indicatorColor: palette.accent.withOpacity(0.22),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? palette.textPrimary
              : palette.textMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? palette.accent
              : palette.textMuted,
        ),
      ),
    ),

    // 分割线
    dividerTheme: DividerThemeData(
      color: palette.outline,
      thickness: 1,
    ),

    // 页面转场：淡入 + 微上浮（全局统一，0.28s 生效）
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeSlidePageTransitionsBuilder(),
        TargetPlatform.iOS: FadeSlidePageTransitionsBuilder(),
        TargetPlatform.macOS: FadeSlidePageTransitionsBuilder(),
        TargetPlatform.linux: FadeSlidePageTransitionsBuilder(),
      },
    ),
  );
}
