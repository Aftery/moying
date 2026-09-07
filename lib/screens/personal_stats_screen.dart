import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../models/stats.dart';
import '../providers/library_provider.dart';
import '../widgets/progress_ring.dart';

/// 个人统计页 —— 全部数字来自 provider 计算属性，与仪表盘同源实时联动
class PersonalStatsScreen extends StatelessWidget {
  const PersonalStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // H6/M6：select 只订阅本页消费的统计聚合，无关变化不再触发重建
    final b = context.select<LibraryProvider, BookStats>((p) => p.bookStats);
    final m =
        context.select<LibraryProvider, MovieStats>((p) => p.movieStats);
    final planCount =
        context.select<LibraryProvider, int>((p) => p.planToReadBooks.length);

    return Scaffold(
      appBar: AppBar(title: const Text('个人统计')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ---------- 阅读年度大卡 ----------
          _GradientStatCard(
            gradient: context.colors.readingGradient,
            kicker: 'READING',
            headline: '${b.total} 本书',
            sub: '${b.active} 在读 · ${b.finished} 读完',
            center: ProgressRing(
              progress: b.progress,
              size: 84,
              strokeWidth: 7,
              trackColor: Colors.white.withOpacity(0.22),
              colors: const [Colors.white, Color(0xFFD9DEFF)],
              label: '${(b.progress * 100).round()}%',
              labelColor: Colors.white,
            ),
            centerCaption: '平均进度',
            details: [
              ('想读', '$planCount 本'),
              ('已读', '${b.pagesRead} 页'),
            ],
          ),
          const SizedBox(height: 16),

          // ---------- 观影年度大卡 ----------
          _GradientStatCard(
            gradient: context.colors.movieGradient,
            kicker: 'WATCHING',
            headline: '${m.total} 部',
            sub: '${m.watchlist} 想看 · ${m.rated} 已评',
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  m.averageRating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const Text(
                  '平均评分 / 5',
                  style: TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
            centerCaption: null,
            details: [
              ('想看', '${m.watchlist} 部'),
              ('已评', '${m.rated} 部'),
            ],
          ),
          const SizedBox(height: 16),

          // ---------- 四格总览 ----------
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCell(value: '${b.finished}', label: '读完书籍'),
                _StatCell(value: '${m.rated}', label: '看过电影'),
                _StatCell(value: '${b.pagesRead}', label: '阅读页数'),
                _StatCell(value: '${m.total}', label: '观影总数'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '数据与书影库实时同步 · 清空记录后归零',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: context.colors.textMuted.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

/// 渐变统计大卡（个人统计页专用，与仪表盘 StatsCard 同视觉语言）
class _GradientStatCard extends StatelessWidget {
  const _GradientStatCard({
    required this.gradient,
    required this.kicker,
    required this.headline,
    required this.sub,
    required this.center,
    required this.centerCaption,
    required this.details,
  });

  final Gradient gradient;
  final String kicker;
  final String headline;
  final String sub;
  final Widget center;
  final String? centerCaption;
  final List<(String, String)> details;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kicker,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 2.2,
              fontWeight: FontWeight.w700,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            headline,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: const TextStyle(fontSize: 12.5, color: Colors.white),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Spacer(),
              center,
              const Spacer(),
            ],
          ),
          if (centerCaption != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Spacer(),
                Text(
                  centerCaption!,
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white70),
                ),
                const Spacer(),
              ],
            ),
          ],
          const SizedBox(height: 16),
          for (var i = 0; i < details.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _detailRow(details[i].$1, details[i].$2),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
        const SizedBox(width: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11.5,
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: context.colors.accent,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.colors.textMuted),
        ),
      ],
    );
  }
}
