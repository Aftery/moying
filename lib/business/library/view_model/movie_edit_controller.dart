import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../../component/media/model/media_ref.dart';
import '../../shared/model/data_source.dart' show CastMember;
import '../../shared/model/actor.dart';
import '../../shared/model/movie.dart';
import 'library_provider.dart';

/// 电影编辑页的表单状态与业务逻辑（M-5b，与 [BookEditController] 同构）。
///
/// 从 State 里搬出来的是三件事：
/// 1. **表单字段**（标题 / 英文名 / 导演 / 片长 / 影评 / 类型标签 / 海报草稿）；
/// 2. **联动与推导**（导演 ↔ 演员槽位自动同步、类型联想候选、演员吸附与新建）；
/// 3. **保存组装**（海报落盘 → 组装 `Movie` 或 `copyWith` 原片）。
///
/// State 只保留 Widget 构建、弹窗与导航，于是上述规则可以脱离 Widget 树直接单测。
///
/// **通知约定**：控制器不做 `setState`；需要重建的入口由页面决定——
/// 纯数据方法返回「是否真的改了」（如 [addGenre] / [commitGenreText]），
/// 页面据此 `setState`，避免无变化时的多余重建。
class MovieEditController extends ChangeNotifier {
  MovieEditController({
    this.movieId,
    Movie? initialMovie,
    List<Actor> initialActors = const <Actor>[],
  })  : _movie = initialMovie,
        notFound = movieId != null && initialMovie == null,
        rating = initialMovie?.rating ?? 0,
        selectedGenres =
            Set<String>.of(initialMovie?.genres ?? const <String>[]) {
    titleCtrl = TextEditingController(text: _movie?.title ?? '');
    englishCtrl = TextEditingController(text: _movie?.englishTitle ?? '');
    directorCtrl = TextEditingController(text: _movie?.director ?? '');
    durationCtrl =
        TextEditingController(text: _movie?.duration?.toString() ?? '');
    reviewCtrl = TextEditingController(text: _movie?.review ?? '');
    releaseDate = _movie?.releaseDate;
    watchDate = _movie?.watchDate;
    // 演职员快照 / 剧照：沿用原值（用户不重新检索时不该丢），检索回填时被覆盖
    cast = _movie?.cast;
    stills = _movie?.stills;
    // 编辑模式回填：actorIds → 实体解析 → 显示姓名（悬空引用静默丢弃）。
    // 这是「渲染 actorIds 的地方统一走解析」的第二个渲染点，与详情页同步切换，
    // 确保用户新建的 id≠name 演员在回填时显示名字而非一串乱码 id。
    for (final actor in initialActors) {
      actorSlots.add(ActorSlot(
        ctrl: TextEditingController(text: actor.name),
        picked: actor,
      ));
    }
    // 编辑模式回填后同步一次导演（首帧前执行，无需通知）；
    // 新增模式导演为空 → no-op
    applyDirectorSync();
  }

  /// 编辑目标 id；null = 新增模式
  final String? movieId;

  /// true = 编辑模式（保存走 `updateMovie`，且显示删除入口）
  bool get isEditMode => movieId != null;

  /// 编辑模式但电影已被并发删除（哨兵：防止 `movie!` 崩溃）
  final bool notFound;

  final Movie? _movie;

  /// 编辑模式的原片（新增模式为 null）
  Movie? get movie => _movie;

  /// 防止双击重复提交
  bool saving = false;

  // ---------- 表单字段 ----------

  late final TextEditingController titleCtrl;
  late final TextEditingController englishCtrl;
  late final TextEditingController directorCtrl;
  late final TextEditingController durationCtrl;
  late final TextEditingController reviewCtrl;

  /// 剧情类型联想输入（多选标签：点选候选 / 自定义回车 / 保存前兜底提交）
  final TextEditingController genreCtrl = TextEditingController();
  final FocusNode genreFocus = FocusNode();

  /// 导演框焦点（失焦触发导演 → 演员槽位自动同步）
  final FocusNode directorFocus = FocusNode();

  /// 网络海报地址输入
  final TextEditingController posterUrlCtrl = TextEditingController();

  DateTime? releaseDate;
  DateTime? watchDate;
  double rating;

  /// 已选类型标签（去重，顺序即展示顺序）
  final Set<String> selectedGenres;

  /// 影评字数上限（输入框 maxLength 与右下角计数共用）
  static const int reviewMaxChars = 5000;

  /// 「添加“X”」哨兵：候选无匹配时提供可点的自定义入口（回车提交同语义）
  static const String genreCreateSentinel = '__genre_create__';

  /// 联想「新建」哨兵 id：无精确命中时作为候选尾项渲染新建行。
  /// 实体演员 id 恒为 `a_` + 微秒时间戳，与此值绝不冲突。
  static const String actorCreateId = '__actor_create__';

  /// 当前导演自动槽的文本（用于识别用户是否改过该槽位）
  String? directorAutoName;

  /// 用户手动删除自动槽时的导演名——同导演不再自动弹回
  String? directorAutoDismissed;

  /// 演员槽位（每个槽位 = 联想输入框 + 已解析实体）
  ///
  /// 槽位文本与实体分离：文本展示姓名，[ActorSlot.picked] 记录解析出的实体 id。
  /// 回填/联想/新建都会把 picked 置为实体；保存时未解析的自由文本做
  /// 「精确吸附已有 + 兜底新建」，保证 actorIds 永远存 id 而非文本。
  final List<ActorSlot> actorSlots = [];

  /// 从相册选中、尚未复制进 images/ 的海报（保存时 attach）
  File? pendingPosterFile;

  /// 海报是否被用户动过（选图/填 URL/移除）——决定保存时沿用原图还是覆盖
  bool posterEdited = false;

  /// 演职员表快照（保存时写入 `Movie.cast`）
  ///
  /// 编辑模式进页面时先从原 Movie 载入——用户不重新检索也应保留既有快照；
  /// 检索回填时用 TMDB credits 覆盖。
  List<CastMember>? cast;

  /// 剧照缓存（保存时写入 `Movie.stills`，TMDB images.backdrops 的网络引用）
  List<MediaRef>? stills;

  /// 数据溯源标记（保存时写入 `Movie.source`，如 `'tmdb:123'`）
  String? sourceTag;

  // ---------- 导演 → 演员槽位自动同步 ----------

  /// 同步的纯数据操作（不含通知；回填后也复用）
  ///
  /// - 导演非空：自动槽文本跟随导演；无自动槽且演员区无同名 → 第 0 位插入；
  ///   用户删过该导演的自动槽（[directorAutoDismissed]）→ 尊重不弹回
  /// - 导演清空：移除自动槽
  /// - 用户改过自动槽文本 → 该槽降级为普通槽（自定义优先，另起自动槽）
  void applyDirectorSync() {
    final director = directorCtrl.text.trim();
    ActorSlot? autoSlot;
    for (final s in actorSlots) {
      if (s.autoFromDirector) {
        autoSlot = s;
        break;
      }
    }
    if (autoSlot != null && autoSlot.ctrl.text.trim() != directorAutoName) {
      autoSlot.autoFromDirector = false; // 用户改过 → 降级
      autoSlot = null;
      directorAutoName = null;
    }
    if (director.isEmpty) {
      if (autoSlot != null) {
        autoSlot.dispose();
        actorSlots.remove(autoSlot);
      }
      directorAutoName = null;
      return;
    }
    if (autoSlot != null) {
      if (autoSlot.ctrl.text != director) {
        autoSlot.ctrl.text = director;
      }
      return;
    }
    final hasSame = actorSlots.any((s) => s.ctrl.text.trim() == director);
    if (!hasSame && director != directorAutoDismissed) {
      final slot = ActorSlot(ctrl: TextEditingController(text: director))
        ..autoFromDirector = true;
      actorSlots.insert(0, slot);
      directorAutoName = director;
    }
  }

  // ---------- 类型联想输入 + 多选标签 ----------

  /// 类型联想候选：预设 ∪ 影库实际用过的类型（去重，预设在前），剔除已选
  List<String> genreCandidates(List<String> usedGenres) => <String>{
        ...kMovieCategories,
        ...usedGenres,
      }.where((g) => !selectedGenres.contains(g)).toList(growable: false);

  /// 联想规则：空输入 → 全部候选；有输入 → 包含匹配。
  /// 精确命中的候选置顶（保证回车确认的就是它）；无精确命中且未选过时
  /// 追加「添加」哨兵——空 options 不渲染浮层，哨兵保证自定义值有可点入口。
  ///
  /// 哨兵选项编码为 `genreCreateSentinel + 用户输入`：RawAutocomplete 选中
  /// 时会先把 displayString 写进输入框，onSelected 里再读输入框会把哨兵
  /// 原文当类型吞进去（踩过），所以真实值必须随选项携带（同演员哨兵做法）。
  List<String> genreOptionsFor(String rawQuery, List<String> usedGenres) {
    final q = rawQuery.trim();
    final candidates = genreCandidates(usedGenres);
    if (q.isEmpty) return candidates;
    final options = candidates.where((c) => c.contains(q)).toList();
    if (options.contains(q)) {
      options
        ..remove(q)
        ..insert(0, q);
    } else if (!selectedGenres.contains(q)) {
      options.add('$genreCreateSentinel$q');
    }
    return options;
  }

  /// 添加一个类型标签（空串/已选静默忽略，天然去重）；返回是否真的新增
  bool addGenre(String genre) {
    final g = genre.trim();
    if (g.isEmpty || selectedGenres.contains(g)) return false;
    selectedGenres.add(g);
    return true;
  }

  /// 把输入框里未提交的文本收进标签并清空输入框（无文本时跳过）；
  /// 返回是否真的新增（标签已存在时仅清空输入框）
  bool commitGenreText() {
    final text = genreCtrl.text.trim();
    if (text.isEmpty) return false;
    final added = addGenre(text);
    genreCtrl.clear();
    return added;
  }

  /// 选中一个联想选项（含「添加“X”」哨兵）→ 收进标签并清空输入框
  bool selectGenreOption(String option) {
    final raw = option.startsWith(genreCreateSentinel)
        ? option.substring(genreCreateSentinel.length)
        : option;
    final added = addGenre(raw);
    genreCtrl.clear();
    return added;
  }

  // ---------- 演员槽位 ----------

  /// 新增一个空槽位
  void addActorSlot() => actorSlots.add(ActorSlot());

  /// 移除槽位；删除的是导演自动槽时记录导演名，同导演不再自动弹回
  void removeActorSlot(ActorSlot slot) {
    if (slot.autoFromDirector) {
      directorAutoDismissed = directorCtrl.text.trim();
      directorAutoName = null;
      slot.autoFromDirector = false;
    }
    slot.dispose();
    actorSlots.remove(slot);
  }

  /// 槽位头像字符：有文本取首字，空文本显示序号
  String slotInitial(ActorSlot slot, int index) {
    final text = slot.ctrl.text.trim();
    return text.isEmpty ? '${index + 1}' : text.characters.first;
  }

  /// 按姓名生成稳定的占位色相
  static double actorHue(String name) =>
      (name.codeUnits.fold<int>(0, (s, c) => s + c) % 360).toDouble();

  /// 联想候选：库中名字包含输入（排除其他槽位已选，允许本槽重选），
  /// 输入非空且无精确命中时在尾部追加「新建」哨兵——保证 overlay 恒可展开。
  List<Actor> actorOptions(
    ActorSlot self,
    String rawQuery,
    LibraryProvider lib,
  ) {
    final query = rawQuery.trim();
    final taken = actorSlots
        .where((s) => !identical(s, self))
        .map((s) => s.picked?.id)
        .whereType<String>()
        .toSet();
    final matches = lib.actors
        .where((a) => !taken.contains(a.id) && a.name.contains(query))
        .toList();
    if (query.isNotEmpty && !matches.any((a) => a.name == query)) {
      matches.add(Actor(
        id: actorCreateId,
        name: query,
        createdAt: DateTime(1970),
      ));
    }
    return matches;
  }

  /// 候选选中：命中「新建」哨兵 → 建实体并落库；否则直接吸附。
  /// 回车落在哨兵上即「创建实体」——这是录入新演员的唯一入口。
  void pickActor(ActorSlot slot, Actor choice, LibraryProvider lib) {
    if (choice.id == actorCreateId) {
      final now = DateTime.now();
      final created = Actor(
        id: 'a_${now.microsecondsSinceEpoch}',
        name: choice.name,
        createdAt: now,
      );
      lib.addActor(created);
      slot.picked = created;
    } else {
      slot.picked = choice;
    }
  }

  /// 槽位 → actorIds：已解析槽位直接用实体 id；未解析的自由文本先精确吸附
  /// 库中同名演员（防「周星驰/周星弛」裂成两个实体），仍无则兜底新建。
  /// 全部为空返回 null（与旧契约一致：空引用不落盘）。
  List<String>? collectActorIds(LibraryProvider lib) {
    final ids = <String>[];
    for (final slot in actorSlots) {
      final text = slot.ctrl.text.trim();
      if (text.isEmpty) continue;
      final picked = slot.picked;
      final String id;
      if (picked != null && picked.name == text) {
        id = picked.id;
      } else {
        Actor? exact;
        for (final a in lib.actors) {
          if (a.name == text) {
            exact = a;
            break;
          }
        }
        if (exact != null) {
          id = exact.id;
          slot.picked = exact;
        } else {
          final now = DateTime.now();
          final url = slot.avatarUrl;
          final created = Actor(
            id: 'a_${now.microsecondsSinceEpoch}',
            name: text,
            // 检索带回的 TMDB 头像直接落库；无头像时保持 null（UI 回退占位）
            avatar: (url == null || url.isEmpty) ? null : MediaRef.network(url),
            createdAt: now,
          );
          lib.addActor(created);
          slot.picked = created;
          id = created.id;
        }
      }
      if (!ids.contains(id)) ids.add(id);
    }
    return ids.isEmpty ? null : ids;
  }

  // ---------- 海报预览 ----------

  /// 海报预览输入：编辑态未改动 → 原图；动过后 → URL 文本（网络）或空（占位）；
  /// 选中本地图时由 `MediaCover.pendingFile` 优先展示，[media] 归位 null。
  MediaRef? get previewPosterMedia {
    if (posterEdited) {
      final url = posterUrlCtrl.text.trim();
      return url.isEmpty ? null : MediaRef.network(url);
    }
    return _movie?.poster;
  }

  // ---------- 检索回填（演职员 / 剧照快照）----------

  /// 把检索详情里的主演与剧照落进表单态：
  /// - 主演 → 演员槽位（跳过已存在的同名；头像随槽位带入，新建 / 吸附本地
  ///   Actor 时一并落库，演员页也能显示真头像）；
  /// - 演职员快照 / 剧照**非空才覆盖**——详情源缺图时不该清掉既有数据。
  void applyCastDetail(List<CastMember> detailCast, List<String> backdropUrls) {
    for (final member in detailCast) {
      final name = member.name.trim();
      if (name.isEmpty) continue;
      if (actorSlots.any((s) => s.ctrl.text.trim() == name)) continue;
      actorSlots.add(ActorSlot(
        ctrl: TextEditingController(text: name),
        avatarUrl: member.profilePath,
      ));
    }
    if (detailCast.isNotEmpty) cast = detailCast;
    if (backdropUrls.isNotEmpty) {
      stills = backdropUrls.map(MediaRef.network).toList();
    }
  }

  // ---------- 校验与保存组装 ----------

  /// 保存前的表单校验；返回错误文案（null = 通过）
  String? validate() =>
      titleCtrl.text.trim().isEmpty ? '电影标题不能为空' : null;

  /// 组装待保存的 `Movie`（含海报落盘）。
  ///
  /// 返回 null = 无法组装（编辑模式下原片已不存在）。新增模式生成新实体，
  /// 编辑模式在原片基础上 `copyWith`。写库与导航由页面负责。
  Future<Movie?> composeMovie(LibraryProvider provider) async {
    // 输入框里还没回车/点选的自定义类型先收进标签，再统计
    commitGenreText();
    final title = titleCtrl.text.trim();
    final ratingValue = rating > 0 ? rating : null;
    final duration = int.tryParse(durationCtrl.text.trim());
    final actorIds = collectActorIds(provider);
    final review = reviewCtrl.text.trim();
    final genres = selectedGenres.isEmpty ? null : selectedGenres.toList();
    final englishTitle = _nullable(englishCtrl.text);
    final director = _nullable(directorCtrl.text);

    final original = _movie;
    if (isEditMode && original == null) return null;
    // 新增/编辑统一先在保存时刻确定 id，供海报复制落盘
    final id = isEditMode
        ? original!.id
        : 'm_${DateTime.now().microsecondsSinceEpoch}';
    final poster = await _resolveDraftPoster(provider, id);

    if (isEditMode) {
      return original!.copyWith(
        title: title,
        englishTitle: englishTitle,
        director: director,
        // 有评分 → 已看；把评分清空时从「已评分」降级为「看过」
        status: ratingValue != null
            ? MovieStatus.rated
            : (original.status == MovieStatus.rated
                ? MovieStatus.watched
                : original.status),
        rating: ratingValue,
        poster: poster,
        releaseDate: releaseDate,
        watchDate: watchDate,
        duration: duration,
        genres: genres,
        review: review.isEmpty ? null : review,
        actorIds: actorIds,
        cast: cast,
        stills: stills,
        // 未重新检索时保留原溯源标记（copyWith 传 null 会清字段）
        source: sourceTag ?? original.source,
      );
    }
    final now = DateTime.now();
    return Movie(
      id: id,
      title: title,
      englishTitle: englishTitle,
      year: releaseDate?.year ?? now.year,
      director: director,
      status: ratingValue != null ? MovieStatus.rated : MovieStatus.watchlist,
      rating: ratingValue,
      coverHue: original?.coverHue ?? 165,
      emoji: original?.emoji,
      poster: poster,
      releaseDate: releaseDate,
      watchDate: watchDate,
      duration: duration,
      genres: genres,
      review: review.isEmpty ? null : review,
      actorIds: actorIds,
      cast: cast,
      stills: stills,
      source: sourceTag,
    );
  }

  /// 计算保存时的海报引用（与书编辑 `_resolveDraftCover` 同构）：
  /// 选中本地图 → 先复制进 images/ 再返回 local；没动过 → 沿用原图；
  /// 动过且填了 URL → **先缓存到本地**（成功 = local+remote 双引用，
  /// 展示优先读本地、离线回退 URL；缓存失败 = 纯网络引用）；URL 空 → 移除。
  Future<MediaRef?> _resolveDraftPoster(
    LibraryProvider provider,
    String id,
  ) async {
    final pending = pendingPosterFile;
    if (pending != null) {
      final rel = await provider.attachImage(pending, id);
      return rel == null ? null : MediaRef.local(rel);
    }
    if (!posterEdited) return _movie?.poster;
    final url = posterUrlCtrl.text.trim();
    if (url.isEmpty) return null;
    final cached = await provider.cacheRemoteImage(url, 'movie_poster');
    if (cached != null) return MediaRef(localFile: cached, remoteUrl: url);
    return MediaRef.network(url);
  }

  /// 去空白后为空 → null（表单文本字段的统一归一）
  static String? _nullable(String raw) {
    final t = raw.trim();
    return t.isEmpty ? null : t;
  }

  @override
  void dispose() {
    titleCtrl.dispose();
    englishCtrl.dispose();
    directorCtrl.dispose();
    durationCtrl.dispose();
    reviewCtrl.dispose();
    for (final slot in actorSlots) {
      slot.dispose();
    }
    genreCtrl.dispose();
    genreFocus.dispose();
    directorFocus.dispose();
    posterUrlCtrl.dispose();
    super.dispose();
  }
}

/// 编辑页演员槽位：输入控制器 + 焦点 + 已解析实体（可空）。
///
/// [picked] 为空表示当前文本尚未吸附到实体——保存时由
/// [MovieEditController.collectActorIds] 做「精确吸附已有 / 兜底新建」。
class ActorSlot {
  ActorSlot({TextEditingController? ctrl, this.picked, this.avatarUrl})
      : ctrl = ctrl ?? TextEditingController(),
        focus = FocusNode();

  final TextEditingController ctrl;
  final FocusNode focus;

  /// 已解析实体（回填 / 联想选中 / 新建产生）；null = 自由文本
  Actor? picked;

  /// 检索带回的头像地址（TMDB profile_path 完整 URL）
  ///
  /// 仅用于**新建**本地 Actor 时落库；吸附到已有 Actor 时不覆盖其头像
  /// （用户可能手动换过头像，不该被网络数据冲掉）。
  final String? avatarUrl;

  /// true = 由导演框自动挂载的槽位（导演失焦/回车同步；用户改过文本或删除后降级）
  bool autoFromDirector = false;

  void dispose() {
    ctrl.dispose();
    focus.dispose();
  }
}
