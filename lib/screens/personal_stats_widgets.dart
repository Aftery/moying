part of 'personal_stats_screen.dart';

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
