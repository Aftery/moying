import 'package:flutter/material.dart';

import '../config/app_palette.dart';

/// 交互式五星评分选择器（编辑页使用）
///
/// - 点击第 N 颗星 → 评分为 N（整数档位）
/// - 再点当前选中的星 → 清除评分（回到 0 = 未评分）
/// - 支持带数字展示
class StarRatingPicker extends StatelessWidget {
  const StarRatingPicker({
    super.key,
    required this.rating,
    required this.onChanged,
    this.size = 34,
  });

  /// 当前评分 0-5（0 表示未评分）
  final double rating;

  /// 评分变化回调（传 0 表示清除）
  final ValueChanged<double> onChanged;

  /// 单颗星尺寸
  final double size;

  @override
  Widget build(BuildContext context) {
    final rounded = rating.round();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          // 触控热区保证 ≥ 44dp（Material 无障碍要求）
          SizedBox(
            width: size + 10,
            height: size + 10,
            child: IconButton(
              padding: EdgeInsets.zero,
              splashRadius: size * 0.6,
              tooltip: '$i 分',
              onPressed: () => onChanged(rounded == i ? 0 : i.toDouble()),
              icon: Icon(
                i <= rounded ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size,
                color: i <= rounded
                    ? context.colors.star
                    : context.colors.textMuted.withOpacity(0.5),
              ),
            ),
          ),
      ],
    );
  }
}
