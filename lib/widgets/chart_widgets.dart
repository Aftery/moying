import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import '../data/statistics.dart';

/// 环形图（类型占比/评分分布通用）
///
/// 纯 CustomPainter 实现，无第三方依赖。空数据时显示灰色圆环 + 中央提示。
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.percentages,
    required this.labels,
    required this.centerText,
    this.size = 120,
    this.strokeWidth = 15,
  });

  /// 各扇区占比（0.0~1.0）
  final List<double> percentages;
  /// 各扇区名称（图例用）
  final List<String> labels;
  /// 中央文字
  final String centerText;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (percentages.isEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              segments: const [],
              strokeWidth: strokeWidth,
              trackColor: colors.surfaceHigh,
            ),
          ),
          Text(centerText,
              style: TextStyle(fontSize: 14, color: colors.textMuted)),
        ]),
      );
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(
          size: Size(size, size),
          painter: _RingPainter(
            segments: percentages,
            strokeWidth: strokeWidth,
            trackColor: colors.surfaceHigh,
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(centerText,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary)),
          ],
        ),
      ]),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.segments,
    required this.strokeWidth,
    required this.trackColor,
  });

  final List<double> segments;
  final double strokeWidth;
  final Color trackColor;

  // 固定色板（与深浅主题均协调）
  static const _colors = [
    Color(0xFF7C8CF8),
    Color(0xFF764BA2),
    Color(0xFF11998E),
    Color(0xFFFFC94D),
    Color(0xFFFFB020),
    Color(0xFF38EF7D),
    Color(0xFF667EEA),
    Color(0xFFFF6B6B),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final total = segments.fold<double>(0, (a, b) => a + b).clamp(1e-9, 1.0);

    // 底色环
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    // 扇区
    var start = -math.pi / 2;
    for (var i = 0; i < segments.length; i++) {
      final sweep = segments[i] / total * 2 * math.pi;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = _colors[i % _colors.length];
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.segments != segments ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.trackColor != trackColor;
}

/// 评分分布柱状图（1~5 星）
class RatingBarChart extends StatelessWidget {
  const RatingBarChart({super.key, required this.distribution, this.height = 120});

  final RatingDistribution distribution;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final counts = [
      distribution.star1,
      distribution.star2,
      distribution.star3,
      distribution.star4,
      distribution.star5,
    ];
    final maxCount = counts.reduce(math.max);
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 5; i++) ...[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${counts[i]}',
                          style: TextStyle(
                              fontSize: 10, color: colors.textMuted),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: maxCount == 0
                              ? 4
                              : (counts[i] / maxCount * (height - 44)),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                colors.readingStart.withOpacity(0.6),
                                colors.readingEnd,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < 4) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < 5; i++) ...[
                Expanded(
                  child: Icon(Icons.star_rounded,
                      size: 13, color: colors.star),
                ),
                if (i < 4) const SizedBox(width: 6),
              ],
            ],
          ),
        ],
      ),
    );
  }
}