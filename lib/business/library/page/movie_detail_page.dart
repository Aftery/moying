import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../component/theme/app_palette.dart';
import '../../../foundation/constants/app_strings.dart';
import '../model/edit_result.dart';
import '../model/actor.dart';
import '../model/cast_item.dart';
import '../../../component/media/model/media_ref.dart';
import '../model/movie.dart';
import '../view_model/library_provider.dart';
import '../view/cast_bottom_sheet.dart';
import '../view/detail_common.dart';
import '../../../component/media/media_cover.dart';
import '../view/rating_stars.dart';
import 'actor_detail_page.dart';
import 'movie_edit_page.dart';
import 'movie_stills_page.dart';
import '../view/movie_detail_view.dart';

/// 电影详情界面
///
/// 布局对齐参考图 2（严格自上而下）：
/// 顶部海报 → 名称/英文名/导演与评分 → 电影简介 → 补充元数据卡（4 项）
/// → 主创/演员横滚 → 我的影评卡 → 剧照网格。
/// AppBar 右上角提供「编辑」入口；从编辑页删除后自动返回上一页。
class MovieDetailPage extends StatefulWidget {
  const MovieDetailPage({super.key, required this.movieId});

  /// 需要展示的电影 id
  final String movieId;

  @override
  State<MovieDetailPage> createState() => _MovieDetailPageState();
}

class _MovieDetailPageState extends State<MovieDetailPage> {
  Future<void> _openEditor(BuildContext context) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => MovieEditPage(movieId: widget.movieId),
      ),
    );
    // 编辑页里删除了这部电影 → 详情页随之关闭
    if (result == kEditResultDeleted && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // H6/M6：select 只订阅影库与演员表引用；个人页/书库等无关变化不再触发重建。
    // 注意演员表必须订阅——演员改名/删除不影响 movieList 引用，
    // 不订阅会导致详情页演员条不刷新（actor_flow_test 回归教训）。
    final library = context.read<LibraryProvider>();
    final movies =
        context.select<LibraryProvider, List<Movie>>((p) => p.movieList);
    final actors =
        context.select<LibraryProvider, List<Actor>>((p) => p.actors);
    final matches = movies.where((m) => m.id == widget.movieId).toList();
    final movie = matches.isEmpty ? null : matches.first;
    // 演员区数据源：id → 实体解析（悬空引用由 actorsByIds 静默跳过）。
    // seed 阶段 id=name，此处解析前后显示完全一致——本步是纯消费端重构。
    final castActors = movie == null
        ? const <Actor>[]
        : (movie.actorIds == null
            ? const <Actor>[]
            : library.actorsByIds(movie.actorIds!, source: actors));
    // 展示用条目：优先 cast 快照（带角色名与 TMDB 头像），回退本地实体
    final castItems = movie == null
        ? const <CastItem>[]
        : _buildCastItems(movie, castActors);
    // 剧照缓存（TMDB images.backdrops 落盘；为空时横滑区显示空态）
    final stills = movie?.stills ?? const <MediaRef>[];

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
                    _buildHeaderCard(movie),
                    const SizedBox(height: 26),
                    // ---------- 电影简介 ----------
                    if (movie.description != null &&
                        movie.description!.isNotEmpty) ...[
                      _sectionTitle(context, '电影简介'),
                      const SizedBox(height: 10),
                      ExpandableSynopsis(
                        text: movie.description!,
                        boxed: true,
                      ),
                      const SizedBox(height: 26),
                    ],
                    // ---------- 补充元数据卡（紧接简介下方，4 项）----------
                    _buildMetaCard(movie),
                    const SizedBox(height: 26),
                    // ---------- 主创 / 演员（横滑 + 全部入口）----------
                    if (castItems.isNotEmpty) ...[
                      _sectionTitle(
                        context,
                        '主创 / 演员',
                        actionLabel: '全部 ${castItems.length}',
                        onAction: () => _openCastSheet(context, movie, castItems),
                      ),
                      const SizedBox(height: 12),
                      _buildCastRow(castItems),
                      const SizedBox(height: 26),
                    ],
                    // ---------- 我的影评 ----------
                    _sectionTitle(context, AppStrings.myReview),
                    const SizedBox(height: 10),
                    _buildReviewCard(movie),
                    const SizedBox(height: 26),
                    // ---------- 剧照（横滑 + 全部入口）----------
                    _sectionTitle(
                      context,
                      '剧照',
                      actionLabel: stills.isEmpty ? null : '全部 ${stills.length}',
                      onAction:
                          stills.isEmpty ? null : () => _openStillsPage(movie),
                    ),
                    const SizedBox(height: 12),
                    _buildStillsRow(stills),
                  ],
                ),
              ),
            ),
    );
  }

  // ---------- 头部：海报 + 标题 / 英文名 / 导演 / 我的评分 / 类型标签 ----------

  Widget _buildHeaderCard(Movie movie) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 海报
          Container(
            width: 116,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: MediaCover(
                media: movie.poster,
                title: movie.title,
                emoji: movie.emoji ?? '',
                hue: movie.coverHue,
                aspectRatio: 3 / 4,
                borderRadius: 0,
                fontSize: 44,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // 右侧信息列
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movie.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 5),
                if (movie.englishTitle != null &&
                    movie.englishTitle!.isNotEmpty)
                  Text(
                    movie.englishTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                if (movie.director != null && movie.director!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    movie.director!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _buildRatingCard(movie),
                const SizedBox(height: 12),
                // 类型标签
                if (movie.genres != null && movie.genres!.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final g in movie.genres!) InfoChip(label: g),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 我的评分卡 ----------

  Widget _buildRatingCard(Movie movie) {
    final rating = movie.rating;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: rating == null
          ? Row(
              children: [
                Icon(Icons.star_border_rounded,
                    size: 16, color: context.colors.textMuted),
                const SizedBox(width: 6),
                Text(
                  AppStrings.unrated,
                  style: TextStyle(
                      color: context.colors.textMuted, fontSize: 12.5),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.myRating,
                  style: TextStyle(
                    color: context.colors.success,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    RatingStars(rating: rating, size: 19),
                    const SizedBox(width: 8),
                    Text(
                      rating.toStringAsFixed(1),
                      style: TextStyle(
                        color: context.colors.star,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  // ---------- 补充元数据卡（3 列单行）----------
  // 三项：看过日期 / 上映时间 / 片长（剧情类型已上移至头部标签）

  Widget _buildMetaCard(Movie movie) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.outline, width: 0.7),
      ),
      child: Row(
        children: [
          Expanded(
            child: MetaCell(
              icon: Icons.visibility_rounded,
              label: '看过日期',
              value: movie.watchDateText.isEmpty
                  ? '—'
                  : movie.watchDateText,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MetaCell(
              icon: Icons.calendar_month_rounded,
              label: AppStrings.releaseDate,
              value: movie.releaseDateText.isEmpty
                  ? '${movie.year}'
                  : movie.releaseDateText,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MetaCell(
              icon: Icons.timer_outlined,
              label: '片长',
              value: movie.durationText.isEmpty ? '—' : movie.durationText,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 主创 / 演员（横向滚动，点击进演员作品页）----------

  Widget _buildCastRow(List<CastItem> items) {
    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (ctx, i) {
          final item = items[i];
          final hasChar = item.character != null && item.character!.isNotEmpty;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 未收录进本地演员库的（actorId 为空）不响应点击——跳过去也是空页
            onTap: item.actorId == null
                ? null
                : () => Navigator.of(ctx).push(
                      MaterialPageRoute(
                        builder: (_) => ActorDetailPage(actorId: item.actorId!),
                      ),
                    ),
            child: Column(
              children: [
                CastAvatar(name: item.name, photoUrl: item.photoUrl),
                const SizedBox(height: 8),
                SizedBox(
                  width: 84,
                  child: Text(
                    item.name,
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
                if (hasChar) ...[
                  const SizedBox(height: 3),
                  SizedBox(
                    width: 84,
                    child: Text(
                      item.character!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style:  TextStyle(
                        color: context.colors.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// 构建演员展示条目：优先 [Movie.cast] 快照（含角色名 + TMDB 头像），
  /// 无快照时回退本地 Actor 实体（旧数据 / 手动添加）。
  ///
  /// 快照里的姓名逐个匹配本地库拿 actorId，供点击跳转作品页复用
  /// 现有的 [ActorDetailPage]（其作品列表按 actorIds 反查，不落盘）。
  List<CastItem> _buildCastItems(Movie movie, List<Actor> localActors) {
    final items = <CastItem>[];
    final snapshot = movie.cast;
    if (snapshot != null && snapshot.isNotEmpty) {
      // 快照优先：带角色名与 TMDB 头像
      for (final c in snapshot) {
        final hit = _matchActor(localActors, c.name);
        items.add(CastItem(
          name: c.name,
          character: c.character,
          photoUrl: c.profilePath,
          actorId: hit?.id,
        ));
      }
    } else {
      // 回退：本地实体（无角色名；头像取 Actor.avatar 的网络地址）
      for (final a in localActors) {
        items.add(CastItem(
          name: a.name,
          photoUrl: a.avatar?.remoteUrl,
          actorId: a.id,
        ));
      }
    }
    // 导演置顶（演员表里已有的不重复加）：弹层据此把该条目分到「导演」组
    final director = movie.director?.trim();
    if (director != null &&
        director.isNotEmpty &&
        items.every((it) => it.name != director)) {
      final hit = _matchActor(localActors, director);
      items.insert(
        0,
        CastItem(
          name: director,
          character: CastItem.kDirectorRole,
          photoUrl: hit?.avatar?.remoteUrl,
          actorId: hit?.id,
        ),
      );
    }
    return items;
  }

  /// 按姓名精确匹配本地演员库（同名取第一个），用于把展示条目挂回实体 id
  static Actor? _matchActor(List<Actor> actors, String name) {
    for (final a in actors) {
      if (a.name == name) return a;
    }
    return null;
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

  // ---------- 剧照（横向滚动；真实 TMDB 剧照，无数据时显示空态）----------

  Widget _buildStillsRow(List<MediaRef> stills) {
    if (stills.isEmpty) {
      return Container(
        height: 96,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.outline, width: 0.7),
        ),
        child:  Center(
          child: Text(
            AppStrings.noStills,
            style: TextStyle(color: context.colors.textMuted, fontSize: 13),
          ),
        ),
      );
    }
    return SizedBox(
      height: 104,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: stills.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 166,
            height: 104,
            child: StillImage(ref: stills[i]),
          ),
        ),
      ),
    );
  }

  /// 打开演职员表弹层（跳转交给回调，避免 widgets → screens 循环依赖）
  void _openCastSheet(BuildContext context, Movie movie, List<CastItem> items) {
    showCastBottomSheet(
      context: context,
      cast: items,
      movieTitle: movie.title,
      onTapActor: (actorId) => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ActorDetailPage(actorId: actorId),
        ),
      ),
    );
  }

  /// 打开剧照全量页
  void _openStillsPage(Movie movie) {
    final poster = movie.poster;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MovieStillsPage(
          title: movie.title,
          backdrops: movie.stills ?? const <MediaRef>[],
          // 主海报并入「海报」Tab（可能是用户上传的本地图，非 TMDB 网络图）
          posters: poster == null ? const <MediaRef>[] : <MediaRef>[poster],
        ),
      ),
    );
  }

  // ---------- 区块标题 ----------

  /// 区块标题（[actionLabel] + [onAction] 存在时右侧显示「全部 N >」入口）
  Widget _sectionTitle(
    BuildContext context,
    String text, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
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
        if (actionLabel != null) ...[
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel,
                  style:  TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                 Icon(Icons.chevron_right_rounded,
                    size: 18, color: context.colors.textMuted),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 演员圆形头像：有图显图，无图用**中性灰渐变** + 姓名首字
///
/// 旧实现用 coverGradient(hue) 按序号生成彩色块，饱和度偏高且偏灰绿/棕；
/// 这里改为近零饱和的灰阶渐变（随主题明暗取两档），视觉上更克制。
