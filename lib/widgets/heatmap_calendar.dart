import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import '../data/statistics.dart';

/// GitHub 风格打卡热力图
///
/// 布局：周（列）× 周一到周日（行），每格 1 天；颜色规则：
/// - count == 0 → 深灰底（未打卡）
/// - count == 1 → 浅紫/浅绿微光
/// - count == 2 → 中亮
/// - count >= 3 → 高亮
///
/// [data] 为 { "yyyy-MM-dd": count }，未出现的日期按 0 处理。
class HeatmapCalendar extends StatelessWidget {
  const HeatmapCalendar({
    super.key,
    required this.data,
    required this.endDate,
    this.cellSize = 13,
    this.spacing = 3,
    this.hue = 260, // 默认紫；可传 160 用绿
  });

  final HeatmapData data;
  final DateTime endDate;
  final double cellSize;
  final double spacing;
  final double hue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cells = _buildCells(colors);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 自适应列数：按月维度，最多 53 周；超出宽度自动收缩 cell
        final cols = cells.length;
        final maxWidth = constraints.maxWidth;
        final usable = maxWidth - 32;
        final cell = cols * cellSize + (cols - 1) * spacing > usable
            ? (usable - (cols - 1) * spacing) / cols
            : cellSize;
        if (cell < 6) {
          return SizedBox(
            width: maxWidth,
            child: Text(
              '活跃数据较少，暂以列表展示',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧星期标签（可选，简化为底部月份）
              for (var c = 0; c < cells.length; c++)
                Padding(
                  padding: EdgeInsets.only(right: spacing),
                  child: Column(
                    children: [
                      for (var r = 0; r < 7; r++)
                        Padding(
                          padding: EdgeInsets.only(bottom: spacing),
                          child: Container(
                            width: cell,
                            height: cell,
                            decoration: BoxDecoration(
                              color: cells[c][r],
                              borderRadius: BorderRadius.circular(cell * 0.25),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// 生成 53 列 × 7 行 的颜色矩阵（按周日历对齐）
  List<List<Color>> _buildCells(AppPalette colors) {
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    // 起始：end 往前推 N 天，取到最近一个周日作为起点（保证 7 行完整）
    final start = end.subtract(const Duration(days: 364));
    // 对齐到周日（weekday 7 为周日；计算需要显示多少周）
    final totalDays = end.difference(start).inDays + 1;
    final weeks = (totalDays / 7).ceil();
    final cols = weeks;

    final result = List.generate(cols, (_) => List.generate(7, (_) => colors.surfaceHigh));

    // 行首为周一（r=0 → Monday）：补空数 = weekday - 1
    final firstWeekOffset = start.weekday - 1;
    for (var w = 0; w < cols; w++) {
      for (var r = 0; r < 7; r++) {
        final dayIndex = w * 7 + r - firstWeekOffset;
        final date = start.add(Duration(days: dayIndex));
        if (dayIndex < 0 || date.isAfter(end)) continue;
        final key = _key(date);
        final count = data[key] ?? 0;
        result[w][r] = _colorFor(count, colors);
      }
    }
    return result;
  }

  Color _colorFor(int count, AppPalette colors) {
    if (count == 0) return colors.surfaceHigh;
    final base = HSLColor.fromAHSL(1, hue, 0.65, 0.5).toColor();
    if (count == 1) return base.withOpacity(0.35);
    if (count == 2) return base.withOpacity(0.6);
    return base.withOpacity(0.95);
  }

  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}