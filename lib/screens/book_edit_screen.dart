import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../models/book.dart';
import '../models/media_ref.dart';
import '../providers/library_provider.dart';
import '../widgets/media_cover.dart';
import '../widgets/star_rating_picker.dart';

/// 编辑页返回约定：null = 取消；'saved' = 已保存；'deleted' = 已删除
const String kEditResultSaved = 'saved';
const String kEditResultDeleted = 'deleted';

/// 图书编辑 / 新增界面（双模式）
///
/// - 传入 [bookId] → 编辑模式：AppBar「编辑图书」，显示删除按钮，保存走 `updateBook`
/// - 不传 [bookId] → 新增模式：AppBar「添加图书」，隐藏删除按钮，保存走 `addBook`
///
/// 布局对齐参考图 3：
/// - 左侧小封面（Change Cover 徽标）+ 右侧书名/作者/总页数输入框
/// - 星级评分选择器（点击 1-5 星，再点当前星清除）
/// - 进度滑动条（实时百分比徽标，拖动联动阅读状态）
/// - 分类下拉 + 阅读感悟多行输入
/// - 底部：保存（渐变主按钮）/ 取消 / 删除（仅编辑模式，需确认）
class BookEditScreen extends StatefulWidget {
  const BookEditScreen({super.key, this.bookId});

  final String? bookId;

  @override
  State<BookEditScreen> createState() => _BookEditScreenState();
}

class _BookEditScreenState extends State<BookEditScreen> {
  bool get _isAddMode => widget.bookId == null;

  /// 编辑模式下按 id 查找失败（书已被删除等）
  bool _notFound = false;

  /// 新增模式下随机生成的封面色相（仅生成一次，避免 rebuild 变色）
  late final double _addCoverHue;

  late final TextEditingController _titleCtrl;
  late final TextEditingController _authorCtrl;
  late final TextEditingController _pagesCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _notesCtrl;
  late double _rating;
  late double _progress;
  late final TextEditingController _categoryCtrl;
  late final FocusNode _categoryFocus;

  /// 添加时间：编辑 = 原书值；新增 = 当前时刻（开始阅读时间的默认值来源）
  late final DateTime _createdAt;

  /// 开始阅读时间（想读状态隐藏字段，进入在读时默认为 [_createdAt]）
  DateTime? _startedAt;

  /// 阅读完成时间（进度 100% 自动填今天；手动选择联动进度拉满）
  DateTime? _finishedAt;

  /// 从相册选中、尚未复制进 images/ 的封面（保存时 attach）
  File? _pendingCoverFile;

  /// 网络封面地址输入（粘贴图片链接）
  final TextEditingController _coverUrlCtrl = TextEditingController();

  /// 封面是否被用户动过（选图/填 URL/移除）——决定保存时沿用原图还是覆盖
  bool _coverEdited = false;

  Book? _book;

  @override
  void initState() {
    super.initState();
    _addCoverHue = Random().nextDouble() * 360;

    if (_isAddMode) {
      _notFound = false;
      _book = null;
      _createdAt = DateTime.now();
    } else {
      final provider = context.read<LibraryProvider>();
      final matches =
          provider.books.where((b) => b.id == widget.bookId).toList();
      _book = matches.isEmpty ? null : matches.first;
      _notFound = _book == null;
      _createdAt = _book?.createdAt ?? DateTime.now();
    }
    _startedAt = _book?.startedAt;
    _finishedAt = _book?.finishedAt;

    _titleCtrl = TextEditingController(text: _book?.title ?? '');
    _authorCtrl = TextEditingController(text: _book?.author ?? '');
    _pagesCtrl =
        TextEditingController(text: _book == null ? '300' : '${_book!.totalPages}');
    _descCtrl = TextEditingController(text: _book?.description ?? '');
    _notesCtrl = TextEditingController(text: _book?.notes ?? '');
    _rating = _book?.rating ?? 0;
    _progress = _book?.progress ?? 0;
    _categoryCtrl = TextEditingController(text: _book?.category ?? '');
    _categoryFocus = FocusNode();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _pagesCtrl.dispose();
    _categoryCtrl.dispose();
    _categoryFocus.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    _coverUrlCtrl.dispose();
    super.dispose();
  }

  BookStatus get _statusFromProgress {
    if (_progress >= 1.0) return BookStatus.finished;
    if (_progress > 0) return BookStatus.reading;
    return BookStatus.planToRead;
  }

  /// 表单当前生效的总页数（新增/编辑共用，输入非法时回退）
  int get _effectiveTotalPages =>
      max(1, int.tryParse(_pagesCtrl.text.trim()) ?? _book?.totalPages ?? 300);

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final author = _authorCtrl.text.trim();
    if (title.isEmpty || author.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('书名与作者不能为空')),
      );
      return;
    }
    final finished = _finishedAt;
    final started = _startedAt;
    if (finished != null &&
        started != null &&
        finished.isBefore(started)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('完成时间不能早于开始时间')),
      );
      return;
    }
    final provider = context.read<LibraryProvider>();

    final totalPages = _effectiveTotalPages;
    final currentPage = (_progress * totalPages).round().clamp(0, totalPages);
    final rating = _rating > 0 ? _rating : null;
    final categoryText = _categoryCtrl.text.trim();
    final category = categoryText.isEmpty ? null : categoryText;
    final description = _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();
    final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    // 新增/编辑统一先在保存时刻确定 id（新增 = 微秒时间戳），供封面复制落盘
    final id = _isAddMode
        ? 'b_${DateTime.now().microsecondsSinceEpoch}'
        : _book!.id;
    final cover = await _resolveDraftCover(provider, id);

    if (_isAddMode) {
      provider.addBook(Book(
        id: id,
        title: title,
        author: author,
        totalPages: totalPages,
        currentPage: currentPage,
        status: _statusFromProgress,
        coverHue: _addCoverHue,
        cover: cover,
        rating: rating,
        category: category,
        description: description,
        notes: notes,
        createdAt: _createdAt,
        startedAt: started,
        finishedAt: _completeWithDefault(started, finished),
      ));
    } else {
      final original = _book;
      if (original == null) return;
      provider.updateBook(original.copyWith(
        title: title,
        author: author,
        totalPages: totalPages,
        currentPage: currentPage,
        status: _statusFromProgress,
        cover: cover,
        rating: rating,
        category: category,
        description: description,
        notes: notes,
        startedAt: started,
        finishedAt: _completeWithDefault(started, finished),
      ));
    }
    if (!mounted) return;
    Navigator.of(context).pop(kEditResultSaved);
  }

  /// 计算保存时的封面引用：
  /// - 选中了本地图 → 先复制进 images/<id><ext> 再返回 local 引用；
  /// - 没动过封面 → 沿用原图（含 null）；
  /// - 动过：填了 URL → 网络引用；URL 为空 → 移除封面（null）。
  Future<MediaRef?> _resolveDraftCover(
    LibraryProvider provider,
    String id,
  ) async {
    final pending = _pendingCoverFile;
    if (pending != null) {
      final rel = await provider.attachImage(pending, id);
      return rel == null ? null : MediaRef.local(rel);
    }
    if (!_coverEdited) return _book?.cover;
    final url = _coverUrlCtrl.text.trim();
    return url.isEmpty ? null : MediaRef.network(url);
  }

  /// 完成时间兜底：进度 100% 却无完成记录时补今天（如旧数据/直接拖满场景）。
  /// 传参会覆盖 copyWith 保留语义——因此仅在有值或需补全时返回非 null。
  DateTime? _completeWithDefault(DateTime? started, DateTime? finished) {
    if (_progress < 1.0) return finished;
    return finished ?? _dateOnly(DateTime.now());
  }

  /// 进度条拖动（即时跟手）：进入 100% 自动补完成时间；离开 0 默认开始时间=添加时间
  void _onProgressChanged(double v) {
    setState(() {
      _progress = v;
      if (v > 0 && _startedAt == null) {
        _startedAt = _dateOnly(_createdAt);
      }
      if (v >= 1.0 && _finishedAt == null) {
        _finishedAt = _dateOnly(DateTime.now());
      }
    });
  }

  /// 拖动结束：从「已完成」往回退且存在完成记录 → 二次确认后才允许清空
  Future<void> _onProgressChangeEnd(double v) async {
    // _progress 已跟手到 v：只有「拖到 <100% 且当前有完成记录」才需确认
    if (v >= 1.0 || _finishedAt == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceHigh,
        title:  Text(
          '回退阅读进度？',
          style: TextStyle(color: context.colors.textPrimary, fontSize: 18),
        ),
        content: Text(
          '该书已有完成记录（${_fmtDate(_finishedAt!)}），继续回退将清除完成记录并回到「在读」。',
          style:  TextStyle(color: context.colors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:  Text('取消',
                style: TextStyle(color: context.colors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认回退',
                style: TextStyle(
                    color: Color(0xFFFFB020), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      setState(() => _finishedAt = null);
    } else {
      setState(() => _progress = 1.0);
    }
  }

  /// 弹出日期选择器并回写（完成时间选择 = 读完 → 联动进度拉满）
  Future<void> _pickDate({required bool isFinished}) async {
    final initial = isFinished ? (_finishedAt ?? DateTime.now()) : (_startedAt ?? _createdAt);
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOnly(initial),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: isFinished ? '选择阅读完成时间' : '选择开始阅读时间',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFinished) {
        _finishedAt = _dateOnly(picked);
        _progress = 1.0;
        _startedAt ??= _dateOnly(_createdAt);
      } else {
        _startedAt = _dateOnly(picked);
      }
    });
  }

  /// 归一到日（忽略时分秒）
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// yyyy-MM-dd
  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _confirmDelete() async {
    final book = _book;
    if (book == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceHigh,
        title:  Text(
          '删除这本书？',
          style: TextStyle(color: context.colors.textPrimary, fontSize: 18),
        ),
        content: Text(
          '《${book.title}》将从书库中移除，此操作不可撤销。',
          style:  TextStyle(color: context.colors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                 Text('取消', style: TextStyle(color: context.colors.textMuted)),
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

    context.read<LibraryProvider>().deleteBook(book.id);
    Navigator.of(context).pop(kEditResultDeleted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(_isAddMode ? '添加图书' : '编辑图书'),
        backgroundColor: Colors.transparent,
      ),
      body: !_isAddMode && _notFound
          ?  Center(
              child:
                  Text('未找到该书', style: TextStyle(color: context.colors.textMuted)),
            )
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _sectionTitle('评分'),
                    const SizedBox(height: 4),
                    Center(
                      child: StarRatingPicker(
                        rating: _rating,
                        onChanged: (v) => setState(() => _rating = v),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('阅读进度'),
                    const SizedBox(height: 8),
                    _buildProgressCard(),
                    // 阅读时间区块：想读且无任何记录时整块隐藏（_readingTimeBlocks 返回空）
                    ..._readingTimeBlocks(),
                    const SizedBox(height: 24),
                    _sectionTitle('分类'),
                    const SizedBox(height: 8),
                    _buildCategoryField(),
                    const SizedBox(height: 24),
                    _sectionTitle('内容简介'),
                    const SizedBox(height: 8),
                    _buildMultilineField(
                      controller: _descCtrl,
                      hint: '用几句话介绍这本书讲什么…',
                      minLines: 3,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 24),
                    _sectionTitle('阅读感悟'),
                    const SizedBox(height: 8),
                    _buildMultilineField(
                      controller: _notesCtrl,
                      hint: '写下你的阅读感悟…',
                    ),
                    const SizedBox(height: 32),
                    _buildActions(),
                  ],
                ),
              ),
            ),
    );
  }

  // ---------- 顶部：封面 + 书名/作者输入 ----------

  /// 封面预览输入：编辑态未改动 → 原图；动过后 → URL 文本（网络）或空（占位）；
  /// 选中本地图时由 [MediaCover.pendingFile] 优先展示，[media] 归位 null。
  MediaRef? get _previewCoverMedia {
    if (_coverEdited) {
      final url = _coverUrlCtrl.text.trim();
      return url.isEmpty ? null : MediaRef.network(url);
    }
    return _book?.cover;
  }

  Widget _buildHeader() {
    // 新增模式下封面预览实时跟随书名输入，色相为 initState 生成的随机值
    final previewTitle =
        _titleCtrl.text.trim().isEmpty ? '书籍' : _titleCtrl.text.trim();
    final hue = _book?.coverHue ?? _addCoverHue;
    final emoji = _book?.emoji ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧封面
        SizedBox(
          width: 108,
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MediaCover(
                  media: _previewCoverMedia,
                  pendingFile: _pendingCoverFile,
                  title: previewTitle,
                  emoji: emoji,
                  hue: hue,
                  aspectRatio: 3 / 4,
                  borderRadius: 0,
                  fontSize: 30,
                ),
              ),
              const SizedBox(height: 6),
              // 更换封面：从相册选择 / 粘贴网络链接 / 移除
              InkWell(
                onTap: _openCoverMenu,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_outlined,
                          size: 13, color: context.colors.textSecondary),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '更换封面',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        // 右侧输入区
        Expanded(
          child: Column(
            children: [
              _inputField(
                controller: _titleCtrl,
                label: '书名',
                hint: '输入书名',
                // 书名实时联动左侧封面预览
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              _inputField(
                controller: _authorCtrl,
                label: '作者',
                hint: '输入作者',
              ),
              const SizedBox(height: 10),
              _inputField(
                controller: _pagesCtrl,
                label: '总页数',
                hint: '如 328',
                keyboardType: TextInputType.number,
                // 页数变化联动进度条换算
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- 封面编辑（选图 / URL / 移除）----------

  /// 更换封面菜单：从相册选择（持久模式）/ 粘贴网络链接 / 移除封面
  Future<void> _openCoverMenu() async {
    final lib = context.read<LibraryProvider>();
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.surfaceHigh,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (lib.canPickImage)
              ListTile(
                leading:  Icon(Icons.photo_library_outlined,
                    color: context.colors.textSecondary),
                title:  Text('从相册选择',
                    style: TextStyle(color: context.colors.textPrimary)),
                onTap: () => Navigator.of(ctx).pop('pick'),
              ),
            ListTile(
              leading:  Icon(Icons.link_rounded,
                  color: context.colors.textSecondary),
              title:  Text('粘贴网络图片链接',
                  style: TextStyle(color: context.colors.textPrimary)),
              onTap: () => Navigator.of(ctx).pop('url'),
            ),
            ListTile(
              leading: const Icon(Icons.image_not_supported_outlined,
                  color: Color(0xFFFF6B6B)),
              title: const Text('移除封面',
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
        await _promptCoverUrl();
      case 'remove':
        setState(() {
          _coverEdited = true;
          _pendingCoverFile = null;
          _coverUrlCtrl.clear();
        });
    }
  }

  /// 系统相册选图（保存时才复制进 images/，取消/失败则维持现状）
  Future<void> _pickFromGallery() async {
    final lib = context.read<LibraryProvider>();
    final picked = await lib.pickImageFile();
    if (picked == null || !mounted) return; // 用户取消
    setState(() {
      _coverEdited = true;
      _pendingCoverFile = picked;
      _coverUrlCtrl.clear();
    });
  }

  /// 弹出 URL 输入框；非空则设为网络封面
  Future<void> _promptCoverUrl() async {
    var url = '';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceHigh,
        title:  Text('网络图片链接',
            style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700)),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.url,
          style:  TextStyle(color: context.colors.textPrimary, fontSize: 14),
          cursorColor: context.colors.accent,
          decoration: InputDecoration(
            hintText: 'https://…',
            hintStyle:
                 TextStyle(color: context.colors.textMuted, fontSize: 13),
            filled: true,
            fillColor: context.colors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                   BorderSide(color: context.colors.outline, width: 0.8),
            ),
          ),
          onChanged: (s) => url = s,
          onSubmitted: (s) => Navigator.of(ctx).pop(s),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:  Text('取消',
                style: TextStyle(color: context.colors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(url),
            child:  Text('确定',
                style: TextStyle(
                    color: context.colors.accent, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    final trimmed = result.trim();
    setState(() {
      _coverEdited = true;
      _pendingCoverFile = null;
      _coverUrlCtrl.text = trimmed;
    });
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
    VoidCallback? onSubmitted,
    FocusNode? focusNode,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      onSubmitted: onSubmitted == null
          ? null
          : (_) => onSubmitted(),
      focusNode: focusNode,
      style:  TextStyle(color: context.colors.textPrimary, fontSize: 15),
      cursorColor: context.colors.accent,
      decoration: InputDecoration(
        labelText: label,
        labelStyle:  TextStyle(color: context.colors.textMuted, fontSize: 13),
        hintText: hint,
        hintStyle:  TextStyle(color: context.colors.textMuted, fontSize: 14),
        filled: true,
        fillColor: context.colors.surfaceHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:  BorderSide(color: context.colors.outline, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:  BorderSide(color: context.colors.outline, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:  BorderSide(color: context.colors.accent, width: 1.3),
        ),
      ),
    );
  }

  // ---------- 区块小标题 ----------

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style:  TextStyle(
        color: context.colors.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  // ---------- 进度条卡片 ----------

  Widget _buildProgressCard() {
    final percent = (_progress * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
               Text(
                '已完成',
                style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  gradient: context.colors.readingGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$percent%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              activeTrackColor: context.colors.readingStart,
              inactiveTrackColor: context.colors.outline,
              thumbColor: Colors.white,
              overlayColor: context.colors.readingStart.withOpacity(0.15),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: _progress,
              onChanged: _onProgressChanged,
              onChangeEnd: _onProgressChangeEnd,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '状态：${_statusFromProgress.label} · ${(_progress * _effectiveTotalPages).round()} / $_effectiveTotalPages 页',
            style:  TextStyle(color: context.colors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ---------- 阅读时间 ----------

  /// 阅读时间区块（想读且无任何记录时返回空，整块隐藏）
  List<Widget> _readingTimeBlocks() {
    final inReading = _progress > 0 || _startedAt != null || _finishedAt != null;
    if (!inReading) return const [];

    final blocks = <Widget>[
      const SizedBox(height: 24),
      _sectionTitle('阅读时间'),
      const SizedBox(height: 8),
      _dateField(
        label: '开始阅读',
        date: _startedAt,
        hint: '默认添加时间，点击选择',
        onTap: () => _pickDate(isFinished: false),
        onClear: _startedAt == null ? null : () => setState(() => _startedAt = null),
      ),
    ];
    if (_progress >= 1.0 || _finishedAt != null) {
      blocks
        ..add(const SizedBox(height: 10))
        ..add(_dateField(
          label: '阅读完成',
          date: _finishedAt,
          hint: '进度 100% 时自动记录，点击修改',
          onTap: () => _pickDate(isFinished: true),
          // 完成时间无独立清除入口：修改走日期选择，删除=拖回进度（需二次确认）
          onClear: null,
        ));
    }
    return blocks;
  }

  /// 日期字段行：点击弹日期选择器；有值时可显示清除入口
  Widget _dateField({
    required String label,
    required DateTime? date,
    required String hint,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final hasValue = date != null;
    return Material(
      color: context.colors.surfaceHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(
                hasValue ? Icons.event_available_rounded : Icons.event_outlined,
                size: 20,
                color: hasValue ? context.colors.readingStart : context.colors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style:  TextStyle(
                          color: context.colors.textMuted, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      date != null ? _fmtDate(date) : hint,
                      style: TextStyle(
                        color: hasValue
                            ? context.colors.textPrimary
                            : context.colors.textMuted,
                        fontSize: 14,
                        fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  behavior: HitTestBehavior.opaque,
                  child:  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded,
                        size: 18, color: context.colors.textMuted),
                  ),
                )
              else
                 Icon(Icons.edit_calendar_outlined,
                    size: 18, color: context.colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 分类下拉 ----------

  /// 分类联想候选：预设分类 ∪ 书库实际使用过的分类（去重，预设在前）
  List<String> get _categoryOptions {
    final used = context.read<LibraryProvider>().usedCategories;
    return <String>{...kBookCategories, ...used}.toList(growable: false);
  }

  /// 分类输入：Autocomplete 联想已有分类（包含匹配），无匹配可直接输入自定义分类。
  /// 自定义值保存进 book.category 后，经 usedCategories 自动进入后续联想与筛选。
  Widget _buildCategoryField() {
    return RawAutocomplete<String>(
      textEditingController: _categoryCtrl,
      focusNode: _categoryFocus,
      optionsBuilder: (value) {
        final query = value.text.trim();
        final options = _categoryOptions;
        if (query.isEmpty) return options;
        return options.where((c) => c.contains(query)).toList(growable: false);
      },
      displayStringForOption: (c) => c,
      onSelected: (_) => _categoryFocus.unfocus(),
      // 注意：fieldViewBuilder 第 4 参数是 onFieldSubmitted（回车确认选中项），
      // 不是 onChanged！文本变化由 RawAutocomplete 通过 controller 监听自行响应。
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return _inputField(
          controller: controller,
          focusNode: focusNode,
          label: '分类',
          hint: '输入或选择分类',
          onSubmitted: onFieldSubmitted,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
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
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Text(
                        option,
                        style:  TextStyle(
                            color: context.colors.textPrimary, fontSize: 14),
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

  // ---------- 多行输入（简介 / 感悟共用样式）----------

  Widget _buildMultilineField({
    required TextEditingController controller,
    required String hint,
    int minLines = 4,
    int maxLines = 5,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      style:  TextStyle(
          color: context.colors.textPrimary, fontSize: 14, height: 1.5),
      cursorColor: context.colors.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:  TextStyle(color: context.colors.textMuted, fontSize: 14),
        filled: true,
        fillColor: context.colors.surfaceHigh,
        alignLabelWithHint: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:  BorderSide(color: context.colors.outline, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:  BorderSide(color: context.colors.outline, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:  BorderSide(color: context.colors.accent, width: 1.3),
        ),
      ),
    );
  }

  // ---------- 底部操作按钮 ----------

  Widget _buildActions() {
    return Column(
      children: [
        // 保存（主操作，渐变高亮）
        SizedBox(
          width: double.infinity,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: context.colors.readingGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: context.colors.readingStart.withOpacity(0.35),
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
                    _isAddMode ? '添加图书' : '保存修改',
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
        // 取消（新增模式独占整行，无删除按钮可显示）
        SizedBox(
          width: double.infinity,
          height: 50,
          child: _isAddMode
              ? OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.colors.textSecondary,
                    side:  BorderSide(color: context.colors.outline, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('取消', style: TextStyle(fontSize: 15)),
                )
              : Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.colors.textSecondary,
                          side:
                               BorderSide(color: context.colors.outline, width: 1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child:
                            const Text('取消', style: TextStyle(fontSize: 15)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
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
                            Text('删除图书',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
