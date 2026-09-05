import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import '../models/media_ref.dart';
import 'media_cover.dart';

/// 当前任务横向卡片
///
/// 支持展示“在读的书”（带进度条）或“想看的电影”（带年份/类型标记）。
class MediaTile extends StatelessWidget {
  const MediaTile.book({
    super.key,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.pageText,
    required this.emoji,
    required this.hue,
    this.media,
  })  : rating = null,
        isBook = true;

  const MediaTile.movie({
    super.key,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.hue,
    this.rating,
    this.media,
  })  : progress = null,
        pageText = null,
        isBook = false;

  final String title;
  final String subtitle;
  final double? progress;
  final String? pageText;
  final String emoji;
  final double hue;
  final double? rating;
  final bool isBook;

  /// 封面图片引用（书 cover / 电影 poster，可选——空则占位）
  final MediaRef? media;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面区
          Padding(
            padding: const EdgeInsets.all(8),
            child: MediaCover(
              media: media,
              title: title,
              emoji: emoji,
              hue: hue,
              aspectRatio: 1 / 1.05,
              borderRadius: 12,
              fontSize: 34,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:  TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:  TextStyle(
                    fontSize: 11,
                    color: context.colors.textMuted,
                  ),
                ),
                const SizedBox(height: 8),
                if (isBook && progress != null)
                  Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 5,
                          backgroundColor: context.colors.outline,
                          valueColor:  AlwaysStoppedAnimation<Color>(
                            context.colors.readingStart,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (pageText != null)
                        SizedBox(
                          width: double.infinity,
                          child: Text(
                            pageText!,
                            style:  TextStyle(
                              fontSize: 10,
                              color: context.colors.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                if (isBook && rating != null)
                  Row(
                    children: [
                       Icon(
                        Icons.star_rounded,
                        size: 13,
                        color: context.colors.star,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        rating!.toStringAsFixed(1),
                        style:  TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
