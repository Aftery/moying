import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../models/actor.dart';
import '../models/media_ref.dart';
import '../models/movie.dart';
import '../providers/library_provider.dart';
import '../widgets/media_cover.dart';

/// 编辑页返回约定：null = 取消；'saved' = 已保存；'deleted' = 已删除
const String kEditResultSaved = 'saved';
const String kEditResultDeleted = 'deleted';

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

  @override
  void initState() {
    super.initState();
    final provider = context.read<LibraryProvider>();
    final movieId = widget.movieId;
    Movie? movie;
    if (movieId != null) {
      final matches =
          provider.movieList.where((m) => m.id == movieId).toList();
      movie = matches.isEmpty ? null : matches.first;
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
    // 编辑模式回填：actorIds → 实体解析 → 显示姓名（悬空引用静默丢弃）。
    // 这是"渲染 actorIds 的地方统一走解析"的第二个渲染点，与详情页同步切换，
    // 确保用户新建的 id≠name 演员在回填时显示名字而非一串乱码 id。
    for (final actor in provider.actorsByIds(movie?.actorIds ?? const <String>[])) {
      _actorSlots.add(ActorSlot(
        ctrl: TextEditingController(text: actor.name),
        picked: actor,
      ));
    }
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
    _posterUrlCtrl.dispose();
    super.dispose();
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
          colorScheme: const ColorScheme.dark(
            primary: AppColors.movieStart,
            onPrimary: Colors.white,
            surface: AppColors.surfaceHigh,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
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
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('电影标题不能为空')),
      );
      return;
    }

    final rating = _rating > 0 ? _rating : null;
    final duration = int.tryParse(_durationCtrl.text.trim());
    final actorIds = _collectActorIds();

    final review = _reviewCtrl.text.trim();
    final genres = _selectedGenres.isEmpty ? null : _selectedGenres.toList();

    final provider = context.read<LibraryProvider>();
    // 新增/编辑统一先在保存时刻确定 id，供海报复制落盘
    final id = _isEditMode
        ? _movie!.id
        : 'm_${DateTime.now().microsecondsSinceEpoch}';
    final poster = await _resolveDraftPoster(provider, id);

    if (_isEditMode) {
      final original = _movie;
      if (original == null) return;
      final updated = original.copyWith(
        title: title,
        englishTitle: _englishCtrl.text.trim().isEmpty
            ? null
            : _englishCtrl.text.trim(),
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
        director:
            _directorCtrl.text.trim().isEmpty ? null : _directorCtrl.text.trim(),
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
      );
      provider.addMovie(newMovie);
    }
    if (!mounted) return;
    Navigator.of(context).pop(kEditResultSaved);
  }

  /// 计算保存时的海报引用（与书编辑 _resolveDraftCover 同构）：
  /// 选中本地图 → 先复制进 images/ 再返回 local；没动过 → 沿用原图；
  /// 动过且填了 URL → 网络；URL 空 → 移除（null）。
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
    return url.isEmpty ? null : MediaRef.network(url);
  }

  // ---------- 删除 ----------

  Future<void> _confirmDelete() async {
    final movie = _movie;
    if (movie == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        title: const Text(
          '删除这部电影？',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
        ),
        content: Text(
          '《${movie.title}》将从电影库中移除，此操作不可撤销。',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                const Text('取消', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '删除',
              style: TextStyle(
                  color: Color(0xFFFF6B6B), fontWeight: FontWeight.w700),
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEditMode ? '修改电影' : '添加电影'),
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCoverHeader(),
              const SizedBox(height: 26),
              _sectionTitle('基本信息'),
              const SizedBox(height: 10),
              _inputField(
                controller: _titleCtrl,
                label: '电影标题',
                hint: '输入片名',
              ),
              const SizedBox(height: 12),
              _inputField(
                controller: _englishCtrl,
                label: '英文名（可选）',
                hint: '输入英文名',
              ),
              const SizedBox(height: 12),
              _inputField(
                controller: _directorCtrl,
                label: '导演',
                hint: '输入导演姓名',
              ),
              const SizedBox(height: 26),
              _sectionTitle('上映与观影'),
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
              TextField(
                controller: _durationCtrl,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 15),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  labelText: '片长',
                  labelStyle:
                      const TextStyle(color: AppColors.textMuted, fontSize: 13),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Center(
                      child: Text(
                        '分钟',
                        style: TextStyle(
                          color: AppColors.textMuted.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  hintText: '如 169',
                  hintStyle:
                      const TextStyle(color: AppColors.textMuted, fontSize: 14),
                  filled: true,
                  fillColor: AppColors.surfaceHigh,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: AppColors.outline, width: 0.8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: AppColors.outline, width: 0.8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: AppColors.accent, width: 1.3),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              _sectionTitle('剧情类型'),
              const SizedBox(height: 10),
              _buildGenreChips(),
              const SizedBox(height: 26),
              _sectionTitle('评分'),
              const SizedBox(height: 4),
              _buildRatingSlider(),
              const SizedBox(height: 26),
              _sectionTitle('演员信息'),
              const SizedBox(height: 10),
              _buildCastEditor(),
              const SizedBox(height: 26),
              _sectionTitle('我的影评'),
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
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceHigh,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lib.canPickImage)
              ListTile(
                leading: const Icon(Icons.photo_library_outlined,
                    color: AppColors.textSecondary),
                title: const Text('从相册选择',
                    style: TextStyle(color: AppColors.textPrimary)),
                onTap: () => Navigator.of(ctx).pop('pick'),
              ),
            ListTile(
              leading: const Icon(Icons.link_rounded,
                  color: AppColors.textSecondary),
              title: const Text('粘贴网络图片链接',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(ctx).pop('url'),
            ),
            ListTile(
              leading: const Icon(Icons.image_not_supported_outlined,
                  color: Color(0xFFFF6B6B)),
              title: const Text('移除海报',
                  style: TextStyle(color: Color(0xFFFF6B6B))),
              onTap: () => Navigator.of(ctx).pop('remove'),
            ),
          ],
        ),
      ),
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
        backgroundColor: AppColors.surfaceHigh,
        title: const Text('网络图片链接',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.url,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          cursorColor: AppColors.accent,
          decoration: InputDecoration(
            hintText: 'https://…',
            hintStyle:
                const TextStyle(color: AppColors.textMuted, fontSize: 13),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.outline, width: 0.8),
            ),
          ),
          onChanged: (s) => url = s,
          onSubmitted: (s) => Navigator.of(ctx).pop(s),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(url),
            child: const Text('确定',
                style: TextStyle(
                    color: AppColors.accent, fontWeight: FontWeight.w700)),
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
    final title = _titleCtrl.text.trim().isEmpty ? '电影' : _titleCtrl.text.trim();
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
                padding:
                    const EdgeInsets.symmetric(vertical: 10),
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

  // ---------- 通用输入框 ----------

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        filled: true,
        fillColor: AppColors.surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outline, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.outline, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.3),
        ),
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
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.outline, width: 0.8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value ?? '选择日期（可跳过）',
                style: TextStyle(
                  color: value == null
                      ? AppColors.textMuted
                      : AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: value == null ? FontWeight.normal : FontWeight.w600,
                ),
              ),
            ),
            Icon(
              value == null
                  ? Icons.expand_more_rounded
                  : Icons.close_rounded,
              size: 18,
              color: value == null ? AppColors.textMuted : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 类型 Tag 多选 ----------

  Widget _buildGenreChips() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final g in kMovieCategories)
          FilterChip(
            label: Text(g),
            selected: _selectedGenres.contains(g),
            onSelected: (selected) => setState(() {
              if (selected) {
                _selectedGenres.add(g);
              } else {
                _selectedGenres.remove(g);
              }
            }),
            selectedColor: AppColors.movieStart.withOpacity(0.28),
            backgroundColor: AppColors.surfaceHigh,
            side: BorderSide(
              color: _selectedGenres.contains(g)
                  ? AppColors.movieStart
                  : AppColors.outline,
              width: 1,
            ),
            labelStyle: TextStyle(
              color: _selectedGenres.contains(g)
                  ? AppColors.movieEnd
                  : AppColors.textSecondary,
              fontSize: 13,
              fontWeight:
                  _selectedGenres.contains(g) ? FontWeight.w700 : FontWeight.w500,
            ),
            showCheckmark: false,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
      ],
    );
  }

  // ---------- 评分 Slider + 实时星级 ----------

  Widget _buildRatingSlider() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '我的评分',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const Spacer(),
              Text(
                _rating > 0 ? '${_rating.toStringAsFixed(1)} 分' : '未评分',
                style: TextStyle(
                  color: _rating > 0 ? AppColors.star : AppColors.textMuted,
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
              activeTrackColor: AppColors.movieStart,
              inactiveTrackColor: AppColors.outline,
              thumbColor: Colors.white,
              overlayColor: AppColors.movieStart.withOpacity(0.15),
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
                    color:
                        _rating >= i - 0.25 ? AppColors.star : AppColors.textMuted.withOpacity(0.4),
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
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.outline, width: 0.8),
            ),
            child: const Center(
              child: Text(
                '还没有演员，点击下方「添加演员」，输入姓名联想选择或新建',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
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
                  Container(
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
                  const SizedBox(width: 10),
                  Expanded(child: _buildActorField(slot)),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: '移除',
                    onPressed: () => setState(() {
                      slot.dispose();
                      _actorSlots.remove(slot);
                    }),
                    icon: const Icon(Icons.remove_circle_outline_rounded,
                        color: Color(0xFFFF6B6B), size: 22),
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
              foregroundColor: AppColors.accent,
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
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => onFieldSubmitted(),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          cursorColor: AppColors.accent,
          decoration: InputDecoration(
            hintText: '输入姓名联想选择或新建',
            hintStyle: const TextStyle(
                color: AppColors.textMuted, fontSize: 13),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: AppColors.outline, width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: AppColors.outline, width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                  color: AppColors.accent, width: 1.2),
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onChoose, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: AppColors.surface,
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
                            const Icon(Icons.person_add_alt_1_rounded,
                                size: 17, color: AppColors.accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '新建演员「${actor.name}」',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.accent,
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
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
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
          onChanged: (_) => setState(() {}),
          style: const TextStyle(
              color: AppColors.textPrimary, fontSize: 14, height: 1.5),
          cursorColor: AppColors.accent,
          decoration: InputDecoration(
            hintText: '写下你的观影感受…',
            hintStyle:
                const TextStyle(color: AppColors.textMuted, fontSize: 14),
            filled: true,
            fillColor: AppColors.surfaceHigh,
            alignLabelWithHint: true,
            counterText: '',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.outline, width: 0.8),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.outline, width: 0.8),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.3),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${_reviewCtrl.text.length}/$_reviewMaxChars',
            style: TextStyle(
              color: _reviewCtrl.text.length >= _reviewMaxChars
                  ? const Color(0xFFFF6B6B)
                  : AppColors.textMuted,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  // ---------- 底部操作栏 ----------

  Widget _buildActions() {
    const gradient = AppColors.movieGradient;
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
                  color: AppColors.movieStart.withOpacity(0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _save,
                child: Center(
                  child: Text(
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
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.outline, width: 1),
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
                      backgroundColor: const Color(0xFFE5484D),
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

  // ---------- 区块标题 ----------

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }
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

  void dispose() {
    ctrl.dispose();
    focus.dispose();
  }
}