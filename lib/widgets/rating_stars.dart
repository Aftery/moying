import 'package:flutter/material.dart';

import '../config/app_palette.dart';

/// 五星评分展示（支持小数，例如 4.2 → 四颗满星 + 一颗部分填充）
class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.size = 14,
    this.color,
    this.showValue = false,
    this.valueStyle,
  });

  /// 评分 0 - 5
  final double rating;

  /// 单颗星尺寸
  final double size;

  /// 星星颜色（null 时用主题功能星色）
  final Color? color;

  /// 是否在星后附带数字（如 “4.2/5”）
  final bool showValue;

  /// 数字样式（默认使用主题 bodySmall 加粗）
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final clamped = rating.clamp(0, 5);
    final starColor = color ?? context.colors.star;
    final fullStars = clamped.floor();
    final hasHalf =
        (clamped - fullStars) >= 0.25 && (clamped - fullStars) < 0.75;
    final nearlyFull = (clamped - fullStars) >= 0.75;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            i < fullStars
                ? Icons.star_rounded
                : (i == fullStars && nearlyFull)
                    ? Icons.star_rounded
                    : (i == fullStars && hasHalf)
                        ? Icons.star_half_rounded
                        : Icons.star_outline_rounded,
            size: size,
            color: starColor,
          ),
        if (showValue) ...[
          const SizedBox(width: 6),
          Text(
            '${clamped.toStringAsFixed(1)}/5',
            style: valueStyle ??
                TextStyle(
                  fontSize: size * 0.9,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
          ),
        ],
      ],
    );
  }
}
