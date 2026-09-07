import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../data/statistics.dart';
import '../models/book.dart';
import '../models/movie.dart';
import '../providers/library_provider.dart';
import '../widgets/cover_placeholder.dart';

/// 年度读书年报 —— 这一年阅读与观影的快照总结
///
/// 内容（产品已确认）：
/// 1. 最晚读完的一本书（completedAt 时刻最晚）
/// 2. 阅读页数最多的一周
/// 3. 打破偏好的那本书（分类与整体最高频分类不同）
class AnnualReportScreen extends StatelessWidget {
  const AnnualReportScreen({super.key, required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final books = context.select<LibraryProvider, List<Book>>((p) => p.books);
    final movies =
        context.select<LibraryProvider, List<Movie>>((p) => p.movieList);
    final h = computeAnnualHighlights(
        books: books, movies: movies, year: year);

    return Scaffold(
      appBar: AppBar(title: Text('$year 年度报告')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // ==================== 年度总览 ====================
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: context.colors.readingGradient,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('READING $year',
                    style: const TextStyle(
                        fontSize: 11,
                        letterSpacing: 2.2,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70)),
                const SizedBox(height: 6),
                Text('今年读完了 ${h.totalBooksRead} 本书',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  '累计 ${h.totalPagesRead} 页 · 看了 ${h.totalMoviesWatched} 部电影'
                  '${h.totalMinutesWatched > 0 ? '（约 ${h.totalMinutesWatched ~/ 60} 小时）' : ''}',
                  style: const TextStyle(
                      fontSize: 12.5, color: Colors.white),
                ),
                if (h.topCategory != null) ...[
                  const SizedBox(height: 10),
                  Text('你的年度偏好是「${h.topCategory}」',
                      style: const TextStyle(
                          fontSize: 12.5, color: Colors.white)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ==================== 最晚读完的一本书 ====================
          _ReportCard(
            icon: '🌙',
            title: '最晚读完的一本书',
            child: h.latestFinishedBook == null
                ? const _EmptyHint()
                : _BookRow(book: h.latestFinishedBook!),
          ),
          const SizedBox(height: 14),

          // ==================== 阅读最快的一周 ====================
          _ReportCard(
            icon: '⚡',
            title: '阅读速度最快的一周',
            child: h.fastestReadingWeek == null
                ? const _EmptyHint()
                : Text(h.fastestReadingWeek!,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary)),
          ),
          const SizedBox(height: 14),

          // ==================== 打破偏好的那本书 ====================
          _ReportCard(
            icon: '💡',
            title: '打破偏好的那一本',
            child: h.breakthroughBook == null
                ? const _EmptyHint()
                : _BookRow(
                    book: h.breakthroughBook!,
                    caption: h.topCategory == null
                        ? null
                        : '平时读「${h.topCategory}」的你，读了这本「${h.breakthroughBook!.category}」'),
          ),
          const SizedBox(height: 24),
          Text(
            '年报数据为实时快照 · 完成记录变化后自动更新',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 11, color: context.colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final String icon;
  final String title;
  final Widget child;

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
              Text(icon, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.book, this.caption});

  final Book book;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: CoverPlaceholder(
            title: book.title,
            emoji: book.emoji,
            hue: book.coverHue,
            aspectRatio: 3 / 4,
            borderRadius: 8,
            fontSize: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('《${book.title}》',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary)),
              const SizedBox(height: 2),
              Text(book.author,
                  style: TextStyle(
                      fontSize: 12, color: context.colors.textSecondary)),
              if (caption != null) ...[
                const SizedBox(height: 6),
                Text(caption!,
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: context.colors.textMuted)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Text('今年暂无相关记录，完成阅读后这里会点亮',
        style: TextStyle(fontSize: 12, color: context.colors.textMuted));
  }
}