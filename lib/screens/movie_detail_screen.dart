import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../config/edit_results.dart';
import '../models/actor.dart';
import '../models/movie.dart';
import '../providers/library_provider.dart';
import '../widgets/media_cover.dart';
import '../widgets/rating_stars.dart';
import 'actor_detail_screen.dart';
import 'movie_edit_screen.dart';

/// 电影详情界面
///
/// 布局对齐参考图 2（严格自上而下）：
/// 顶部海报 → 名称/英文名/导演与评分 → 电影简介 → 补充元数据卡（4 项）
/// → 主创/演员横滚 → 我的影评卡 → 剧照网格。
/// AppBar 右上角提供「编辑」入口；从编辑页删除后自动返回上一页。
class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({super.key, required this.movieId});

  /// 需要展示的电影 id
  final String movieId;

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  Future<void> _openEditor(BuildContext context) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MovieEditScreen(movieId: widget.movieId),
      ),
    );
    // 编辑页里删除了这部电影 → 详情页随之关闭
    if (result == kEditResultDeleted && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final matches =
        library.movieList.where((m) => m.id == widget.movieId).toList();
    final movie = matches.isEmpty ? null : matches.first;
    // 演员区数据源：id → 实体解析（悬空引用由 actorsByIds 静默跳过）。
    // seed 阶段 id=name，此处解析前后显示完全一致——本步是纯消费端重构。
    final castActors = movie == null
        ? const <Actor>[]
        : (movie.actorIds == null
            ? const <Actor>[]
            : library.actorsByIds(movie.actorIds!));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '编辑',
            icon:  Icon(Icons.edit_rounded, color: context.colors.textPrimary),
            onPressed: movie == null ? null : () => _openEditor(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: movie == null
          ?  Center(
              child: Text(
                '这部电影已从电影库移除',
                style: TextStyle(color: context.colors.textMuted),
              ),
            )
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPoster(movie),
                    const SizedBox(height: 22),
                    // ---------- 名称 / 英文名 / 导演 / 评分 ----------
                    Text(
                      movie.title,
                      textAlign: TextAlign.center,
                      style:  TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (movie.englishTitle != null &&
                        movie.englishTitle!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        movie.englishTitle!,
                        textAlign: TextAlign.center,
                        style:  TextStyle(
                          color: context.colors.textMuted,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                    if (movie.director != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        movie.director!,
                        textAlign: TextAlign.center,
                        style:  TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (movie.hasRating) ...[
                      const SizedBox(height: 6),
                      Center(
                        child: RatingStars(
                          rating: movie.rating!,
                          size: 22,
                          showValue: true,
                          valueStyle:  TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 26),
                    // ---------- 电影简介 ----------
                    if (movie.description != null &&
                        movie.description!.isNotEmpty) ...[
                      _sectionTitle(context, '电影简介'),
                      const SizedBox(height: 10),
                      _ExpandableSynopsis(text: movie.description!),
                      const SizedBox(height: 26),
                    ],
                    // ---------- 补充元数据卡（紧接简介下方，4 项）----------
                    _buildMetaCard(movie),
                    const SizedBox(height: 26),
                    // ---------- 主创 / 演员（实体条，点击进演员页）----------
                    if (castActors.isNotEmpty) ...[
                      _sectionTitle(context, '主创 / 演员'),
                      const SizedBox(height: 12),
                      _buildCastRow(castActors),
                      const SizedBox(height: 26),
                    ],
                    // ---------- 我的影评 ----------
                    _sectionTitle(context, '我的影评'),
                    const SizedBox(height: 10),
                    _buildReviewCard(movie),
                    const SizedBox(height: 26),
                    // ---------- 剧照 ----------
                    _sectionTitle(context, '剧照'),
                    const SizedBox(height: 12),
                    _buildStillsGrid(movie),
                  ],
                ),
              ),
            ),
    );
  }

  // ---------- 顶部海报 ----------

  Widget _buildPoster(Movie movie) {
    return Center(
      child: Container(
        width: 190,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: MediaCover(
            media: movie.poster,
            title: movie.title,
            emoji: movie.emoji ?? '',
            hue: movie.coverHue,
            aspectRatio: 3 / 4,
            borderRadius: 0,
            fontSize: 60,
          ),
        ),
      ),
    );
  }

  // ---------- 补充元数据卡（2×2 网格）----------
  // 四项固定：看过日期 / 上映时间 / 片长 / 剧情类型

  Widget _buildMetaCard(Movie movie) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.outline, width: 0.7),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MetaCell(
                  icon: Icons.visibility_rounded,
                  label: '看过日期',
                  value: movie.watchDateText.isEmpty
                      ? '—'
                      : movie.watchDateText,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _MetaCell(
                  icon: Icons.calendar_month_rounded,
                  label: '上映时间',
                  value: movie.releaseDateText.isEmpty
                      ? '${movie.year}'
                      : movie.releaseDateText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MetaCell(
                  icon: Icons.timer_outlined,
                  label: '片长',
                  value: movie.durationText.isEmpty ? '—' : movie.durationText,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _MetaCell(
                  icon: Icons.local_movies_outlined,
                  label: '剧情类型',
                  value: movie.genresText.isEmpty ? '—' : movie.genresText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 主创 / 演员（横向滚动，实体条可点击进演员页）----------

  Widget _buildCastRow(List<Actor> cast) {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: cast.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final actor = cast[i];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ActorDetailScreen(actorId: actor.id),
              ),
            ),
            child: Column(
              children: [
                // 圆形头像（有头像显图，无则姓名首字渐变占位）
                SizedBox(
                  width: 62,
                  height: 62,
                  child: MediaCover(
                    circular: true,
                    media: actor.avatar,
                    title: actor.name,
                    hue: 30.0 * (i + 1),
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: 84,
                  child: Text(
                    actor.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style:  TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ---------- 我的影评卡 ----------

  Widget _buildReviewCard(Movie movie) {
    final review = movie.review;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.outline, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部行：评分星星 + 编辑影评按钮
          Row(
            children: [
              Expanded(
                child: movie.hasRating
                    ? Row(
                        children: [
                          RatingStars(rating: movie.rating!, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '${movie.rating!.toStringAsFixed(1)}/5',
                            style:  TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      )
                    :  Text(
                        '尚未评分',
                        style: TextStyle(
                            color: context.colors.textMuted, fontSize: 13),
                      ),
              ),
              OutlinedButton.icon(
                onPressed: () => _openEditor(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.accent,
                  side:  BorderSide(
                      color: context.colors.accent, width: 1),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.edit_outlined, size: 15),
                label: const Text('编辑影评',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 影评文本
          if (review == null || review.isEmpty)
             Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.edit_note_rounded,
                    size: 16, color: context.colors.textMuted),
                const SizedBox(width: 6),
                Text(
                  '还没有写下影评',
                  style: TextStyle(color: context.colors.textMuted, fontSize: 13),
                ),
              ],
            )
          else
            Text(
              review,
              style:  TextStyle(
                color: context.colors.textSecondary,
                fontSize: 14,
                height: 1.7,
              ),
            ),
        ],
      ),
    );
  }

  // ---------- 剧照（双列网格，用色块模拟）----------

  Widget _buildStillsGrid(Movie movie) {
    // 以电影主色hue 生成 4 张风格一致的「剧照」占位
    final hues = [movie.coverHue, movie.coverHue + 28,
        movie.coverHue + 56, movie.coverHue - 20];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        for (final h in hues)
          Container(
            decoration: BoxDecoration(
              gradient: coverGradient(h % 360),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Icon(Icons.movie_filter_rounded,
                      color: Colors.white24, size: 40),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---------- 区块标题 ----------

  Widget _sectionTitle(BuildContext context, String text) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            gradient: context.colors.movieGradient,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style:  TextStyle(
            color: context.colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 元数据小格（图标 + 标签 + 值）
class _MetaCell extends StatelessWidget {
  const _MetaCell({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: context.colors.movieStart),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:  TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:  TextStyle(
              color: context.colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// 内容简介文本块（超过 4 行自动折叠，可展开/收起）
class _ExpandableSynopsis extends StatefulWidget {
  const _ExpandableSynopsis({required this.text});

  final String text;

  @override
  State<_ExpandableSynopsis> createState() => _ExpandableSynopsisState();
}

class _ExpandableSynopsisState extends State<_ExpandableSynopsis> {
  static const int _foldLines = 4;

  bool _expanded = false;
  bool _overflow = false;
  bool _measured = false;

  @override
  void didUpdateWidget(covariant _ExpandableSynopsis oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 内容变化（如编辑后返回）时重新测量折叠状态
    if (oldWidget.text != widget.text) {
      _measured = false;
      _overflow = false;
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.outline, width: 0.7),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!_measured) {
            _measured = true;
            final span = TextSpan(
              text: widget.text,
              style: TextStyle(
                fontSize: 14,
                height: 1.7,
                color: context.colors.textSecondary,
              ),
            );
            final painter = TextPainter(
              text: span,
              maxLines: _foldLines,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: constraints.maxWidth);
            final needFold = painter.didExceedMaxLines;
            if (needFold != _overflow) {
              _overflow = needFold;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            }
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.text,
                maxLines: _expanded ? null : _foldLines,
                overflow: _expanded ? null : TextOverflow.ellipsis,
                style:  TextStyle(
                  fontSize: 14,
                  height: 1.7,
                  color: context.colors.textSecondary,
                ),
              ),
              if (_overflow)
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _expanded ? '收起' : '展开全部',
                            style:  TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: context.colors.accent,
                            ),
                          ),
                          Icon(
                            _expanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                            size: 16,
                            color: context.colors.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}