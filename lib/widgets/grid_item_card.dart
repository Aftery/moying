import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/media_ref.dart';
import 'media_cover.dart';

/// 网格列表卡片（阅读列表 / 电影列表通用）
///
/// 底部一行：书籍 → 状态/评分徽标；电影 → 年份 + 评分星星
class GridItemCard extends StatelessWidget {
  const GridItemCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.hue,
    this.media,
    this.rating,
    this.statusLabel,
    this.onTap,
  });

  /// 主标题
  final String title;

  /// 副标题（作者 / 导演等）
  final String subtitle;

  /// 封面 emoji
  final String emoji;

  /// 封面色相
  final double hue;

  /// 封面图片引用（书 cover / 电影 poster，可选——空则占位）
  final MediaRef? media;

  /// 评分 0-5（可选）
  final double? rating;

  /// 状态标签（在读/已读/想看/已评等）
  final String? statusLabel;

  /// 点击回调
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                MediaCover(
                  media: media,
                  title: title,
                  emoji: emoji,
                  hue: hue,
                  aspectRatio: 3 / 4,
                  borderRadius: 0,
                  fontSize: 40,
                ),
                // 左上角状态徽标
                if (statusLabel != null)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        statusLabel!,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (rating != null) ...[
                        const Icon(
                          Icons.star_rounded,
                          size: 15,
                          color: AppColors.star,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          rating!.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: AppColors.outline,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
