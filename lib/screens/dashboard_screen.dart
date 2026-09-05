import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../models/book.dart';
import '../models/movie.dart';
import '../providers/library_provider.dart';
import '../widgets/grid_item_card.dart';
import '../widgets/media_tile.dart';
import '../widgets/section_header.dart';
import '../widgets/stats_card.dart';

/// 仪表盘主页 —— 数据统计 + 当前任务 + 阅读/电影列表
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();

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
                    bookStats: library.bookStats,
                    movieStats: library.movieStats,
                    planToReadCount: library.planToReadBooks.length,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatsCard(
                    type: StatsCardType.movie,
                    bookStats: library.bookStats,
                    movieStats: library.movieStats,
                    planToReadCount: library.planToReadBooks.length,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),

          // ---------- 当前任务（横向滚动） ----------
          const SectionHeader(
            title: '当前任务',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('下一部电影'),
                Icon(Icons.arrow_forward_ios, size: 11),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CurrentTasks(library: library),
          const SizedBox(height: 26),

          // ---------- 阅读列表 ----------
          const SectionHeader(
            title: '阅读列表',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('查看全部'),
                Icon(Icons.arrow_forward_ios, size: 11),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _BookGrid(books: library.readingList),
          const SizedBox(height: 26),

          // ---------- 电影列表 ----------
          const SectionHeader(
            title: '我的电影',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('查看全部'),
                Icon(Icons.arrow_forward_ios, size: 11),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _MovieGrid(movies: library.movieList),
        ],
      ),
    );
  }
}

/// 顶部欢迎头
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          // Logo 标记
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.readingGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_stories_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          // 标题区占满剩余空间（窄屏超长时自动省略，避免溢出）
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '墨影',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'My Media Tracker · 书影记录',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.search_rounded,
                color: AppColors.textSecondary),
            tooltip: '搜索',
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none_rounded,
                color: AppColors.textSecondary),
            tooltip: '通知',
          ),
        ],
      ),
    );
  }
}

/// 当前任务横向滚动区（在读的书 + 想看的电影）
class _CurrentTasks extends StatelessWidget {
  const _CurrentTasks({required this.library});

  final LibraryProvider library;

  @override
  Widget build(BuildContext context) {
    // 组装横向卡片序列：在读 2 本 + 想看 2 部电影
    final tiles = <Widget>[];

    for (final Book b in library.currentlyReadingBooks.take(2)) {
      tiles.add(
        MediaTile.book(
          title: b.title,
          subtitle: b.author,
          progress: b.progress,
          pageText: '第 ${b.currentPage}/${b.totalPages} 页',
          emoji: b.emoji ?? '',
          hue: b.coverHue,
          media: b.cover,
        ),
      );
    }
    for (final Movie m in library.upcomingMovies.take(2)) {
      tiles.add(
        MediaTile.movie(
          title: m.title,
          subtitle: '${m.year} · 想看',
          emoji: m.emoji ?? '',
          hue: m.coverHue,
          media: m.poster,
        ),
      );
    }

    // 空态：保留原 268 高度，避免外层 ListView 高度跳变
    if (tiles.isEmpty) {
      return const SizedBox(
        height: 268,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: _InlineEmpty(
            icon: Icons.auto_awesome_outlined,
            title: '暂无当前任务',
            subtitle: '在读的书或想看的电影会出现在这里\n去对应模块添加吧',
          ),
        ),
      );
    }

    return SizedBox(
      height: 268,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: tiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => tiles[i],
      ),
    );
  }
}

/// 书籍网格（2 列）
class _BookGrid extends StatelessWidget {
  const _BookGrid({required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: _InlineEmpty(
          icon: Icons.menu_book_outlined,
          title: '书库空空',
          subtitle: '去「书籍」Tab 添加你的第一本书',
        ),
      );
    }
    return _GridSection(
      children: [
        for (final b in books)
          GridItemCard(
            title: b.title,
            subtitle: b.author,
            emoji: b.emoji ?? '',
            hue: b.coverHue,
            media: b.cover,
            rating: b.rating,
            statusLabel: b.status.label,
          ),
      ],
    );
  }
}

/// 电影网格（2 列）
class _MovieGrid extends StatelessWidget {
  const _MovieGrid({required this.movies});

  final List<Movie> movies;

  @override
  Widget build(BuildContext context) {
    if (movies.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: _InlineEmpty(
          icon: Icons.movie_outlined,
          title: '还没有电影记录',
          subtitle: '去「电影」Tab 添加你的第一部',
        ),
      );
    }
    return _GridSection(
      children: [
        for (final m in movies)
          GridItemCard(
            title: m.title,
            subtitle: m.director ?? '${m.year}',
            emoji: m.emoji ?? '',
            hue: m.coverHue,
            media: m.poster,
            rating: m.rating,
            statusLabel: m.status.label,
          ),
      ],
    );
  }
}

/// 统一 2 列网格容器
class _GridSection extends StatelessWidget {
  const _GridSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final itemWidth = (constraints.maxWidth - gap) / 2;
          // 逐行排布，保证 item 宽度一致且总高精确
          final rows = <Widget>[];
          for (var i = 0; i < children.length; i += 2) {
            rows.add(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: itemWidth, child: children[i]),
                  if (i + 1 < children.length) ...[
                    const SizedBox(width: gap),
                    SizedBox(width: itemWidth, child: children[i + 1]),
                  ],
                ],
              ),
            );
            if (i + 2 < children.length) rows.add(const SizedBox(height: gap));
          }
          return Column(children: rows);
        },
      ),
    );
  }
}

/// 仪表盘内联空态（嵌入 ListView 区块内，比 PlaceholderView 紧凑）
///
/// - 圆角浅色卡片 + 居中 icon + 标题 + 多行描述
/// - 不带 CTA：跳转由用户点击底部 Tab 自助完成（避免 Tab 控制器提升到全局的连带重构）
class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: AppColors.textMuted, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.55,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}