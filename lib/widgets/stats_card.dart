import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import '../models/stats.dart';
import 'progress_ring.dart';

/// 统计卡片展示类型
enum StatsCardType { reading, movie }

/// 仪表盘顶部统计卡片（参考图 Reading / Watching 双卡）
///
/// 数据来自 [LibraryProvider] 实时聚合的 [BookStats] / [MovieStats]，不再依赖 mock。
///
/// - [bookStats] / [movieStats]：两个统计聚合（构造时都必传，由 [type] 决定显示哪张）
/// - [planToReadCount]：书模块「想读」本数（来自 provider.planToReadBooks.length，
///   与 stats 解耦——stats 只承载纯聚合数字，书/影交叉指标由调用方传入）
class StatsCard extends StatelessWidget {
  const StatsCard({
    super.key,
    required this.type,
    required this.bookStats,
    required this.movieStats,
    required this.planToReadCount,
  });

  final StatsCardType type;
  final BookStats bookStats;
  final MovieStats movieStats;
  final int planToReadCount;

  @override
  Widget build(BuildContext context) {
    final isReading = type == StatsCardType.reading;
    final gradient =
        isReading ? context.colors.readingGradient : context.colors.movieGradient;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
      ),
      // 按 type 分发到对应构建器（参数不同，避免 build 内分支 import）
      child: isReading
          ? _buildReading(bookStats, planToReadCount)
          : _buildMovie(movieStats),
    );
  }

  // ---- 阅读卡片 ----
  Widget _buildReading(BookStats stats, int planToReadCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardKicker(text: 'READING'),
        const SizedBox(height: 2),
        Text(
          '${stats.total} Books',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${stats.active} Active · ${stats.finished} Finished',
          style: _subStyle,
        ),
        const SizedBox(height: 14),
        // 进度环上方小标注「平均进度」—— 区分未来其他可能的进度环
        const Row(
          children: [
            Spacer(),
            Text(
              '平均进度',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
            Spacer(),
          ],
        ),
        Row(
          children: [
            const Spacer(),
            ProgressRing(
              progress: stats.progress,
              size: 56,
              strokeWidth: 5,
              trackColor: Colors.white.withOpacity(0.22),
              colors: const [Colors.white, Color(0xFFD9DEFF)],
              // 不传 label：ProgressRing 默认显示「百分比」
              labelColor: Colors.white,
            ),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 14),
        // 明细行整宽排布（窄屏双卡并排也不会溢出）
        _detailRow('想读', '$planToReadCount 本'),
        const SizedBox(height: 4),
        _detailRow('已读', '${stats.pagesRead} 页'),
      ],
    );
  }

  // ---- 电影卡片 ----
  Widget _buildMovie(MovieStats stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CardKicker(text: 'WATCHING'),
        const SizedBox(height: 2),
        Text(
          '${stats.total} Movies',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${stats.watchlist} Watchlist · ${stats.rated} Rated',
          style: _subStyle,
        ),
        const SizedBox(height: 14),
        // 均分徽章上方小标注——与阅读卡「平均进度」行镜像，保证双卡等高对齐
        const Row(
          children: [
            Spacer(),
            Text(
              '平均评分',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
            Spacer(),
          ],
        ),
        Row(
          children: [
            const Spacer(),
            _AvgScoreBadge(score: stats.averageRating),
            const Spacer(),
          ],
        ),
        const SizedBox(height: 14),
        // 明细行整宽排布（窄屏双卡并排也不会溢出）
        _detailRow('想看', '${stats.watchlist} 部'),
        const SizedBox(height: 4),
        _detailRow('已评', '${stats.rated} 部'),
      ],
    );
  }

  TextStyle get _subStyle => const TextStyle(
        fontSize: 12,
        color: Colors.white,
        fontWeight: FontWeight.w400,
        decoration: TextDecoration.none,
      );

  Widget _detailRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 卡片顶部小标签（如 READING / WATCHING）
class _CardKicker extends StatelessWidget {
  const _CardKicker({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// 平均分圆徽章（大数字 + 满分分母）
class _AvgScoreBadge extends StatelessWidget {
  const _AvgScoreBadge({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.16),
        border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
      ),
      child: Center(
        child: Text.rich(
          TextSpan(
            text: score.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            children: const [
              TextSpan(
                text: '/5',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}