import 'package:flutter/material.dart';

/// 全局色板（随主题切换）
///
/// [AppPalette.dark] 为「墨影」原始暗色设计；[AppPalette.light] 为其浅色反推：
/// 背景近白、surface 纯白、文字深灰；品牌渐变（阅读紫 / 观影青）与功能色两套共用，
/// 渐变卡上的白字在两种主题下对比度均足够。
///
/// 取色一律走 `context.colors.xxx`（见 [AppPaletteContext]）——
/// 底层是 Theme.of 依赖，主题切换时全树自动重绘；
/// 禁止再引用静态常量色（切换后 const 子树不会重绘）。
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.readingStart,
    required this.readingEnd,
    required this.movieStart,
    required this.movieEnd,
    required this.star,
    required this.accent,
    required this.success,
    this.danger = const Color(0xFFFF6B6B),
    this.warning = const Color(0xFFFFB020),
    this.error = const Color(0xFFFF6B6B),
  });

  // ---- 基础背景 ----
  /// 页面主背景
  final Color background;

  /// 卡片/表面背景
  final Color surface;

  /// 次级表面 / 悬浮层
  final Color surfaceHigh;

  /// 分割线 / 描边
  final Color outline;

  // ---- 文字 ----
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // ---- 阅读主题色（紫 → 靛蓝渐变）----
  final Color readingStart;
  final Color readingEnd;

  // ---- 观影主题色（青绿渐变）----
  final Color movieStart;
  final Color movieEnd;

  // ---- 功能色 ----
  final Color star;
  final Color accent;
  final Color success;
  final Color danger; // 危险/删除用红
  final Color warning; // 警告用黄
  final Color error; // 错误态用红（区别于 success 绿）

  /// 阅读卡片渐变
  LinearGradient get readingGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [readingStart, readingEnd],
      );

  /// 观影卡片渐变
  LinearGradient get movieGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [movieStart, movieEnd],
      );

  /// 暗色板（原始设计，默认外观）
  static const AppPalette dark = AppPalette(
    background: Color(0xFF0F0F0F),
    surface: Color(0xFF1A1A2E),
    surfaceHigh: Color(0xFF24243A),
    outline: Color(0xFF2A2A3E),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFFB0B0C4),
    textMuted: Color(0xFF7A7A90),
    readingStart: Color(0xFF667EEA),
    readingEnd: Color(0xFF764BA2),
    movieStart: Color(0xFF11998E),
    movieEnd: Color(0xFF38EF7D),
    star: Color(0xFFFFC94D),
    accent: Color(0xFF7C8CF8),
    success: Color(0xFF3DDC97),
    danger: Color(0xFFFF6B6B),
    warning: Color(0xFFFFB020),
    error: Color(0xFFFF5252),
  );

  /// 浅色板（暗色反推：近白背景 + 深灰文字；品牌渐变与功能色保持一致）
  static const AppPalette light = AppPalette(
    background: Color(0xFFF7F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF0F0F5),
    outline: Color(0xFFE4E4EC),
    textPrimary: Color(0xFF1A1A2E),
    textSecondary: Color(0xFF565672),
    textMuted: Color(0xFF9A9AAE),
    readingStart: Color(0xFF667EEA),
    readingEnd: Color(0xFF764BA2),
    movieStart: Color(0xFF11998E),
    movieEnd: Color(0xFF38EF7D),
    star: Color(0xFFFFC94D),
    accent: Color(0xFF6B7BE8),
    success: Color(0xFF2BBF84),
    danger: Color(0xFFE53935),
    warning: Color(0xFFFFA000),
    error: Color(0xFFD32F2F),
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? outline,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? readingStart,
    Color? readingEnd,
    Color? movieStart,
    Color? movieEnd,
    Color? star,
    Color? accent,
    Color? success,
    Color? danger,
    Color? warning,
    Color? error,
  }) {
    return AppPalette(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      outline: outline ?? this.outline,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      readingStart: readingStart ?? this.readingStart,
      readingEnd: readingEnd ?? this.readingEnd,
      movieStart: movieStart ?? this.movieStart,
      movieEnd: movieEnd ?? this.movieEnd,
      star: star ?? this.star,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      error: error ?? this.error,
    );
  }

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceHigh: Color.lerp(surfaceHigh, other.surfaceHigh, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      readingStart: Color.lerp(readingStart, other.readingStart, t)!,
      readingEnd: Color.lerp(readingEnd, other.readingEnd, t)!,
      movieStart: Color.lerp(movieStart, other.movieStart, t)!,
      movieEnd: Color.lerp(movieEnd, other.movieEnd, t)!,
      star: Color.lerp(star, other.star, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
    );
  }
}

/// `context.colors` —— 当前主题色板取色入口
extension AppPaletteContext on BuildContext {
  /// 当前生效色板（依赖 Theme.of，主题切换自动重绘）
  ///
  /// 未挂 [AppPalette] 的环境（如未定制主题的测试壳）回退暗色板。
  AppPalette get colors =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}

/// 封面占位渐变（按 HSL 色相生成两个相近色，不随主题变化——自配色已保证对比）
LinearGradient coverGradient(double hue) {
  final base = HSLColor.fromAHSL(1, hue % 360, 0.42, 0.34);
  final light = base.withLightness(0.44);
  final dark = base.withLightness(0.22);
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [light.toColor(), dark.toColor()],
  );
}
