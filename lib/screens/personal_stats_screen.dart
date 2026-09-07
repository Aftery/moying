import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../data/statistics.dart';
import '../models/book.dart';
import '../models/movie.dart';
import '../providers/library_provider.dart';
import '../widgets/chart_widgets.dart';
import '../widgets/cover_placeholder.dart';
import '../widgets/heatmap_calendar.dart';
import 'annual_report_screen.dart';

/// 个人统计页 —— 三段式仪表盘
///
/// 1. 顶部：年度概览指标栏 + GitHub 风格打卡热力图（30天/季度/年度切换）
/// 2. 中部：类型偏好环形图 + 评分分布柱状图
/// 3. 底部：在读进度条（3 本 + 查看全部）+ 年度五星封面墙 + 年报入口
///
/// 全部数字来自 provider 计算属性，与仪表盘同源实时联动。
class PersonalStatsScreen extends StatefulWidget {
  const PersonalStatsScreen({super.key});

  @override
  State<PersonalStatsScreen> createState() => _PersonalStatsScreenState();
}

class _PersonalStatsScreenState extends State<PersonalStatsScreen> {
  HeatmapRange _range = HeatmapRange.month30;

  @override
  Widget build(BuildContext context) {
    final books = context.select<LibraryProvider, List<Book>>((p) => p.books);
    final movies =
        context.select<LibraryProvider, List<Movie>>((p) => p.movieList);

    final now = DateTime.now();
    final annual = computeAnnualStats(
        books: books, movies: movies, year: now.year);
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
          _MetricBar(annual: annual),
          const SizedBox(height: 16),
          _SectionCard(
            title: '打卡记录',
            trailing: _RangeSwitch(
              value: _range,
              onChanged: (v) => setState(() => _range = v),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HeatmapCalendar(
                  data: heatmap,
                  endDate: now,
                  hue: _range == HeatmapRange.month30 ? 160 : 260,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _LegendDot(color: context.colors.surfaceHigh, label: '未打卡'),
                    const SizedBox(width: 10),
                    _LegendDot(
                        color: HSLColor.fromAHSL(1, _range == HeatmapRange.month30 ? 160 : 260, 0.65, 0.5)
                            .toColor()
                            .withOpacity(0.35),
                        label: '1 次'),
                    const SizedBox(width: 10),
                    _LegendDot(
                        color: HSLColor.fromAHSL(1, _range == HeatmapRange.month30 ? 160 : 260, 0.65, 0.5)
                            .toColor()
                            .withOpacity(0.95),
                        label: '3+ 次'),
                  ],
                ),
              ],
            ),
          ),

          // ==================== 第二段：偏好分析 ====================
          const SizedBox(height: 20),
          _SectionCard(
            title: '类型偏好',
            child: top5.isEmpty
                ? const _EmptyHint(text: '读完的书标记分类后，这里会展示你的口味分布')
                : Row(
                    children: [
                      DonutChart(
                        percentages: top5.map((e) => e.percent).toList(),
                        labels: top5.map((e) => e.category).toList(),
                        centerText: '${categories.fold<int>(0, (a, e) => a + e.count)} 本',
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
                                        color: _segColor(i),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(top5[i].category,
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: context.colors.textSecondary)),
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
          _SectionCard(
            title: '评分习惯',
            child: ratings.total == 0
                ? const _EmptyHint(text: '评分后这里会展示 1~5 星的分布')
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

          // ==================== 第三段：进行中与里程碑 ====================
          const SizedBox(height: 20),
          _SectionCard(
            title: reading.isEmpty ? '进行中' : '进行中 · ${reading.length} 本在读',
            child: reading.isEmpty
                ? const _EmptyHint(text: '书架里还没有在读的书，去添加一本吧')
                : Column(
                    children: [
                      for (final r in reading.take(3))
                        _ReadingProgressBar(item: r),
                      if (reading.length > 3)
                        TextButton(
                          onPressed: () => _showAllReading(context, reading),
                          child: Text('查看全部 ${reading.length} 本在读'),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: fiveStar.isEmpty ? '本年度最高分' : '本年度最高分 · ${fiveStar.length} 部五星',
            child: fiveStar.isEmpty
                ? const _EmptyHint(text: '今年标记 5 星的书影会出现在这里')
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

          // ==================== 年报入口 ====================
          const SizedBox(height: 24),
          _AnnualReportEntry(year: now.year),
        ],
      ),
    );
  }

  // ---------- 数据组装 ----------

  HeatmapData _buildHeatmap(List<Book> books, List<Movie> movies, DateTime now) {
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

  Color _segColor(int i) {
    const palette = [
      Color(0xFF7C8CF8),
      Color(0xFF764BA2),
      Color(0xFF11998E),
      Color(0xFFFFC94D),
      Color(0xFFFFB020),
    ];
    return palette[i % palette.length];
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
                child: _ReadingProgressBar(item: r),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================== 子组件 ====================

/// 指标栏：年度读书 X 本 · 观影 Y 部 · 阅读时长 Z 小时
class _MetricBar extends StatelessWidget {
  const _MetricBar({required this.annual});

  final AnnualStats annual;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _metric('${annual.booksRead}', '年度读书 / 本', context),
          _divider(context),
          _metric('${annual.moviesWatched}', '年度观影 / 部', context),
          _divider(context),
          _metric('${annual.hoursWatched}h', '观影时长', context),
        ],
      ),
    );
  }

  Widget _metric(String value, String label, BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: context.colors.textPrimary)),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(fontSize: 11, color: context.colors.textMuted)),
      ],
    );
  }

  Widget _divider(BuildContext context) => Container(
        width: 1,
        height: 28,
        color: context.colors.outline,
      );
}

/// 区块卡片（标题 + 可选 trailing + 内容）
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// 范围切换（30天 / 季度 / 年度）
class _RangeSwitch extends StatelessWidget {
  const _RangeSwitch({required this.value, required this.onChanged});

  final HeatmapRange value;
  final ValueChanged<HeatmapRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in HeatmapRange.values)
            GestureDetector(
              onTap: () => onChanged(r),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: value == r ? context.colors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  switch (r) {
                    HeatmapRange.month30 => '30天',
                    HeatmapRange.quarter => '季度',
                    HeatmapRange.year => '年度',
                  },
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color:
                        value == r ? Colors.white : context.colors.textMuted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 10, color: context.colors.textMuted)),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(text,
            style: TextStyle(fontSize: 12, color: context.colors.textMuted)),
      ),
    );
  }
}

/// 在读进度条：《标题》 420/512 页 · 82%
class _ReadingProgressBar extends StatelessWidget {
  const _ReadingProgressBar({required this.item});

  final ReadingProgress item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('《${item.title}》',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary)),
              ),
              Text('${item.current}/${item.total} 页',
                  style: TextStyle(
                      fontSize: 11, color: context.colors.textMuted)),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: item.progress,
              minHeight: 6,
              backgroundColor: context.colors.surfaceHigh,
              valueColor:
                  AlwaysStoppedAnimation<Color>(context.colors.accent),
            ),
          ),
        ],
      ),
    );
  }
}

/// 年报入口卡
class _AnnualReportEntry extends StatelessWidget {
  const _AnnualReportEntry({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AnnualReportScreen(year: year))),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: context.colors.readingGradient,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const Text('📊', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('我的 $year 读书年报',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  const SizedBox(height: 3),
                  const Text('最晚读完的书 · 最快阅读周 · 打破偏好的那一本',
                      style: TextStyle(fontSize: 11, color: Colors.white70)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}