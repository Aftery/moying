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
import 'book_detail_screen.dart';
import 'book_edit_screen.dart';
import 'movie_detail_screen.dart';
import 'movie_edit_screen.dart';

/// 仪表盘主页 —— 数据统计 + 当前任务 + 阅读/电影列表
///
/// [onOpenBooks] / [onOpenMovies]：「查看全部」等入口跳转对应底部 Tab，
/// 由 MainShell 注入（IndexedStack 切换，各 Tab 状态保留）；不传则无跳转。
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, this.onOpenBooks, this.onOpenMovies});

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
class _HeaderLink extends StatelessWidget {
  const _HeaderLink({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: onTap != null
                ? context.colors.textSecondary
                : context.colors.textMuted,
          ),
        ),
        const SizedBox(width: 2),
        Icon(
          Icons.arrow_forward_ios,
          size: 11,
          color: onTap != null
              ? context.colors.textSecondary
              : context.colors.textMuted,
        ),
      ],
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: row,
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
              gradient: context.colors.readingGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_stories_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          // 标题区占满剩余空间（窄屏超长时自动省略，避免溢出）
          Expanded(
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
                    color: context.colors.textPrimary,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'My Media Tracker · 书影记录',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon:
                Icon(Icons.search_rounded, color: context.colors.textSecondary),
            tooltip: '搜索',
          ),
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.notifications_none_rounded,
                color: context.colors.textSecondary),
            tooltip: '通知',
          ),
        ],
      ),
    );
  }
}

/// 当前任务横向滚动区（在读的书 + 想看的电影）
class _CurrentTasks extends StatelessWidget {
  const _CurrentTasks({required this.books, required this.movies});

  final List<Book> books;
  final List<Movie> movies;

  @override
  Widget build(BuildContext context) {
    // 组装横向卡片序列：在读 2 本 + 想看 2 部电影
    final tiles = <Widget>[];

    for (final Book b in books.take(2)) {
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
    for (final Movie m in movies.take(2)) {
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
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _InlineEmpty(
          icon: Icons.menu_book_outlined,
          title: '书库空空',
          subtitle: '点击这里直接添加你的第一本书',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const BookEditScreen()),
          ),
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
            // 与书籍模块一致：单击进详情、长按进编辑
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => BookDetailScreen(bookId: b.id)),
            ),
            onLongPress: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => BookEditScreen(bookId: b.id)),
            ),
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
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: _InlineEmpty(
          icon: Icons.movie_outlined,
          title: '还没有电影记录',
          subtitle: '点击这里直接添加你的第一部电影',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MovieEditScreen()),
          ),
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
            // 与书籍模块一致：单击进详情、长按进编辑
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => MovieDetailScreen(movieId: m.id)),
            ),
            onLongPress: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MovieEditScreen(movieId: m.id)),
            ),
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
/// - 传入 [onTap] 时整卡可点击（书籍 / 电影空态直达新增页）；不传则纯展示
class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
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
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: context.colors.textMuted, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: context.colors.textMuted,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: card,
    );
  }
}
