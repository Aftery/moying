import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../component/theme/app_palette.dart';
import '../model/statistics.dart';
import '../../library/model/book.dart';
import '../../library/model/movie.dart';
import '../../library/view_model/library_provider.dart';
import '../view/chart_view.dart';
import '../../../component/media/cover_placeholder.dart';
import '../view/heatmap_calendar.dart';
import '../view/personal_stats_view.dart';

/// 个人统计页 —— 三段式仪表盘
///
/// 1. 顶部：年度概览指标栏 + GitHub 风格打卡热力图（30天/季度/年度切换）
/// 2. 中部：类型偏好环形图 + 评分分布柱状图
/// 3. 底部：在读进度条（3 本 + 查看全部）+ 年度五星封面墙 + 年报入口
///
/// 全部数字来自 provider 计算属性，与仪表盘同源实时联动。
class PersonalStatsPage extends StatefulWidget {
  const PersonalStatsPage({super.key});

  @override
  State<PersonalStatsPage> createState() => _PersonalStatsPageState();
}

class _PersonalStatsPageState extends State<PersonalStatsPage> {
  HeatmapRange _range = HeatmapRange.month30;

  @override
  Widget build(BuildContext context) {
    final books = context.select<LibraryProvider, List<Book>>((p) => p.books);
    final movies =
        context.select<LibraryProvider, List<Movie>>((p) => p.movieList);

    final now = DateTime.now();
    final annual =
        computeAnnualStats(books: books, movies: movies, year: now.year);
    final heatmap = _buildHeatmap(books, movies, now);
    final categories = categoryDistribution(books);
    final top5 = categories.take(5).toList();
    final ratings = ratingDistribution(books: books, movies: movies);
    final reading = readingProgressList(books);
    final fiveStar = _fiveStarItems(books, movies, now.year);

    return Scaffold(
      appBar: AppBar(title: const Text('个人统计')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // ==================== 第一段：年度概览 ====================
          _OverviewSection(
            annual: annual,
            heatmap: heatmap,
            now: now,
            range: _range,
            onRangeChanged: (v) => setState(() => _range = v),
          ),

          // ==================== 第二段：偏好分析 ====================
          _PreferenceSection(
            top5: top5,
            totalBooks: categories.fold<int>(0, (a, e) => a + e.count),
            ratings: ratings,
          ),

          // ==================== 第三段：进行中与里程碑 ====================
          _ProgressSection(
            reading: reading,
            fiveStar: fiveStar,
            onShowAllReading: () => _showAllReading(context, reading),
          ),

          // ==================== 年报入口 ====================
          const SizedBox(height: 24),
          AnnualReportEntry(year: now.year),
        ],
      ),
    );
  }

  // ---------- 数据组装 ----------

  HeatmapData _buildHeatmap(
      List<Book> books, List<Movie> movies, DateTime now) {
    final (from, to) = _rangeBounds(now);
    final entities = [
      for (final b in books) (b.id, bookActivityDates(b)),
      for (final m in movies) (m.id, movieActivityDates(m)),
    ];
    return buildHeatmap(entities, from: from, to: to);
  }

  (DateTime, DateTime) _rangeBounds(DateTime now) {
    switch (_range) {
      case HeatmapRange.month30:
        return (now.subtract(const Duration(days: 29)), now);
      case HeatmapRange.quarter:
        return (now.subtract(const Duration(days: 89)), now);
      case HeatmapRange.year:
        return (DateTime(now.year, 1, 1), now);
    }
  }

  /// 本年度 5 星条目：(type, title, emoji, hue)
  List<(String, String, String?, double)> _fiveStarItems(
      List<Book> books, List<Movie> movies, int year) {
    final result = <(String, String, String?, double)>[];
    for (final b in books) {
      final f = b.finishedAt;
      if (b.rating == 5 && f != null && f.year == year) {
        result.add(('书', b.title, b.emoji, b.coverHue));
      }
    }
    for (final m in movies) {
      final w = m.watchDate;
      if (m.rating == 5 && w != null && w.year == year) {
        result.add(('影', m.title, m.emoji, m.coverHue));
      }
    }
    return result;
  }

  void _showAllReading(BuildContext context, List<ReadingProgress> items) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          shrinkWrap: true,
          children: [
            Text('全部在读 · ${items.length} 本',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary)),
            const SizedBox(height: 12),
            for (final r in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ReadingProgressBar(item: r),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================== 子组件 ====================

/// 第一段：年度概览（打卡热力图 + metric bar）
class _OverviewSection extends StatefulWidget {
  const _OverviewSection({
    required this.annual,
    required this.heatmap,
    required this.now,
    required this.range,
    required this.onRangeChanged,
  });

  final AnnualStats annual;
  final HeatmapData heatmap;
  final DateTime now;
  final HeatmapRange range;
  final ValueChanged<HeatmapRange> onRangeChanged;

  @override
  State<_OverviewSection> createState() => _OverviewSectionState();
}

class _OverviewSectionState extends State<_OverviewSection> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricBar(annual: widget.annual),
        const SizedBox(height: 16),
        SectionCard(
          title: '打卡记录',
          trailing: RangeSwitch(
            value: widget.range,
            onChanged: widget.onRangeChanged,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeatmapCalendar(
                data: widget.heatmap,
                endDate: widget.now,
                hue: widget.range == HeatmapRange.month30 ? 160 : 260,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  LegendDot(color: context.colors.surfaceHigh, label: '未打卡'),
                  const SizedBox(width: 10),
                  LegendDot(
                      color: HSLColor.fromAHSL(
                              1,
                              widget.range == HeatmapRange.month30 ? 160 : 260,
                              0.65,
                              0.5)
                          .toColor()
                          .withOpacity(0.35),
                      label: '1 次'),
                  const SizedBox(width: 10),
                  LegendDot(
                      color: HSLColor.fromAHSL(
                              1,
                              widget.range == HeatmapRange.month30 ? 160 : 260,
                              0.65,
                              0.5)
                          .toColor()
                          .withOpacity(0.95),
                      label: '3+ 次'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 第二段：偏好分析（类型分布环图 + 评分习惯柱状图）
class _PreferenceSection extends StatelessWidget {
  const _PreferenceSection({
    required this.top5,
    required this.totalBooks,
    required this.ratings,
  });

  final List<CategoryEntry> top5;
  final int totalBooks;
  final RatingDistribution ratings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        SectionCard(
          title: '类型偏好',
          child: top5.isEmpty
              ? const EmptyHint(text: '读完的书标记分类后，这里会展示你的口味分布')
              : Row(
                  children: [
                    DonutChart(
                      percentages: top5.map((e) => e.percent).toList(),
                      labels: top5.map((e) => e.category).toList(),
                      centerText: '$totalBooks 本',
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < top5.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppPalette.chartSeries[
                                          i % AppPalette.chartSeries.length],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(top5[i].category,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color:
                                                context.colors.textSecondary)),
                                  ),
                                  Text(
                                    '${(top5[i].percent * 100).round()}%',
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: context.colors.textPrimary),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: '评分习惯',
          child: ratings.total == 0
              ? const EmptyHint(text: '评分后这里会展示 1~5 星的分布')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RatingBarChart(distribution: ratings),
                    const SizedBox(height: 6),
                    Text('共 ${ratings.total} 条评分',
                        style: TextStyle(
                            fontSize: 11, color: context.colors.textMuted)),
                  ],
                ),
        ),
      ],
    );
  }
}

/// 第三段：进行中与里程碑（在读进度 + 五星封面墙）
class _ProgressSection extends StatelessWidget {
  const _ProgressSection({
    required this.reading,
    required this.fiveStar,
    required this.onShowAllReading,
  });

  final List<ReadingProgress> reading;
  final List<(String, String, String?, double)> fiveStar;
  final VoidCallback onShowAllReading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        SectionCard(
          title: reading.isEmpty ? '进行中' : '进行中 · ${reading.length} 本在读',
          child: reading.isEmpty
              ? const EmptyHint(text: '书架里还没有在读的书，去添加一本吧')
              : Column(
                  children: [
                    for (final r in reading.take(3))
                      ReadingProgressBar(item: r),
                    if (reading.length > 3)
                      TextButton(
                        onPressed: onShowAllReading,
                        child: Text('查看全部 ${reading.length} 本在读'),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title:
              fiveStar.isEmpty ? '本年度最高分' : '本年度最高分 · ${fiveStar.length} 部五星',
          child: fiveStar.isEmpty
              ? const EmptyHint(text: '今年标记 5 星的书影会出现在这里')
              : SizedBox(
                  height: 120,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: fiveStar.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final item = fiveStar[i];
                      return SizedBox(
                        width: 84,
                        child: Column(
                          children: [
                            CoverPlaceholder(
                              title: item.$2,
                              emoji: item.$3,
                              hue: item.$4,
                              aspectRatio: 3 / 4,
                              borderRadius: 10,
                            ),
                            const SizedBox(height: 4),
                            Text(item.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: context.colors.textSecondary)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
