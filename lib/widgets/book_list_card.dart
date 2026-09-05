import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import '../models/book.dart';
import 'media_cover.dart';
import 'rating_stars.dart';

/// 图书列表卡片（图书模块双排网格用）
///
/// 视觉对齐参考图：竖版封面 + 左上状态徽标 + 右下进度角标；
/// 下方信息区为标题/作者/星级与直观的渐变进度条。
/// 单击查看详情，长按唤起编辑。
class BookListCard extends StatelessWidget {
  const BookListCard({
    super.key,
    required this.book,
    this.onTap,
    this.onLongPress,
  });

  final Book book;

  /// 单击回调（查看详情）
  final VoidCallback? onTap;

  /// 长按回调（编辑）
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final finished = book.status == BookStatus.finished;

    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---------- 封面区 ----------
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MediaCover(
                    media: book.cover,
                    title: book.title,
                    emoji: book.emoji ?? '',
                    hue: book.coverHue,
                    aspectRatio: 3 / 4,
                    borderRadius: 0,
                    fontSize: 40,
                  ),
                  // 左上角状态徽标
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _StatusBadge(status: book.status),
                  ),
                  // 右下角进度角标（未读完才显示，读完有独立进度条状态）
                  if (!finished)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: _PercentBadge(percent: book.progressPercent),
                    ),
                ],
              ),
            ),
            // ---------- 信息区 ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
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
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:  TextStyle(
                      fontSize: 11,
                      color: context.colors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 星级 + 百分比进度
                  Row(
                    children: [
                      if (book.rating != null)
                        RatingStars(rating: book.rating!, size: 14)
                      else
                         Text(
                          '未评分',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textMuted,
                          ),
                        ),
                      const Spacer(),
                      Text(
                        '${book.progressPercent}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: finished
                              ? context.colors.success
                              : context.colors.readingStart,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 渐变进度条
                  _GradientBar(
                    progress: book.progress,
                    color:
                        finished ? context.colors.success : context.colors.readingStart,
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

/// 左上角阅读状态徽标
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final BookStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      BookStatus.reading => context.colors.readingStart,
      BookStatus.finished => context.colors.success,
      BookStatus.planToRead => context.colors.accent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.92),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// 右下角小百分比角标（黑底半透明）
class _PercentBadge extends StatelessWidget {
  const _PercentBadge({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$percent%',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// 渐变进度条（底部信息区，宽度撑满）
class _GradientBar extends StatelessWidget {
  const _GradientBar({required this.progress, required this.color});

  final double progress;

  /// 已完成时用 success，否则用阅读主题色
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 5,
      decoration: BoxDecoration(
        color: context.colors.outline,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: progress.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withOpacity(0.65)],
            ),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}
