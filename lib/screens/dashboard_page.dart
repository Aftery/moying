import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../models/book.dart';
import '../models/movie.dart';
import '../models/stats.dart';
import '../providers/library_provider.dart';
import '../widgets/grid_item_card.dart';
import '../widgets/media_tile.dart';
import '../widgets/section_header.dart';
import '../widgets/stats_card.dart';
import 'book_detail_page.dart';
import 'book_edit_page.dart';
import 'movie_detail_page.dart';
import 'movie_edit_page.dart';

part 'dashboard_widgets.dart';

/// 仪表盘主页 —— 数据统计 + 当前任务 + 阅读/电影列表
///
/// [onOpenBooks] / [onOpenMovies]：「查看全部」等入口跳转对应底部 Tab，
/// 由 RootPage 注入（IndexedStack 切换，各 Tab 状态保留）；不传则无跳转。
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, this.onOpenBooks, this.onOpenMovies});

  final VoidCallback? onOpenBooks;
  final VoidCallback? onOpenMovies;

  @override
  Widget build(BuildContext context) {
    // H6/M6：select 收窄订阅——其他 Tab 的数据变化（如改个人资料）不再
    // 触发仪表盘整页 rebuild；仅本页消费的派生数据引用变化时重建。
    // 依赖的 getter 均有 provider 侧缓存（引用稳定），select 才有意义。
    final bookStats =
        context.select<LibraryProvider, BookStats>((p) => p.bookStats);
    final movieStats =
        context.select<LibraryProvider, MovieStats>((p) => p.movieStats);
    final planToReadCount =
        context.select<LibraryProvider, int>((p) => p.planToReadBooks.length);
    final readingList =
        context.select<LibraryProvider, List<Book>>((p) => p.readingList);
    final currentlyReading = context.select<LibraryProvider, List<Book>>(
        (p) => p.currentlyReadingBooks);
    final movieList =
        context.select<LibraryProvider, List<Movie>>((p) => p.movieList);
    final upcoming = context
        .select<LibraryProvider, List<Movie>>((p) => p.upcomingMovies);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          // ---------- 顶部标题 ----------
          const _Header(),
          const SizedBox(height: 20),

          // ---------- 统计双卡 ----------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StatsCard(
                    type: StatsCardType.reading,
                    bookStats: bookStats,
                    movieStats: movieStats,
                    planToReadCount: planToReadCount,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatsCard(
                    type: StatsCardType.movie,
                    bookStats: bookStats,
                    movieStats: movieStats,
                    planToReadCount: planToReadCount,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),

          // ---------- 当前任务（横向滚动） ----------
          SectionHeader(
            title: '当前任务',
            trailing: _HeaderLink(
              label: '下一部电影',
              onTap: onOpenMovies,
            ),
          ),
          const SizedBox(height: 12),
          _CurrentTasks(books: currentlyReading, movies: upcoming),
          const SizedBox(height: 26),

          // ---------- 阅读列表 ----------
          SectionHeader(
            title: '阅读列表',
            trailing: _HeaderLink(
              label: '查看全部',
              onTap: onOpenBooks,
            ),
          ),
          const SizedBox(height: 12),
          _BookGrid(books: readingList.take(4).toList()),
          const SizedBox(height: 26),

          // ---------- 电影列表 ----------
          SectionHeader(
            title: '我的电影',
            trailing: _HeaderLink(
              label: '查看全部',
              onTap: onOpenMovies,
            ),
          ),
          const SizedBox(height: 12),
          _MovieGrid(movies: movieList.take(4).toList()),
        ],
      ),
    );
  }
}

/// 区块头部的可点入口（查看全部 / 下一部电影），onTap 为空时退化为纯文本
