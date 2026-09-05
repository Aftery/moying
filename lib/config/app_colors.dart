import 'package:flutter/material.dart';

/// 全局色板 —— 「墨影」现代暗色主题
///
/// 统一在此维护颜色，避免散落 magic number。
abstract final class AppColors {
  // ---- 基础背景 ----
  /// 页面主背景（近黑）
  static const Color background = Color(0xFF0F0F0F);

  /// 卡片/表面背景（比背景略亮，参考图 #1A1A2E）
  static const Color surface = Color(0xFF1A1A2E);

  /// 次级表面 / 悬浮层
  static const Color surfaceHigh = Color(0xFF24243A);

  /// 分割线 / 描边
  static const Color outline = Color(0xFF2A2A3E);

  // ---- 文字 ----
  static const Color textPrimary = Color(0xFFF5F5F7);
  static const Color textSecondary = Color(0xFFB0B0C4);
  static const Color textMuted = Color(0xFF7A7A90);

  // ---- 阅读主题色（紫 → 靛蓝渐变）----
  static const Color readingStart = Color(0xFF667EEA);
  static const Color readingEnd = Color(0xFF764BA2);

  // ---- 观影主题色（青绿渐变）----
  static const Color movieStart = Color(0xFF11998E);
  static const Color movieEnd = Color(0xFF38EF7D);

  // ---- 功能色 ----
  static const Color star = Color(0xFFFFC94D);
  static const Color accent = Color(0xFF7C8CF8);
  static const Color success = Color(0xFF3DDC97);

  /// 阅读卡片渐变
  static const LinearGradient readingGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [readingStart, readingEnd],
  );

  /// 观影卡片渐变
  static const LinearGradient movieGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [movieStart, movieEnd],
  );
}

/// 封面占位渐变（按 HSL 色相生成两个相近色，避免网络图片依赖）
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
