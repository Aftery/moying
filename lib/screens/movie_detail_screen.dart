import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../config/edit_results.dart';
import '../models/actor.dart';
import '../models/cast_item.dart';
import '../models/media_ref.dart';
import '../models/movie.dart';
import '../providers/library_provider.dart';
import '../widgets/cast_bottom_sheet.dart';
import '../widgets/media_cover.dart';
import '../widgets/rating_stars.dart';
import 'actor_detail_screen.dart';
import 'movie_edit_screen.dart';
import 'movie_stills_screen.dart';

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
                    _sectionTitle(context, '我的影评'),
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
                        builder: (_) => ActorDetailScreen(actorId: item.actorId!),
                      ),
                    ),
            child: Column(
              children: [
                _CastAvatar(name: item.name, photoUrl: item.photoUrl),
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
  /// 现有的 [ActorDetailScreen]（其作品列表按 actorIds 反查，不落盘）。
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
            '暂无剧照',
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
            child: _StillImage(ref: stills[i]),
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
          builder: (_) => ActorDetailScreen(actorId: actorId),
        ),
      ),
    );
  }

  /// 打开剧照全量页
  void _openStillsPage(Movie movie) {
    final poster = movie.poster;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MovieStillsScreen(
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
class _CastAvatar extends StatelessWidget {
  const _CastAvatar({
    required this.name,
    this.photoUrl,
  });

  /// 头像半径（详情页横滑条固定尺寸，无第二个调用点故不作参数）
  static const double radius = 31;

  final String name;

  /// 头像地址（空 = 走占位）
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    const size = radius * 2;
    final url = photoUrl;
    final hasPhoto = url != null && url.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.outline, width: 0.8),
      ),
      // 圆形裁剪由容器承担，图片本身无需再套 ClipOval
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: 200,
              // TMDB 图源失效（404 / 断网）时回退占位，而不是留一个透明圆圈
              errorBuilder: (_, __, ___) =>
                  _CastAvatarFallback(name: name, size: size),
            )
          : _CastAvatarFallback(name: name, size: size),
    );
  }
}

/// 头像占位：中性灰渐变 + 姓名首字
class _CastAvatarFallback extends StatelessWidget {
  const _CastAvatarFallback({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF565664), Color(0xFF33333F)]
              : const [Color(0xFFD4D4DE), Color(0xFFAEAEBB)],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: isDark ? const Color(0xFFD8D8E2) : const Color(0xFF5A5A6A),
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 剧照单图：网络图优先，加载中 / 失败 / 无图统一走中性灰占位
///
/// 剧照目前只来自 TMDB images（网络引用）；本地图（用户上传）尚未接入，
/// 命中 localFile 时同样走占位，避免相对路径未解析导致空白块。
class _StillImage extends StatelessWidget {
  const _StillImage({required this.ref});

  final MediaRef ref;

  @override
  Widget build(BuildContext context) {
    final url = ref.remoteUrl;
    if (url == null || url.isEmpty) return _placeholder(context);
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : _placeholder(context),
      errorBuilder: (_, __, ___) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF3A3A46), Color(0xFF25252F)]
              : const [Color(0xFFE2E2EA), Color(0xFFCACAD4)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.movie_filter_rounded,
          color: isDark ? Colors.white24 : Colors.black26,
          size: 30,
        ),
      ),
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

  /// 上次测量的可用宽度（M23：文本或宽度变化才重测，避免每次 rebuild 重复排版）
  double _lastWidth = -1;

  /// M11：postFrame 调度去重，避免首帧前多次 rebuild 重复入队测量任务
  bool _measureScheduled = false;

  /// 测量简介是否超过 [_foldLines] 行，结果按（文本, 宽度）缓存。
  ///
  /// 排版是同步重活，不在 build 阶段执行——由 postFrame 调度本方法，
  /// 避免长简介下每次 rebuild 都触发一次 TextPainter.layout()。
  void _measure(double maxWidth) {
    _measured = true;
    _measureScheduled = false;
    _lastWidth = maxWidth;
    final painter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: TextStyle(
          fontSize: 14,
          height: 1.7,
          color: context.colors.textSecondary,
        ),
      ),
      maxLines: _foldLines,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final needFold = painter.didExceedMaxLines;
    if (needFold != _overflow && mounted) {
      setState(() => _overflow = needFold);
    }
  }

  @override
  void didUpdateWidget(covariant _ExpandableSynopsis oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 内容变化（如编辑后返回）时重新测量折叠状态
    if (oldWidget.text != widget.text) {
      _measured = false;
      _measureScheduled = false;
      _lastWidth = -1;
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
          // M23：排版不在 build 阶段同步执行，交给 postFrame（_measure 内缓存结果）
          if (!_measured || constraints.maxWidth != _lastWidth) {
            if (!_measureScheduled) {
              _measureScheduled = true;
              final width = constraints.maxWidth;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _measure(width);
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