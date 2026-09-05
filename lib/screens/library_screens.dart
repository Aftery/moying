import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../models/movie.dart';
import '../providers/library_provider.dart';
import '../widgets/grid_item_card.dart';
import '../widgets/search_bar_widget.dart';
import 'movie_detail_screen.dart';
import 'movie_edit_screen.dart';

/// 电影库主页面
///
/// 对齐参考图 1：
/// - 顶部搜索栏（片名/导演实时过滤）
/// - 分类筛选 + 排序两个下拉（排序：评分最高 / 观影时间最新 / 上映时间最新）
/// - 双列网格卡片（封面 + 状态徽标 + 片名 + 导演 + 星级评分）
/// - 单击卡片 → 详情页
/// - 右下角 FAB → 新增电影
class MoviesScreen extends StatefulWidget {
  const MoviesScreen({super.key});

  @override
  State<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends State<MoviesScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String? _genreFilter;
  MovieSort _sort = MovieSort.ratingHigh;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final movies = library.getFilteredMovies(
      query: _query,
      genre: _genreFilter,
      sort: _sort,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          '电影',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---------- 搜索栏 ----------
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: SearchBarWidget(
                controller: _searchCtrl,
                hintText: '搜索电影/导演…',
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 12),
            // ---------- 筛选 + 排序 ----------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _FilterDropdown<String?>(
                    icon: Icons.theaters_rounded,
                    value: _genreFilter,
                    items: [
                      const _FilterItem(label: '全部类型', value: null),
                      for (final g in kMovieCategories)
                        _FilterItem(label: g, value: g),
                    ],
                    onChanged: (v) => setState(() => _genreFilter = v),
                  ),
                  const SizedBox(width: 10),
                  _FilterDropdown<MovieSort>(
                    icon: Icons.swap_vert_rounded,
                    value: _sort,
                    items: [
                      for (final s in MovieSort.values)
                        _FilterItem(label: s.label, value: s),
                    ],
                    onChanged: (v) => setState(() => _sort = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // ---------- 结果计数行 ----------
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Text(
                '共 ${movies.length} 部',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 6),
            // ---------- 双列网格 ----------
            Expanded(
              child: movies.isEmpty
                  ? _buildEmpty()
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.56,
                      ),
                      itemCount: movies.length,
                      itemBuilder: (context, i) {
                        final movie = movies[i];
                        return GridItemCard(
                          title: movie.title,
                          subtitle: movie.director ?? '${movie.year}',
                          emoji: movie.emoji ?? '',
                          hue: movie.coverHue,
                          media: movie.poster,
                          rating: movie.rating,
                          statusLabel: movie.status.label,
                          onTap: () => _openDetail(movie.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      // ---------- 新增电影 FAB ----------
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        // 唯一 heroTag：避免与书籍列表页 FAB 在 IndexedStack 同一 Hero 子树中默认 tag 冲突
        heroTag: 'movies-add-fab',
        backgroundColor: AppColors.movieStart,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          '添加电影',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // ---------- 导航 ----------

  void _openDetail(String movieId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MovieDetailScreen(movieId: movieId)),
    );
  }

  Future<void> _openCreate() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const MovieEditScreen()),
    );
    if (result == kEditResultSaved && messenger.mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('电影已添加')));
    }
  }

  // ---------- 空状态 ----------

  Widget _buildEmpty() {
    final hasFilter = _query.isNotEmpty || _genreFilter != null;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            hasFilter ? Icons.search_off_rounded : Icons.movie_filter_rounded,
            size: 52,
            color: AppColors.textMuted.withOpacity(0.5),
          ),
          const SizedBox(height: 14),
          Text(
            hasFilter ? '没有找到匹配的电影' : '电影库空空如也',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasFilter) ...[
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => setState(() {
                _query = '';
                _searchCtrl.clear();
                _genreFilter = null;
              }),
              child: const Text('清除筛选条件'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 通用筛选项
class _FilterItem<T> {
  const _FilterItem({required this.label, required this.value});

  final String label;
  final T value;
}

/// 暗色下拉筛选组件
class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.icon,
    required this.items,
    required this.onChanged,
    required this.value,
  });

  final IconData icon;
  final List<_FilterItem<T>> items;
  final ValueChanged<T> onChanged;
  final T value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.outline, width: 0.8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            isDense: true,
            dropdownColor: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            icon: const Icon(Icons.expand_more_rounded,
                color: AppColors.textSecondary),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            items: [
              for (final item in items)
                DropdownMenuItem<T>(
                  value: item.value,
                  child: Row(
                    children: [
                      Icon(icon, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }
}