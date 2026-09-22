import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../component/media/media_cover.dart';
import '../../../component/theme/app_palette.dart';
import '../../../foundation/constants/app_strings.dart';
import '../../../foundation/utils/date_format.dart';
import '../../shared/model/data_source.dart';
import '../../shared/data_source_facade.dart';
import '../../shared/model/actor.dart';
import '../model/edit_result.dart';
import '../../shared/model/movie.dart';
import '../view/edit_form_view.dart';
import '../view/quick_search_panel.dart';
import '../view_model/library_provider.dart';
import '../view_model/movie_edit_controller.dart';

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
class MovieEditPage extends StatefulWidget {
  const MovieEditPage({super.key, this.movieId});

  /// 待编辑电影 id；为空表示新增模式
  final String? movieId;

  @override
  State<MovieEditPage> createState() => _MovieEditPageState();
}

class _MovieEditPageState extends State<MovieEditPage> {
  /// 表单状态与业务逻辑（M-5b）：校验、导演 ↔ 演员联动、类型标签、
  /// 海报解析、保存组装。放在控制器里，可脱离 Widget 树直接单测。
  late final MovieEditController _c;

  // ---------- 快速检索（联网信息补全）状态：与 Provider / BuildContext 强耦合，留在页面 ----------

  /// 搜索词输入
  final TextEditingController _searchCtrl = TextEditingController();

  /// 搜索 debounce 定时器（800ms）
  Timer? _searchDebounce;

  /// 最近一次选中回填的搜索结果（结果行「已填充」标记）
  MovieSearchResult? _filledResult;

  @override
  void initState() {
    super.initState();
    final provider = context.read<LibraryProvider>();
    final movieId = widget.movieId;
    Movie? movie;
    if (movieId != null) {
      final matches = provider.movieList.where((m) => m.id == movieId);
      movie = matches.isEmpty ? null : matches.first;
    }
    _c = MovieEditController(
      movieId: movieId,
      initialMovie: movie,
      // 编辑模式回填：actorIds → 实体解析（悬空引用静默丢弃）
      initialActors: provider.actorsByIds(movie?.actorIds ?? const <String>[]),
    );
    // 失焦时把未提交的输入收进标签，防止用户中途移开焦点丢输入
    _c.genreFocus.addListener(_handleGenreFocusChange);
    // 导演失焦 → 自动同步到演员第 0 位（回车提交在导演输入框 onSubmitted 同样触发）
    _c.directorFocus.addListener(_handleDirectorFocusChange);
    // 快速检索框：listener 驱动搜索（可读 IME composing，见 _onSearchCtrlChanged）
    _searchCtrl.addListener(_onSearchCtrlChanged);
  }

  @override
  void dispose() {
    _c.genreFocus.removeListener(_handleGenreFocusChange);
    _c.directorFocus.removeListener(_handleDirectorFocusChange);
    _c.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ---------- 导演 → 演员槽位自动同步 ----------

  /// 失焦时触发（onSubmitted 同语义）
  void _handleDirectorFocusChange() {
    if (!_c.directorFocus.hasFocus) _handleDirectorSync();
  }

  void _handleDirectorSync() {
    _c.applyDirectorSync();
    setState(() {});
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

  /// 日期字段展示值（null = 未设置，交给占位文案）
  String? _fmtDate(DateTime? d) => d == null ? null : formatDateYmd(d);

  // ---------- 保存 ----------

  Future<void> _save() async {
    if (_c.saving) return;
    setState(() => _c.saving = true);
    try {
      await _doSave();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.saveFailed(e))),
      );
    } finally {
      if (mounted) setState(() => _c.saving = false);
    }
  }

  Future<void> _doSave() async {
    final error = _c.validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }
    final provider = context.read<LibraryProvider>();
    final movie = await _c.composeMovie(provider);
    if (movie == null) return;
    if (_c.isEditMode) {
      provider.updateMovie(movie);
    } else {
      provider.addMovie(movie);
    }
    if (!mounted) return;
    Navigator.of(context).pop(kEditResultSaved);
  }

  // ---------- 删除 ----------

  Future<void> _confirmDelete() async {
    if (_c.saving) return;
    final movie = _c.movie;
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
        title: Text(_c.isEditMode ? '修改电影' : AppStrings.addMovie),
        backgroundColor: Colors.transparent,
      ),
      body: _c.isEditMode && _c.notFound
          ? Center(
              child: Text('未找到该电影',
                  style: TextStyle(color: context.colors.textMuted)),
            )
          : _buildFormContent(),
    );
  }

  /// 表单主体：封面、各分区输入与底部操作，仅在「未找到」分支之外渲染。
  Widget _buildFormContent() {
    return SafeArea(
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
            ..._buildBasicInfoFields(),
            const SizedBox(height: 26),
            ..._buildDateFields(),
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
            const EditSectionTitle(AppStrings.myReview),
            const SizedBox(height: 8),
            _buildReviewField(),
            const SizedBox(height: 32),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  /// 基本信息区：标题 / 英文名 / 导演三个输入行（含分区标题）。
  List<Widget> _buildBasicInfoFields() {
    return [
      const EditSectionTitle('基本信息'),
      const SizedBox(height: 10),
      EditInputField(
        controller: _c.titleCtrl,
        label: '电影标题',
        hint: '输入片名',
      ),
      const SizedBox(height: 12),
      EditInputField(
        controller: _c.englishCtrl,
        label: '英文名（可选）',
        hint: '输入英文名',
      ),
      const SizedBox(height: 12),
      EditInputField(
        controller: _c.directorCtrl,
        label: '导演',
        hint: '输入导演姓名',
        focusNode: _c.directorFocus,
        onSubmitted: _handleDirectorSync,
      ),
    ];
  }

  /// 上映与观影区：上映日期 / 看过时间 / 片长三个输入行（含分区标题）。
  List<Widget> _buildDateFields() {
    return [
      const EditSectionTitle('上映与观影'),
      const SizedBox(height: 10),
      _buildDateField(
        label: AppStrings.releaseDate,
        icon: Icons.calendar_month_rounded,
        value: _fmtDate(_c.releaseDate),
        onTap: () => _pickDate(
          current: _c.releaseDate,
          onPicked: (v) => setState(() => _c.releaseDate = v),
        ),
      ),
      const SizedBox(height: 12),
      _buildDateField(
        label: '看过时间',
        icon: Icons.visibility_rounded,
        value: _fmtDate(_c.watchDate),
        onTap: () => _pickDate(
          current: _c.watchDate,
          onPicked: (v) => setState(() => _c.watchDate = v),
        ),
      ),
      const SizedBox(height: 12),
      // 片长（数字 + 分钟后缀）
      // 注意：不能用 TextInputType.number——搜狗等部分国产输入法在该
      // 模式下弹数字键盘但不提交字符（键盘能弹、输入无效）。也不能用
      // FilteringTextInputFormatter——组合输入中间态会被格式化器吞掉。
      // 最终方案：文本通道 + onChanged 手动净化（见 sanitizeDurationInput）。
      EditInputField(
        controller: _c.durationCtrl,
        label: '片长',
        hint: '如 169',
        suffixText: '分钟',
        keyboardType: TextInputType.text,
        onChanged: (raw) {
          final clean = sanitizeDurationInput(raw);
          if (clean == raw) return;
          _c.durationCtrl.value = TextEditingValue(
            text: clean,
            selection: TextSelection.collapsed(offset: clean.length),
          );
        },
      ),
    ];
  }
  // ---------- 快速检索（联网信息补全）----------

  /// 检索区块：未注入 DataSourceFacade（部分测试只给 LibraryProvider）
  /// 或无默认影视数据源时整块隐藏，不影响手动录入。
  List<Widget> _quickSearchBlocks() {
    final DataSourceFacade? ds = _tryReadDataSource(context);
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
        filledTitle: _filledResult?.title,
        tagColor: context.colors.movieStart,
        fallbackIcon: Icons.movie_outlined,
        onClear: () {
          _searchDebounce?.cancel();
          _searchCtrl.clear();
          ds.clearResults();
          setState(() {});
        },
        onPick: (item) async {
          // 从展示投影找回原始结果对象再回填（回填消费完整模型字段）
          final matches =
              ds.movieResults?.where((r) => r.externalId == item.externalId);
          if (matches == null || matches.isEmpty) return;
          final searchResult = matches.first;
          setState(() {});
          await _applyMovieResult(searchResult, ds);
          // 回填完成后收起结果列表（保留搜索框文本，展示「已填充《片名》」）
          ds.clearResults();
        },
      ),
      const SizedBox(height: 26),
    ];
  }

  /// 从上下文读数据源 Provider；未注册时返回 null（不抛异常）。
  /// build 中用默认 listen: true（搜索状态变化触发整页 rebuild）；
  /// 事件回调（onChanged / Timer）中必须 listen: false。
  DataSourceFacade? _tryReadDataSource(
    BuildContext context, {
    bool listen = true,
  }) {
    try {
      return Provider.of<DataSourceFacade>(context, listen: listen);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// 搜索词变化（controller listener）：
  /// - M8：清除按钮显隐改由 QuickSearchPanel 内 ValueListenableBuilder 承担，
  ///   不再因输入触发整页 setState / rebuild；
  /// - IME 拼音组合输入中（composing 有效）不发起搜索，避免输入
  ///   片名拼音的过程打出多次半成品查询；
  /// - 组合结束/普通输入 → 取消旧 timer，800ms debounce 后搜索。
  void _onSearchCtrlChanged() {
    final value = _searchCtrl.value;
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
    DataSourceFacade ds,
  ) async {
    MovieSearchResult detail = r;
    final full = await ds.fetchMovieDetail(r);
    if (!mounted) return;
    // 合并而非替换：详情非空字段覆盖，缺失字段保留搜索结果
    //（避免详情接口不含海报/年份/类型时被 null 覆盖丢失）
    if (full != null) detail = r.mergeWith(full);

    final source = ds.defaultMovieSource;
    setState(() {
      _c.titleCtrl.text = detail.title;
      if (detail.originalTitle != null && detail.originalTitle!.isNotEmpty) {
        _c.englishCtrl.text = detail.originalTitle!;
      }
      if (detail.director != null && detail.director!.isNotEmpty) {
        _c.directorCtrl.text = detail.director!;
        _c.directorAutoDismissed = null;
        _c.applyDirectorSync();
      }
      if (detail.year != null) {
        _c.releaseDate = DateTime(detail.year!);
      }
      if (detail.runtimeMinutes != null && detail.runtimeMinutes! > 0) {
        _c.durationCtrl.text = '${detail.runtimeMinutes}';
      }
      // 评分**刻意不自动填充**（同书籍页）：源给的是 TMDB 大众平均分，
      // 不是「我的评分」；填进来会让用户以为自己打过这个分。
      if (detail.posterUrl != null && detail.posterUrl!.isNotEmpty) {
        _c.posterEdited = true;
        _c.pendingPosterFile = null;
        _c.posterUrlCtrl.text = detail.posterUrl!;
      }
      // 主演 → 演员槽位（导演自动槽之外追加）；演职员快照 + 剧照非空才覆盖
      _c.applyCastDetail(detail.cast, detail.backdrops);
      _c.selectedGenres.addAll(detail.genres);
      _filledResult = r;
      _c.sourceTag =
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
          _c.posterEdited = true;
          _c.pendingPosterFile = null;
          _c.posterUrlCtrl.clear();
        });
    }
  }

  Future<void> _pickFromGallery() async {
    final lib = context.read<LibraryProvider>();
    final picked = await lib.pickImageFile();
    if (picked == null || !mounted) return; // 用户取消
    setState(() {
      _c.posterEdited = true;
      _c.pendingPosterFile = picked;
      _c.posterUrlCtrl.clear();
    });
  }

  Future<void> _promptPosterUrl() async {
    var url = '';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceHigh,
        title: Text(AppStrings.networkImageUrl,
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
      _c.posterEdited = true;
      _c.pendingPosterFile = null;
      _c.posterUrlCtrl.text = trimmed;
    });
  }

  Widget _buildCoverHeader() {
    final title =
        _c.titleCtrl.text.trim().isEmpty ? '电影' : _c.titleCtrl.text.trim();
    final hue = _c.movie?.coverHue ?? 165;
    final emoji = _c.movie?.emoji;
    return Center(
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: MediaCover(
              media: _c.previewPosterMedia,
              pendingFile: _c.pendingPosterFile,
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

  /// 类型输入框失焦：把未提交的文本收进标签（无文本 / 已存在时 no-op）
  void _handleGenreFocusChange() {
    if (_c.genreFocus.hasFocus) return;
    if (_c.commitGenreText()) setState(() {});
  }

  Widget _buildGenreSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 已选标签（点 x 移除，等价旧 FilterChip 的取消语义）
        if (_c.selectedGenres.isNotEmpty) _buildGenreChips(),
        RawAutocomplete<String>(
          textEditingController: _c.genreCtrl,
          focusNode: _c.genreFocus,
          optionsBuilder: (value) => _c.genreOptionsFor(
            value.text,
            context.read<LibraryProvider>().usedMovieGenres,
          ),
          displayStringForOption: (g) => g,
          onSelected: (g) {
            // 「添加“X”」哨兵自带用户输入，解析出真实类型；普通选项直接采用；
            // 两种来源最后统一清空输入框（selector 内部处理）
            if (_c.selectGenreOption(g)) setState(() {});
          },
          // 注意：fieldViewBuilder 第 4 参是 onFieldSubmitted（回车确认候选），
          // 不是 onChanged；自定义文本的提交在 onFieldSubmitted 之后兜底。
          fieldViewBuilder: _buildGenreField,
          optionsViewBuilder: _buildGenreOptionsView,
        ),
      ],
    );
  }

  /// 已选类型标签（点 x 移除）。
  Widget _buildGenreChips() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final g in _c.selectedGenres)
            InputChip(
              label: Text(g),
              onDeleted: () => setState(() => _c.selectedGenres.remove(g)),
              deleteIconColor: context.colors.textMuted,
              backgroundColor: context.colors.surfaceHigh,
              side: BorderSide(color: context.colors.movieStart, width: 1),
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
    );
  }

  /// 类型输入框（RawAutocomplete 的 fieldViewBuilder）。
  Widget _buildGenreField(
    BuildContext context,
    TextEditingController controller,
    FocusNode focusNode,
    void Function() onFieldSubmitted,
  ) {
    return TextField(
      key: const ValueKey('genre-input'),
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) {
        // 先走候选确认（有精确/高亮候选时），再把剩余自定义文本收进标签
        onFieldSubmitted();
        if (_c.commitGenreText()) setState(() {});
      },
      style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
      cursorColor: context.colors.accent,
      decoration: InputDecoration(
        hintText: '输入或选择类型，回车添加（可多选）',
        hintStyle: TextStyle(color: context.colors.textMuted, fontSize: 14),
        filled: true,
        fillColor: context.colors.surfaceHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
    );
  }

  /// 类型联想下拉（RawAutocomplete 的 optionsViewBuilder）。
  Widget _buildGenreOptionsView(
    BuildContext context,
    AutocompleteOnSelected<String> onChoose,
    Iterable<String> options,
  ) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        color: context.colors.surface,
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220, maxWidth: 340),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, i) {
              final option = options.elementAt(i);
              final isCreate =
                  option.startsWith(MovieEditController.genreCreateSentinel);
              return InkWell(
                onTap: () => onChoose(option),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: isCreate
                      ? Row(
                          children: [
                            Icon(Icons.add_circle_outline_rounded,
                                size: 17, color: context.colors.accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '添加「${option.substring(MovieEditController.genreCreateSentinel.length)}」',
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
                              color: context.colors.textPrimary, fontSize: 14),
                        ),
                ),
              );
            },
          ),
        ),
      ),
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
                AppStrings.myRating,
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 13),
              ),
              const Spacer(),
              Text(
                _c.rating > 0
                    ? '${_c.rating.toStringAsFixed(1)} 分'
                    : AppStrings.unrated,
                style: TextStyle(
                  color: _c.rating > 0
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
              value: _c.rating,
              max: 5,
              divisions: 10,
              // 拖动时下方星级实时点亮；每跨半星给一次轻微触感，
              // 与书籍页的星星选择器手感一致（见 star_rating_picker.dart）
              onChanged: (v) {
                if (v != _c.rating) unawaited(HapticFeedback.selectionClick());
                setState(() => _c.rating = v);
              },
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
                    _c.rating >= i - 0.25
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 24,
                    color: _c.rating >= i - 0.25
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

  Widget _buildCastEditor() {
    return Column(
      children: [
        if (_c.actorSlots.isEmpty)
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
          ..._c.actorSlots.asMap().entries.map((entry) {
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
                        _c.slotInitial(slot, i),
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
                    // 删除导演自动槽：控制器内部记录导演名，同导演不再自动弹回
                    onPressed: () => setState(() => _c.removeActorSlot(slot)),
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
            onPressed: () => setState(_c.addActorSlot),
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

  /// 单槽位联想输入框（复用图书分类趟平的 RawAutocomplete 模式：
  /// 文本变化交给 controller 监听，fieldViewBuilder 第 4 参是 onFieldSubmitted）
  Widget _buildActorField(ActorSlot slot) {
    return RawAutocomplete<Actor>(
      textEditingController: slot.ctrl,
      focusNode: slot.focus,
      optionsBuilder: (value) =>
          _c.actorOptions(slot, value.text, context.read<LibraryProvider>()),
      displayStringForOption: (a) => a.name,
      onSelected: (actor) {
        // 命中「新建」哨兵 -> 控制器建实体并落库（录入新演员的唯一入口）
        _c.pickActor(slot, actor, context.read<LibraryProvider>());
        slot.focus.unfocus();
      },
      fieldViewBuilder: _buildActorFieldView,
      optionsViewBuilder: _buildActorOptionsView,
    );
  }

  /// 演员输入框（RawAutocomplete 的 fieldViewBuilder）。
  Widget _buildActorFieldView(
    BuildContext context,
    TextEditingController controller,
    FocusNode focusNode,
    void Function() onFieldSubmitted,
  ) {
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
  }

  /// 演员联想下拉（RawAutocomplete 的 optionsViewBuilder）。
  Widget _buildActorOptionsView(
    BuildContext context,
    AutocompleteOnSelected<Actor> onChoose,
    Iterable<Actor> options,
  ) {
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
            itemBuilder: (context, i) =>
                _buildActorOptionRow(context, onChoose, options.elementAt(i)),
          ),
        ),
      ),
    );
  }

  /// 演员下拉单行（新建哨兵 / 已存在演员头像首字）。
  Widget _buildActorOptionRow(
    BuildContext context,
    AutocompleteOnSelected<Actor> onChoose,
    Actor actor,
  ) {
    final isCreate = actor.id == MovieEditController.actorCreateId;
    return InkWell(
      onTap: () => onChoose(actor),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                  gradient:
                      coverGradient(MovieEditController.actorHue(actor.name)),
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
                      color: context.colors.textPrimary, fontSize: 14),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  // ---------- 我的影评 Textarea + 字数统计 ----------

  Widget _buildReviewField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _c.reviewCtrl,
          maxLines: 6,
          minLines: 4,
          maxLength: MovieEditController.reviewMaxChars,
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
            valueListenable: _c.reviewCtrl,
            builder: (_, value, __) {
              final len = value.text.length;
              return Text(
                '$len/$MovieEditController.reviewMaxChars',
                style: TextStyle(
                  color: len >= MovieEditController.reviewMaxChars
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
        _buildSaveButton(gradient),
        const SizedBox(height: 12),
        Row(
          children: [
            _buildCancelButton(),
            if (_c.isEditMode) ...[
              const SizedBox(width: 12),
              _buildDeleteButton(),
            ],
          ],
        ),
      ],
    );
  }

  /// 保存按钮（主操作，渐变高亮）。
  Widget _buildSaveButton(Gradient gradient) {
    return SizedBox(
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
            onTap: _c.saving ? null : _save,
            child: Center(
              child: _c.saving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _c.isEditMode ? '保存修改' : '保存',
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
    );
  }

  /// 取消按钮（返回上一页）。
  Widget _buildCancelButton() {
    return Expanded(
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
    );
  }

  /// 删除按钮（仅编辑模式显示）。
  Widget _buildDeleteButton() {
    return Expanded(
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
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
  // → EditSectionTitle
}
