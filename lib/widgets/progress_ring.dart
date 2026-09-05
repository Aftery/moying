import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_palette.dart';

/// 圆形进度环
///
/// 用 [CustomPainter] 绘制轨道 + 渐变进度弧，并带平滑动画。
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    this.size = 56,
    this.strokeWidth = 5,
    this.colors,
    this.trackColor = const Color(0x33FFFFFF),
    this.label,
    this.labelColor = Colors.white,
  });

  /// 进度 0.0 - 1.0
  final double progress;

  /// 圆环直径
  final double size;

  /// 描边宽度
  final double strokeWidth;

  /// 进度渐变颜色（null 时用主题阅读渐变起止色）
  final List<Color>? colors;

  /// 轨道（底环）颜色
  final Color trackColor;

  /// 中心文字（默认显示百分比）
  final String? label;

  /// 中心文字颜色
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    final text = label ?? '${(clamped * 100).round()}%';
    final ringColors = colors ??
        [context.colors.readingStart, context.colors.readingEnd];

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: clamped),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => CustomPaint(
              size: Size.square(size),
              painter: _RingPainter(
                progress: value,
                strokeWidth: strokeWidth,
                colors: ringColors,
                trackColor: trackColor,
              ),
            ),
          ),
          Text(
            text,
            style: TextStyle(
              fontSize: size * 0.24,
              fontWeight: FontWeight.w700,
              color: labelColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.colors,
    required this.trackColor,
  });

  final double progress;
  final double strokeWidth;
  final List<Color> colors;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const startAngle = -math.pi / 2; // 12 点方向开始
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // 轨道
    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, track);

    // 进度弧
    if (progress <= 0) return;
    final sweep = 2 * math.pi * progress;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweep,
        colors: colors,
      ).createShader(rect);
    canvas.drawArc(rect, startAngle, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.colors != colors ||
      old.strokeWidth != strokeWidth;
}
