import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../config/edit_results.dart';
import '../models/actor.dart';
import '../models/data_source.dart';
import '../models/media_ref.dart';
import '../models/movie.dart';
import '../providers/data_source_provider.dart';
import '../providers/library_provider.dart';
import '../widgets/edit_form_widgets.dart';
import '../widgets/media_cover.dart';
import '../widgets/quick_search_panel.dart';

/// 片长输入净化正则（提为顶层常量，避免每字符输入重建）
final _nonDigitRegex = RegExp(r'[^0-9]');

/// 片长输入净化：仅保留 ASCII 数字，超 4 位截断。
///
/// 不走 [TextInputFormatter]——搜狗等国产输入法经格式化器过滤时组合输入
/// 中间态会被吞掉，表现为"键盘能弹、字符进不去"；改为 onChanged 收敛后
/// 输入通道与普通文本框完全一致。
String sanitizeDurationInput(String raw) {
  final digits = raw.replaceAll(_nonDigitRegex, '');
  return digits.length > 4 ? digits.substring(0, 4) : digits;
}

/// 电影修改 / 新增界面（双模式）
///
/// - 传入 [movieId] → 编辑模式：AppBar「修改电影」，显示删除按钮，保存走 `updateMovie`
/// - 不传 [movieId] → 新增模式：AppBar「添加电影」，隐藏删除按钮，保存走 `addMovie`
///
/// 布局对齐参考图 3：
/// - 顶部封面预览 + 叠加「更改封面」上传按钮
/// - 标题 / 导演输入框、上映/看过日期选择、片长数字框（分钟后缀）
/// - 剧情类型 Tag 多选（FilterChip 高亮）、评分 Slider + 实时星级点亮
/// - 演员信息动态增删、我的影评 Textarea + 字数统计（/5000）
/// - 底部：蓝色「保存修改」（新增模式为「保存」）/ 灰色「取消」/ 红色「删除电影」（需二次确认）
class MovieEditScreen extends StatefulWidget {
  const MovieEditScreen({super.key, this.movieId});

  /// 待编辑电影 id；为空表示新增模式
  final String? movieId;

  @override
  State<MovieEditScreen> createState() => _MovieEditScreenState();
}

class _MovieEditScreenState extends State<MovieEditScreen> {
  static const int _reviewMaxChars = 5000;

  late final TextEditingController _titleCtrl;
  late final TextEditingController _englishCtrl;
  late final TextEditingController _directorCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _reviewCtrl;

  late DateTime? _releaseDate;
  late DateTime? _watchDate;
  late double _rating;
  late final Set<String> _selectedGenres;

  /// 剧情类型联想输入（多选标签：点选候选 / 自定义回车 / 保存前兜底提交）
  late final TextEditingController _genreCtrl;
  late final FocusNode _genreFocus;

  /// 导演框焦点（失焦触发导演 → 演员槽位自动同步）
  late final FocusNode _directorFocus;

  /// 当前导演自动槽的文本（用于识别用户是否改过该槽位）
  String? _directorAutoName;

  /// 用户手动删除自动槽时的导演名——同导演不再自动弹回
  String? _directorAutoDismissed;

  /// 防止双击重复提交
  bool _saving = false;

  /// 「添加“X”」哨兵：候选无匹配时提供可点的自定义入口（回车提交同语义）
  static const String _genreCreateSentinel = '__genre_create__';

  /// 演员槽位（每个槽位 = 联想输入框 + 已解析实体）
  ///
  /// 槽位文本与实体分离：文本展示姓名，[ActorSlot.picked] 记录解析出的实体 id。
  /// 回填/联想/新建都会把 picked 置为实体；保存时未解析的自由文本做
  /// 「精确吸附已有 + 兜底新建」，保证 actorIds 永远存 id 而非文本。
  final List<ActorSlot> _actorSlots = [];

  /// 从相册选中、尚未复制进 images/ 的海报（保存时 attach）
  File? _pendingPosterFile;

  /// 网络海报地址输入
  final TextEditingController _posterUrlCtrl = TextEditingController();

  /// 海报是否被用户动过（选图/填 URL/移除）——决定保存时沿用原图还是覆盖
  bool _posterEdited = false;

  Movie? _movie;
  bool get _isEditMode => widget.movieId != null;

  /// 编辑模式但电影已被并发删除（防 _movie! 崩溃）
  bool _notFound = false;

  // ---------- 快速检索（联网信息补全）状态 ----------

  /// 搜索词输入
  final TextEditingController _searchCtrl = TextEditingController();

  /// 搜索 debounce 定时器（800ms）
  Timer? _searchDebounce;

  /// 最近一次选中回填的搜索结果（结果行「已填充」标记）
  MovieSearchResult? _filledResult;

  /// 数据溯源标记（保存时写入 Movie.source，如 'tmdb:123'）
  String? _sourceTag;

  @override
  void initState() {
    super.initState();
    final provider = context.read<LibraryProvider>();
    final movieId = widget.movieId;
    Movie? movie;
    if (movieId != null) {
      final matches = provider.movieList.where((m) => m.id == movieId).toList();
      movie = matches.isEmpty ? null : matches.first;
      _notFound = movie == null; // 并发删除时防止 _movie! 崩溃
    }
    _movie = movie;

    _titleCtrl = TextEditingController(text: movie?.title ?? '');
    _englishCtrl = TextEditingController(text: movie?.englishTitle ?? '');
    _directorCtrl = TextEditingController(text: movie?.director ?? '');
    _durationCtrl =
        TextEditingController(text: movie?.duration?.toString() ?? '');
    _reviewCtrl = TextEditingController(text: movie?.review ?? '');
    _releaseDate = movie?.releaseDate;
    _watchDate = movie?.watchDate;
    _rating = movie?.rating ?? 0;
    _selectedGenres = Set.of(movie?.genres ?? const <String>[]);
    _genreCtrl = TextEditingController();
    _genreFocus = FocusNode();
    // 失焦时把未提交的输入收进标签，防止用户中途移开焦点丢输入
    _genreFocus.addListener(_handleGenreFocusChange);
    _directorFocus = FocusNode();
    // 导演失焦 → 自动同步到演员第 0 位（回车提交在导演输入框 onSubmitted 同样触发）
    _directorFocus.addListener(_handleDirectorFocusChange);
    // 编辑模式回填：actorIds → 实体解析 → 显示姓名（悬空引用静默丢弃）。
    // 这是"渲染 actorIds 的地方统一走解析"的第二个渲染点，与详情页同步切换，
    // 确保用户新建的 id≠name 演员在回填时显示名字而非一串乱码 id。
    for (final actor
        in provider.actorsByIds(movie?.actorIds ?? const <String>[])) {
      _actorSlots.add(ActorSlot(
        ctrl: TextEditingController(text: actor.name),
        picked: actor,
      ));
    }
    // 编辑模式回填后同步一次导演（首帧前执行，无需 setState）；
    // 新增模式导演为空 → no-op
    _applyDirectorSync();
    // 快速检索框：listener 驱动搜索（可读 IME composing，见 _onSearchCtrlChanged）
    _searchCtrl.addListener(_onSearchCtrlChanged);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _englishCtrl.dispose();
    _directorCtrl.dispose();
    _durationCtrl.dispose();
    _reviewCtrl.dispose();
    for (final slot in _actorSlots) {
      slot.dispose();
    }
    _genreCtrl.dispose();
    _genreFocus.dispose();
    _directorFocus.dispose();
    _posterUrlCtrl.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ---------- 导演 → 演员槽位自动同步 ----------

  /// 失焦时触发（onSubmitted 同语义）
  void _handleDirectorFocusChange() {
    if (!_directorFocus.hasFocus) _handleDirectorSync();
  }

  void _handleDirectorSync() {
    _applyDirectorSync();
    setState(() {});
  }

  /// 同步的纯数据操作（不含 setState；initState 回填后也复用）
  ///
  /// - 导演非空：自动槽文本跟随导演；无自动槽且演员区无同名 → 第 0 位插入；
  ///   用户删过该导演的自动槽（[_directorAutoDismissed]）→ 尊重不弹回
  /// - 导演清空：移除自动槽
  /// - 用户改过自动槽文本 → 该槽降级为普通槽（自定义优先，另起自动槽）
  void _applyDirectorSync() {
    final director = _directorCtrl.text.trim();
    ActorSlot? autoSlot;
    for (final s in _actorSlots) {
      if (s.autoFromDirector) {
        autoSlot = s;
        break;
      }
    }
    if (autoSlot != null && autoSlot.ctrl.text.trim() != _directorAutoName) {
      autoSlot.autoFromDirector = false; // 用户改过 → 降级
      autoSlot = null;
      _directorAutoName = null;
    }
    if (director.isEmpty) {
      if (autoSlot != null) {
        autoSlot.dispose();
        _actorSlots.remove(autoSlot);
      }
      _directorAutoName = null;
      return;
    }
    if (autoSlot != null) {
      if (autoSlot.ctrl.text != director) {
        autoSlot.ctrl.text = director;
      }
      return;
    }
    final hasSame = _actorSlots.any((s) => s.ctrl.text.trim() == director);
    if (!hasSame && director != _directorAutoDismissed) {
      final slot = ActorSlot(ctrl: TextEditingController(text: director))
        ..autoFromDirector = true;
      _actorSlots.insert(0, slot);
      _directorAutoName = director;
    }
  }

  // ---------- 日期选择 ----------

  Future<void> _pickDate({
    required DateTime? current,
    required ValueChanged<DateTime?> onPicked,
  }) async {
    final now = DateTime.now();
    final firstDate = DateTime(1900);
    final lastDate = DateTime(now.year + 2);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: '选择日期',
      cancelText: '清除',
      confirmText: '确定',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: context.colors.movieStart,
            onPrimary: Colors.white,
            surface: context.colors.surfaceHigh,
            onSurface: context.colors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (!mounted) return;
    if (picked != null) onPicked(picked);
  }

  String? _fmtDate(DateTime? d) {
    if (d == null) return null;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  // ---------- 保存 ----------

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _doSave();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _doSave() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('电影标题不能为空')),
      );
      return;
    }

    // 输入框里还没回车/点选的自定义类型先收进标签，再统计
    _commitGenreText();
    final rating = _rating > 0 ? _rating : null;
    final duration = int.tryParse(_durationCtrl.text.trim());
    final actorIds = _collectActorIds();

    final review = _reviewCtrl.text.trim();
    final genres = _selectedGenres.isEmpty ? null : _selectedGenres.toList();

    final provider = context.read<LibraryProvider>();
    if (_isEditMode && _movie == null) return;
    // 新增/编辑统一先在保存时刻确定 id，供海报复制落盘
    final id =
        _isEditMode ? _movie!.id : 'm_${DateTime.now().microsecondsSinceEpoch}';
    final poster = await _resolveDraftPoster(provider, id);

    if (_isEditMode) {
      final original = _movie;
      if (original == null) return;
      final updated = original.copyWith(
        title: title,
        englishTitle:
            _englishCtrl.text.trim().isEmpty ? null : _englishCtrl.text.trim(),
        director: _directorCtrl.text.trim().isEmpty
            ? null
            : _directorCtrl.text.trim(),
        status: rating != null
            ? MovieStatus.rated
            : (original.status == MovieStatus.rated
                ? MovieStatus.watched
                : original.status),
        rating: rating,
        poster: poster,
        releaseDate: _releaseDate,
        watchDate: _watchDate,
        duration: duration,
        genres: genres,
        review: review.isEmpty ? null : review,
        actorIds: actorIds,
        // 未重新检索时保留原溯源标记（copyWith 传 null 会清字段）
        source: _sourceTag ?? original.source,
      );
      provider.updateMovie(updated);
    } else {
      final now = DateTime.now();
      final newMovie = Movie(
        id: id,
        title: title,
        englishTitle:
            _englishCtrl.text.trim().isEmpty ? null : _englishCtrl.text.trim(),
        year: _releaseDate?.year ?? now.year,
        director: _directorCtrl.text.trim().isEmpty
            ? null
            : _directorCtrl.text.trim(),
        status: rating != null ? MovieStatus.rated : MovieStatus.watchlist,
        rating: rating,
        coverHue: (_movie?.coverHue ?? 165),
        emoji: _movie?.emoji,
        poster: poster,
        releaseDate: _releaseDate,
        watchDate: _watchDate,
        duration: duration,
        genres: genres,
        review: review.isEmpty ? null : review,
        actorIds: actorIds,
        source: _sourceTag,
      );
      provider.addMovie(newMovie);
    }
    if (!mounted) return;
    Navigator.of(context).pop(kEditResultSaved);
  }

  /// 计算保存时的海报引用（与书编辑 _resolveDraftCover 同构）：
  /// 选中本地图 → 先复制进 images/ 再返回 local；没动过 → 沿用原图；
  /// 动过且填了 URL → **先缓存到本地**（成功 = local+remote 双引用，
  /// 展示优先读本地、离线回退 URL；缓存失败 = 纯网络引用）；URL 空 → 移除。
  Future<MediaRef?> _resolveDraftPoster(
    LibraryProvider provider,
    String id,
  ) async {
    final pending = _pendingPosterFile;
    if (pending != null) {
      final rel = await provider.attachImage(pending, id);
      return rel == null ? null : MediaRef.local(rel);
    }
    if (!_posterEdited) return _movie?.poster;
    final url = _posterUrlCtrl.text.trim();
    if (url.isEmpty) return null;
    final cached = await provider.cacheRemoteImage(url, 'movie_poster');
    if (cached != null) return MediaRef(localFile: cached, remoteUrl: url);
    return MediaRef.network(url);
  }

  // ---------- 删除 ----------

  Future<void> _confirmDelete() async {
    if (_saving) return;
    final movie = _movie;
    if (movie == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceHigh,
        title: Text(
          '删除这部电影？',
          style: TextStyle(color: context.colors.textPrimary, fontSize: 18),
        ),
        content: Text(
          '《${movie.title}》将从电影库中移除，此操作不可撤销。',
          style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                Text('取消', style: TextStyle(color: context.colors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '删除',
              style: TextStyle(
                  color: context.colors.danger, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    context.read<LibraryProvider>().deleteMovie(movie.id);
    Navigator.of(context).pop(kEditResultDeleted);
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(_isEditMode ? '修改电影' : '添加电影'),
        backgroundColor: Colors.transparent,
      ),
      body: _isEditMode && _notFound
          ? Center(
              child:
                  Text('未找到该电影', style: TextStyle(color: context.colors.textMuted)),
            )
          : SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 快速检索（联网补全）：无默认影视数据源时整块隐藏
              ..._quickSearchBlocks(),
              _buildCoverHeader(),
              const SizedBox(height: 26),
              const EditSectionTitle('基本信息'),
              const SizedBox(height: 10),
              EditInputField(
                controller: _titleCtrl,
                label: '电影标题',
                hint: '输入片名',
              ),
              const SizedBox(height: 12),
              EditInputField(
                controller: _englishCtrl,
                label: '英文名（可选）',
                hint: '输入英文名',
              ),
              const SizedBox(height: 12),
              EditInputField(
                controller: _directorCtrl,
                label: '导演',
                hint: '输入导演姓名',
                focusNode: _directorFocus,
                onSubmitted: _handleDirectorSync,
              ),
              const SizedBox(height: 26),
              const EditSectionTitle('上映与观影'),
              const SizedBox(height: 10),
              _buildDateField(
                label: '上映时间',
                icon: Icons.calendar_month_rounded,
                value: _fmtDate(_releaseDate),
                onTap: () => _pickDate(
                  current: _releaseDate,
                  onPicked: (v) => setState(() => _releaseDate = v),
                ),
              ),
              const SizedBox(height: 12),
              _buildDateField(
                label: '看过时间',
                icon: Icons.visibility_rounded,
                value: _fmtDate(_watchDate),
                onTap: () => _pickDate(
                  current: _watchDate,
                  onPicked: (v) => setState(() => _watchDate = v),
                ),
              ),
              const SizedBox(height: 12),
              // 片长（数字 + 分钟后缀）
              // 注意：不能用 TextInputType.number——搜狗等部分国产输入法在该
              // 模式下弹数字键盘但不提交字符（键盘能弹、输入无效）。也不能用
              // FilteringTextInputFormatter——组合输入中间态会被格式化器吞掉。
              // 最终方案：文本通道 + onChanged 手动净化（见 sanitizeDurationInput）。
              EditInputField(
                controller: _durationCtrl,
                label: '片长',
                hint: '如 169',
                suffixText: '分钟',
                keyboardType: TextInputType.text,
                onChanged: (raw) {
                  final clean = sanitizeDurationInput(raw);
                  if (clean == raw) return;
                  _durationCtrl.value = TextEditingValue(
                    text: clean,
                    selection: TextSelection.collapsed(offset: clean.length),
                  );
                },
              ),
              const SizedBox(height: 26),
              const EditSectionTitle('剧情类型'),
              const SizedBox(height: 10),
              _buildGenreSection(),
              const SizedBox(height: 26),
              const EditSectionTitle('评分'),
              const SizedBox(height: 4),
              _buildRatingSlider(),
              const SizedBox(height: 26),
              const EditSectionTitle('演员信息'),
              const SizedBox(height: 10),
              _buildCastEditor(),
              const SizedBox(height: 26),
              const EditSectionTitle('我的影评'),
              const SizedBox(height: 8),
              _buildReviewField(),
              const SizedBox(height: 32),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 快速检索（联网信息补全）----------

  /// 检索区块：未注入 DataSourceProvider（部分测试只给 LibraryProvider）
  /// 或无默认影视数据源时整块隐藏，不影响手动录入。
  List<Widget> _quickSearchBlocks() {
    final DataSourceProvider? ds = _tryReadDataSource(context);
    final source = ds?.defaultMovieSource;
    if (ds == null || source == null) return const [];
    return [
      QuickSearchPanel(
        controller: _searchCtrl,
        hint: '输入片名，联网搜索并回填',
        sourceName: source.name,
        isSearching: ds.isSearching,
        error: ds.searchError,
        results: ds.movieResults
            ?.map((r) => QuickSearchItem(
                  title: r.title,
                  subtitle: r.subtitle,
                  coverUrl: r.posterUrl,
                  externalId: r.externalId,
                ))
            .toList(),
        filledExternalId: _filledResult?.externalId,
        tagColor: context.colors.movieStart,
        fallbackIcon: Icons.movie_outlined,
        onClear: () {
          _searchDebounce?.cancel();
          _searchCtrl.clear();
          ds.clearResults();
          setState(() {});
        },
        onPick: (item) {
          // 从展示投影找回原始结果对象再回填（回填消费完整模型字段）
          final matches =
              ds.movieResults?.where((r) => r.externalId == item.externalId);
          if (matches == null || matches.isEmpty) return;
          _applyMovieResult(matches.first, ds);
        },
      ),
      const SizedBox(height: 26),
    ];
  }

  /// 从上下文读数据源 Provider；未注册时返回 null（不抛异常）。
  /// build 中用默认 listen: true（搜索状态变化触发整页 rebuild）；
  /// 事件回调（onChanged / Timer）中必须 listen: false。
  DataSourceProvider? _tryReadDataSource(
    BuildContext context, {
    bool listen = true,
  }) {
    try {
      return Provider.of<DataSourceProvider>(context, listen: listen);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// 搜索词变化（controller listener）：
  /// - 每次变更 setState 刷新清除按钮显隐（原 onChanged 同款开销）；
  /// - IME 拼音组合输入中（composing 有效）不发起搜索，避免输入
  ///   片名拼音的过程打出多次半成品查询；
  /// - 组合结束/普通输入 → 取消旧 timer，800ms debounce 后搜索。
  void _onSearchCtrlChanged() {
    final value = _searchCtrl.value;
    setState(() {});
    if (value.composing.isValid) return;
    _searchDebounce?.cancel();
    final q = value.text.trim();
    if (q.isEmpty) {
      _tryReadDataSource(context, listen: false)?.clearResults();
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _tryReadDataSource(context, listen: false)?.searchMovies(q);
    });
  }

  /// 选中搜索结果 → 自动回填表单。
  /// 先尝试取详情补全导演/主演/片长/类型（失败回退搜索结果），再统一 setState。
  Future<void> _applyMovieResult(
    MovieSearchResult r,
    DataSourceProvider ds,
  ) async {
    MovieSearchResult detail = r;
    final full = await ds.fetchMovieDetail(r);
    if (!mounted) return;
    if (full != null) detail = full;

    final source = ds.defaultMovieSource;
    setState(() {
      _titleCtrl.text = detail.title;
      if (detail.originalTitle != null && detail.originalTitle!.isNotEmpty) {
        _englishCtrl.text = detail.originalTitle!;
      }
      if (detail.director != null && detail.director!.isNotEmpty) {
        _directorCtrl.text = detail.director!;
        _directorAutoDismissed = null;
        _applyDirectorSync();
      }
      if (detail.year != null) {
        _releaseDate = DateTime(detail.year!);
      }
      if (detail.runtimeMinutes != null && detail.runtimeMinutes! > 0) {
        _durationCtrl.text = '${detail.runtimeMinutes}';
      }
      if (detail.rating != null && detail.rating! > 0) {
        _rating = detail.rating!;
      }
      if (detail.posterUrl != null && detail.posterUrl!.isNotEmpty) {
        _posterEdited = true;
        _pendingPosterFile = null;
        _posterUrlCtrl.text = detail.posterUrl!;
      }
      // 主演 → 演员槽位（导演自动槽之外追加；自由文本，保存时精确吸附/新建）
      for (final member in detail.cast) {
        final name = member.name.trim();
        if (name.isEmpty) continue;
        if (_actorSlots.any((s) => s.ctrl.text.trim() == name)) continue;
        _actorSlots.add(ActorSlot(ctrl: TextEditingController(text: name)));
      }
      _selectedGenres.addAll(detail.genres);
      _filledResult = r;
      _sourceTag =
          source == null ? null : '${source.type.name}:${detail.externalId}';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已自动填充《${detail.title}》'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------- 顶部封面 + 更改封面 ----------

  /// 海报预览输入：编辑态未改动 → 原图；动过后 → URL 文本（网络）或空（占位）；
  /// 选中本地图时由 [MediaCover.pendingFile] 优先展示，[media] 归位 null。
  MediaRef? get _previewPosterMedia {
    if (_posterEdited) {
      final url = _posterUrlCtrl.text.trim();
      return url.isEmpty ? null : MediaRef.network(url);
    }
    return _movie?.poster;
  }

  /// 更改海报菜单：从相册选择（持久模式）/ 粘贴网络链接 / 移除海报
  Future<void> _openPosterMenu() async {
    final lib = context.read<LibraryProvider>();
    final action = await showCoverActionSheet(
      context: context,
      canPickImage: lib.canPickImage,
      removeLabel: '移除海报',
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'pick':
        await _pickFromGallery();
      case 'url':
        await _promptPosterUrl();
      case 'remove':
        setState(() {
          _posterEdited = true;
          _pendingPosterFile = null;
          _posterUrlCtrl.clear();
        });
    }
  }

  Future<void> _pickFromGallery() async {
    final lib = context.read<LibraryProvider>();
    final picked = await lib.pickImageFile();
    if (picked == null || !mounted) return; // 用户取消
    setState(() {
      _posterEdited = true;
      _pendingPosterFile = picked;
      _posterUrlCtrl.clear();
    });
  }

  Future<void> _promptPosterUrl() async {
    var url = '';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceHigh,
        title: Text('网络图片链接',
            style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.url,
          style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
          cursorColor: context.colors.accent,
          decoration: InputDecoration(
            hintText: 'https://…',
            hintStyle: TextStyle(color: context.colors.textMuted, fontSize: 13),
            filled: true,
            fillColor: context.colors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.outline, width: 0.8),
            ),
          ),
          onChanged: (s) => url = s,
          onSubmitted: (s) => Navigator.of(ctx).pop(s),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                Text('取消', style: TextStyle(color: context.colors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(url),
            child: Text('确定',
                style: TextStyle(
                    color: context.colors.accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    final trimmed = result.trim();
    setState(() {
      _posterEdited = true;
      _pendingPosterFile = null;
      _posterUrlCtrl.text = trimmed;
    });
  }

  Widget _buildCoverHeader() {
    final title =
        _titleCtrl.text.trim().isEmpty ? '电影' : _titleCtrl.text.trim();
    final hue = _movie?.coverHue ?? 165;
    final emoji = _movie?.emoji;
    return Center(
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: MediaCover(
              media: _previewPosterMedia,
              pendingFile: _pendingPosterFile,
              title: title,
              emoji: emoji ?? '',
              hue: hue,
              aspectRatio: 3 / 4,
              borderRadius: 0,
              fontSize: 44,
              showTitle: true,
            ),
          ),
          // 更改封面叠加按钮
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: _openPosterMenu,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.75),
                    ],
                  ),
                ),
                child: const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined,
                          size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        '更改封面',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 日期选择行（仿输入框）----------

  Widget _buildDateField({
    required String label,
    required IconData icon,
    required String? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: context.colors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.outline, width: 0.8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: context.colors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value ?? '选择日期（可跳过）',
                style: TextStyle(
                  color: value == null
                      ? context.colors.textMuted
                      : context.colors.textPrimary,
                  fontSize: 15,
                  fontWeight:
                      value == null ? FontWeight.normal : FontWeight.w600,
                ),
              ),
            ),
            Icon(
              value == null ? Icons.expand_more_rounded : Icons.close_rounded,
              size: 18,
              color: value == null
                  ? context.colors.textMuted
                  : context.colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 类型联想输入 + 多选标签 ----------

  /// 类型联想候选：预设 ∪ 影库实际用过的类型（去重，预设在前），剔除已选
  List<String> get _genreCandidates {
    final used = context.read<LibraryProvider>().usedMovieGenres;
    return <String>{
      ...kMovieCategories,
      ...used,
    }.where((g) => !_selectedGenres.contains(g)).toList(growable: false);
  }

  /// 联想规则：空输入 → 全部候选；有输入 → 包含匹配。
  /// 精确命中的候选置顶（保证回车确认的就是它）；无精确命中且未选过时
  /// 追加「添加」哨兵——空 options 不渲染浮层，哨兵保证自定义值有可点入口。
  ///
  /// 哨兵选项编码为 `_genreCreateSentinel + 用户输入`：RawAutocomplete 选中
  /// 时会先把 displayString 写进输入框，onSelected 里再读输入框会把哨兵
  /// 原文当类型吞进去（踩过），所以真实值必须随选项携带（同演员哨兵做法）。
  List<String> _genreOptionsFor(String rawQuery) {
    final q = rawQuery.trim();
    if (q.isEmpty) return _genreCandidates;
    final options = _genreCandidates.where((c) => c.contains(q)).toList();
    if (options.contains(q)) {
      options
        ..remove(q)
        ..insert(0, q);
    } else if (!_selectedGenres.contains(q)) {
      options.add('$_genreCreateSentinel$q');
    }
    return options;
  }

  /// 添加一个类型标签（空串/已选静默忽略，天然去重）
  void _addGenre(String genre) {
    final g = genre.trim();
    if (g.isEmpty || _selectedGenres.contains(g)) return;
    setState(() => _selectedGenres.add(g));
  }

  /// 把输入框里未提交的文本收进标签并清空输入框（无文本时跳过）
  void _commitGenreText() {
    final text = _genreCtrl.text.trim();
    if (text.isEmpty) return;
    _addGenre(text);
    _genreCtrl.clear();
  }

  void _handleGenreFocusChange() {
    if (!_genreFocus.hasFocus) _commitGenreText();
  }

  Widget _buildGenreSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 已选标签（点 × 移除，等价旧 FilterChip 的取消语义）
        if (_selectedGenres.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in _selectedGenres)
                  InputChip(
                    label: Text(g),
                    onDeleted: () => setState(() => _selectedGenres.remove(g)),
                    deleteIconColor: context.colors.textMuted,
                    backgroundColor: context.colors.surfaceHigh,
                    side:
                        BorderSide(color: context.colors.movieStart, width: 1),
                    labelStyle: TextStyle(
                      color: context.colors.movieEnd,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
              ],
            ),
          ),
        RawAutocomplete<String>(
          textEditingController: _genreCtrl,
          focusNode: _genreFocus,
          optionsBuilder: (value) => _genreOptionsFor(value.text),
          displayStringForOption: (g) => g,
          onSelected: (g) {
            // 哨兵选项自带用户输入，解析出真实类型；普通选项直接采用。
            // 两种来源最后统一清空输入框（RawAutocomplete 选中时已把
            // displayString 写入输入框，不主动清会残留哨兵/旧文本）。
            if (g.startsWith(_genreCreateSentinel)) {
              _addGenre(g.substring(_genreCreateSentinel.length));
            } else {
              _addGenre(g);
            }
            _genreCtrl.clear();
          },
          // 注意：fieldViewBuilder 第 4 参是 onFieldSubmitted（回车确认候选），
          // 不是 onChanged；自定义文本的提交在 onFieldSubmitted 之后兜底。
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              key: const ValueKey('genre-input'),
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                // 先走候选确认（有精确/高亮候选时），再把剩余自定义文本收进标签
                onFieldSubmitted();
                _commitGenreText();
              },
              style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
              cursorColor: context.colors.accent,
              decoration: InputDecoration(
                hintText: '输入或选择类型，回车添加（可多选）',
                hintStyle:
                    TextStyle(color: context.colors.textMuted, fontSize: 14),
                filled: true,
                fillColor: context.colors.surfaceHigh,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: context.colors.outline, width: 0.8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: context.colors.outline, width: 0.8),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      BorderSide(color: context.colors.accent, width: 1.3),
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onChoose, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: context.colors.surface,
                elevation: 6,
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 220, maxWidth: 340),
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, i) {
                      final option = options.elementAt(i);
                      final isCreate = option.startsWith(_genreCreateSentinel);
                      return InkWell(
                        onTap: () => onChoose(option),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          child: isCreate
                              ? Row(
                                  children: [
                                    Icon(Icons.add_circle_outline_rounded,
                                        size: 17, color: context.colors.accent),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '添加「${option.substring(_genreCreateSentinel.length)}」',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: context.colors.accent,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  option,
                                  style: TextStyle(
                                      color: context.colors.textPrimary,
                                      fontSize: 14),
                                ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ---------- 评分 Slider + 实时星级 ----------

  Widget _buildRatingSlider() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.outline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '我的评分',
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 13),
              ),
              const Spacer(),
              Text(
                _rating > 0 ? '${_rating.toStringAsFixed(1)} 分' : '未评分',
                style: TextStyle(
                  color: _rating > 0
                      ? context.colors.star
                      : context.colors.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Slider 0-5 步进 0.5
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              activeTrackColor: context.colors.movieStart,
              inactiveTrackColor: context.colors.outline,
              thumbColor: Colors.white,
              overlayColor: context.colors.movieStart.withOpacity(0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: _rating,
              max: 5,
              divisions: 10,
              onChanged: (v) => setState(() => _rating = v),
            ),
          ),
          const SizedBox(height: 2),
          // 实时星级点亮（0-5 星）
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 1; i <= 5; i++)
                  Icon(
                    _rating >= i - 0.25
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 24,
                    color: _rating >= i - 0.25
                        ? context.colors.star
                        : context.colors.textMuted.withOpacity(0.4),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 演员动态增删（联想已有 + 快速新建）----------

  /// 联想「新建」哨兵 id：无精确命中时作为候选尾项渲染新建行。
  /// 实体演员 id 恒为 `a_` + 微秒时间戳，与此值绝不冲突。
  static const String _actorCreateId = '__actor_create__';

  Widget _buildCastEditor() {
    return Column(
      children: [
        if (_actorSlots.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.colors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.colors.outline, width: 0.8),
            ),
            child: Center(
              child: Text(
                '还没有演员，点击下方「添加演员」，输入姓名联想选择或新建',
                style: TextStyle(color: context.colors.textMuted, fontSize: 13),
              ),
            ),
          )
        else
          ..._actorSlots.asMap().entries.map((entry) {
            final i = entry.key;
            final slot = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  // 序号头像（文本首字实时跟随）
                  AnimatedBuilder(
                    animation: slot.ctrl,
                    builder: (_, __) => Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: coverGradient(30.0 * (i + 1)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _slotInitial(slot, i),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _buildActorField(slot)),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: '移除',
                    onPressed: () => setState(() {
                      // 删除导演自动槽：记录导演名，同导演不再自动弹回
                      if (slot.autoFromDirector) {
                        _directorAutoDismissed = _directorCtrl.text.trim();
                        _directorAutoName = null;
                        slot.autoFromDirector = false;
                      }
                      slot.dispose();
                      _actorSlots.remove(slot);
                    }),
                    icon: Icon(Icons.remove_circle_outline_rounded,
                        color: context.colors.danger, size: 22),
                  ),
                ],
              ),
            );
          }),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _actorSlots.add(ActorSlot())),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.accent,
            ),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
            label: const Text('添加演员',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  /// 槽位头像字符：有文本取首字，空文本显示序号
  String _slotInitial(ActorSlot slot, int index) {
    final text = slot.ctrl.text.trim();
    return text.isEmpty ? '${index + 1}' : text.characters.first;
  }

  /// 单槽位联想输入框（复用图书分类趟平的 RawAutocomplete 模式：
  /// 文本变化交给 controller 监听，fieldViewBuilder 第 4 参是 onFieldSubmitted）
  Widget _buildActorField(ActorSlot slot) {
    return RawAutocomplete<Actor>(
      textEditingController: slot.ctrl,
      focusNode: slot.focus,
      optionsBuilder: (value) => _actorOptions(slot, value.text),
      displayStringForOption: (a) => a.name,
      onSelected: (actor) {
        if (actor.id == _actorCreateId) {
          // 回车落在「新建」哨兵上 = 创建实体（录入新演员的唯一入口）
          final now = DateTime.now();
          final created = Actor(
            id: 'a_${now.microsecondsSinceEpoch}',
            name: actor.name,
            createdAt: now,
          );
          context.read<LibraryProvider>().addActor(created);
          slot.picked = created;
        } else {
          slot.picked = actor;
        }
        slot.focus.unfocus();
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onSubmitted: (_) => onFieldSubmitted(),
          style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
          cursorColor: context.colors.accent,
          decoration: InputDecoration(
            hintText: '输入姓名联想选择或新建',
            hintStyle: TextStyle(color: context.colors.textMuted, fontSize: 13),
            filled: true,
            fillColor: context.colors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.outline, width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.outline, width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.accent, width: 1.2),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onChoose, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: context.colors.surface,
            elevation: 6,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 380),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final actor = options.elementAt(i);
                  final isCreate = actor.id == _actorCreateId;
                  return InkWell(
                    onTap: () => onChoose(actor),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      child: Row(
                        children: [
                          if (isCreate) ...[
                            Icon(Icons.person_add_alt_1_rounded,
                                size: 17, color: context.colors.accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '新建演员「${actor.name}」',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.colors.accent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ] else ...[
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: coverGradient(_actorHue(actor.name)),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                actor.name.characters.first,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                actor.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontSize: 14),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// 联想候选：库中名字包含输入（排除其他槽位已选，允许本槽重选），
  /// 输入非空且无精确命中时在尾部追加「新建」哨兵——保证 overlay 恒可展开。
  List<Actor> _actorOptions(ActorSlot self, String rawQuery) {
    final query = rawQuery.trim();
    final lib = context.read<LibraryProvider>();
    final taken = _actorSlots
        .where((s) => !identical(s, self))
        .map((s) => s.picked?.id)
        .whereType<String>()
        .toSet();
    final matches = lib.actors
        .where((a) => !taken.contains(a.id) && a.name.contains(query))
        .toList();
    if (query.isNotEmpty && !matches.any((a) => a.name == query)) {
      matches.add(Actor(
        id: _actorCreateId,
        name: query,
        createdAt: DateTime(1970),
      ));
    }
    return matches;
  }

  double _actorHue(String name) =>
      (name.codeUnits.fold<int>(0, (s, c) => s + c) % 360).toDouble();

  /// 槽位 → actorIds：已解析槽位直接用实体 id；未解析的自由文本先精确吸附
  /// 库中同名演员（防「周星驰/周星弛」裂成两个实体），仍无则兜底新建。
  /// 全部为空返回 null（与旧契约一致：空引用不落盘）。
  List<String>? _collectActorIds() {
    final lib = context.read<LibraryProvider>();
    final ids = <String>[];
    for (final slot in _actorSlots) {
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
          final created = Actor(
            id: 'a_${now.microsecondsSinceEpoch}',
            name: text,
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

  // ---------- 我的影评 Textarea + 字数统计 ----------

  Widget _buildReviewField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _reviewCtrl,
          maxLines: 6,
          minLines: 4,
          maxLength: _reviewMaxChars,
          style: TextStyle(
              color: context.colors.textPrimary, fontSize: 14, height: 1.5),
          cursorColor: context.colors.accent,
          decoration: InputDecoration(
            hintText: '写下你的观影感受…',
            hintStyle: TextStyle(color: context.colors.textMuted, fontSize: 14),
            filled: true,
            fillColor: context.colors.surfaceHigh,
            alignLabelWithHint: true,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.colors.outline, width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.colors.outline, width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.colors.accent, width: 1.3),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _reviewCtrl,
            builder: (_, value, __) {
              final len = value.text.length;
              return Text(
                '$len/$_reviewMaxChars',
                style: TextStyle(
                  color: len >= _reviewMaxChars
                      ? context.colors.danger
                      : context.colors.textMuted,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------- 底部操作栏 ----------

  Widget _buildActions() {
    final gradient = context.colors.movieGradient;
    return Column(
      children: [
        // 保存修改（主操作，渐变高亮）
        SizedBox(
          width: double.infinity,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: context.colors.movieStart.withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _saving ? null : _save,
                child: Center(
                  child: _saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isEditMode ? '保存修改' : '保存',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // 取消 + 删除（删除仅编辑模式显示）
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.textSecondary,
                    side: BorderSide(color: context.colors.outline, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('取消', style: TextStyle(fontSize: 15)),
                ),
              ),
            ),
            if (_isEditMode) ...[
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _confirmDelete,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colors.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 20),
                        SizedBox(width: 6),
                        Text('删除电影',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // → EditSectionTitle
}

/// 编辑页演员槽位：输入控制器 + 焦点 + 已解析实体（可空）。
///
/// [picked] 为空表示当前文本尚未吸附到实体——保存时由编辑页
/// `_collectActorIds` 做「精确吸附已有 / 兜底新建」。
class ActorSlot {
  ActorSlot({TextEditingController? ctrl, this.picked})
      : ctrl = ctrl ?? TextEditingController(),
        focus = FocusNode();

  final TextEditingController ctrl;
  final FocusNode focus;

  /// 已解析实体（回填 / 联想选中 / 新建产生）；null = 自由文本
  Actor? picked;

  /// true = 由导演框自动挂载的槽位（导演失焦/回车同步；用户改过文本或删除后降级）
  bool autoFromDirector = false;

  void dispose() {
    ctrl.dispose();
    focus.dispose();
  }
}
