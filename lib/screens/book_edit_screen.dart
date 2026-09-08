import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../config/edit_results.dart';
import '../models/book.dart';
import '../models/data_source.dart';
import '../models/media_ref.dart';
import '../providers/data_source_provider.dart';
import '../providers/library_provider.dart';
import '../widgets/edit_form_widgets.dart' show showCoverActionSheet;
import '../widgets/media_cover.dart';
import '../widgets/quick_search_panel.dart';
import '../widgets/star_rating_picker.dart';

/// 图书编辑 / 新增界面（双模式，v2 卡片式布局）
///
/// - 传入 [bookId] → 编辑模式：顶栏「修改书籍记录」，底部保留删除按钮，保存走 `updateBook`
/// - 不传 [bookId] → 新增模式：顶栏「添加图书」，无删除按钮，保存走 `addBook`
///
/// 对齐参考图 2：
/// - 顶栏：取消 · 标题 · 保存胶囊
/// - 卡片 1：封面（点按更换）+ 书名/作者无边框输入 + 出版社/分类标签
/// - 卡片 2：我的评分（星星 + 分数）
/// - 卡片 3：阅读进度更新（状态胶囊 + 已读页数/总页数输入，0 页=想读、填满=完成）
/// - 卡片 4：出版社 / 出版年份 / ISBN 行（点按弹窗编辑）
/// - 卡片 5/6：内容简介、阅读感悟 & 划线（1000 字计数）
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
  late final TextEditingController _isbnCtrl;
  late final TextEditingController _pagesCtrl;

  /// 已读页数（替代旧滑杆；0 = 想读，填满总页数 = 完成）
  late final TextEditingController _currentPagesCtrl;

  late final TextEditingController _publisherCtrl;
  late final TextEditingController _yearCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _notesCtrl;
  late double _rating;
  late final TextEditingController _categoryCtrl;
  late final FocusNode _categoryFocus;

  /// 添加时间：编辑 = 原书值；新增 = 当前时刻（开始阅读时间的默认值来源）
  late final DateTime _createdAt;

  /// 开始阅读时间（想读状态隐藏字段，进入在读时默认为 [_createdAt]）
  DateTime? _startedAt;

  /// 阅读完成时间（填满总页数自动填今天；回退需保存时二次确认）
  DateTime? _finishedAt;

  /// 从相册选中、尚未复制进 images/ 的封面（保存时 attach）
  File? _pendingCoverFile;

  /// 网络封面地址输入（粘贴图片链接）
  final TextEditingController _coverUrlCtrl = TextEditingController();

  /// 封面是否被用户动过（选图/填 URL/移除）——决定保存时沿用原图还是覆盖
  bool _coverEdited = false;

  Book? _book;

  // ---------- 快速检索（联网信息补全）状态 ----------

  /// 搜索词输入
  final TextEditingController _searchCtrl = TextEditingController();

  /// 搜索 debounce 定时器（800ms，避免逐字符/逐拼音打接口）
  Timer? _searchDebounce;

  /// 最近一次选中回填的搜索结果（收起态「已填充《书名》」标记）
  BookSearchResult? _filledResult;

  /// 数据溯源标记（保存时写入 Book.source，如 'googleBooks:xyz'）
  String? _sourceTag;

  /// 防止双击重复提交
  bool _saving = false;

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
    _isbnCtrl = TextEditingController(text: _book?.isbn ?? '');
    _pagesCtrl = TextEditingController(
        text: _book == null ? '300' : '${_book!.totalPages}');
    _currentPagesCtrl =
        TextEditingController(text: '${_book?.currentPage ?? 0}');
    _publisherCtrl = TextEditingController(text: _book?.publisher ?? '');
    _yearCtrl = TextEditingController(
        text: _book?.year == null ? '' : '${_book!.year}');
    _descCtrl = TextEditingController(text: _book?.description ?? '');
    _notesCtrl = TextEditingController(text: _book?.notes ?? '');
    _rating = _book?.rating ?? 0;
    _categoryCtrl = TextEditingController(text: _book?.category ?? '');
    _categoryFocus = FocusNode();
    // 快速检索框：listener 驱动搜索（可读 IME composing，见 _onSearchCtrlChanged）
    _searchCtrl.addListener(_onSearchCtrlChanged);
    // 已读页数变化 → 自动补开始/完成时间（见 _onCurrentPagesChanged）
    _currentPagesCtrl.addListener(_onCurrentPagesChanged);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _isbnCtrl.dispose();
    _pagesCtrl.dispose();
    _currentPagesCtrl.dispose();
    _publisherCtrl.dispose();
    _yearCtrl.dispose();
    _categoryCtrl.dispose();
    _categoryFocus.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    _coverUrlCtrl.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ---------- 页数与状态 ----------

  /// 表单当前生效的总页数（输入非法时回退：编辑 = 原书值，新增 = 300）
  int get _effectiveTotalPages =>
      max(1, int.tryParse(_pagesCtrl.text.trim()) ?? _book?.totalPages ?? 300);

  /// 表单当前生效的已读页数（非法输入按 0；超出总页数截断——填满即完成）
  int get _effectiveCurrentPages {
    final v = int.tryParse(_currentPagesCtrl.text.trim()) ?? 0;
    return v.clamp(0, _effectiveTotalPages);
  }

  BookStatus get _statusFromProgress {
    if (_effectiveCurrentPages >= _effectiveTotalPages) {
      return BookStatus.finished;
    }
    if (_effectiveCurrentPages > 0) return BookStatus.reading;
    return BookStatus.planToRead;
  }

  /// 已读页数变化的自动联动：
  /// - >0 且无开始记录 → 默认开始时间 = 添加时间
  /// - 填满总页数且无完成记录 → 自动补今天
  void _onCurrentPagesChanged() {
    final cur = _effectiveCurrentPages;
    final total = _effectiveTotalPages;
    DateTime? start = _startedAt;
    DateTime? fin = _finishedAt;
    if (cur > 0 && start == null) start = _dateOnly(_createdAt);
    if (total > 0 && cur >= total && fin == null) {
      fin = _dateOnly(DateTime.now());
    }
    if (start != _startedAt || fin != _finishedAt) {
      setState(() {
        _startedAt = start;
        _finishedAt = fin;
      });
    }
  }

  /// ISBN 输入归一（空串 → null）
  String? get _isbnValue {
    final v = _isbnCtrl.text.trim();
    return v.isEmpty ? null : v;
  }

  // ---------- 保存 ----------

  Future<void> _save() async {
    if (_saving) return;
    // 校验与二次确认必须在进 loading 之前完成：确认框弹出时保存按钮若已转圈，
    // 会呈现「用户尚未确认却在保存」的错误状态（且 loading 是无限动画，
    // 会让 pumpAndSettle 无法收敛）。
    if (!await _confirmBeforeSave()) return;
    if (!mounted) return;
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

  /// 保存前的校验与二次确认。返回 false = 中断保存（已提示或用户取消）。
  Future<bool> _confirmBeforeSave() async {
    final title = _titleCtrl.text.trim();
    final author = _authorCtrl.text.trim();
    if (title.isEmpty || author.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('书名与作者不能为空')),
      );
      return false;
    }
    final finished = _finishedAt;
    final started = _startedAt;
    if (finished != null && started != null && finished.isBefore(started)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('完成时间不能早于开始时间')),
      );
      return false;
    }
    // 已读页数未填满但仍有完成记录 → 回退需二次确认（对应旧滑杆回退确认）
    if (_effectiveCurrentPages < _effectiveTotalPages && finished != null) {
      final confirmed = await _confirmClearFinished(finished);
      if (!confirmed) return false;
      _finishedAt = null;
    }
    return true;
  }

  Future<void> _doSave() async {
    final title = _titleCtrl.text.trim();
    final author = _authorCtrl.text.trim();
    final started = _startedAt;
    final totalPages = _effectiveTotalPages;
    final currentPage = _effectiveCurrentPages;

    final provider = context.read<LibraryProvider>();

    final rating = _rating > 0 ? _rating : null;
    final categoryText = _categoryCtrl.text.trim();
    final category = categoryText.isEmpty ? null : categoryText;
    final publisherText = _publisherCtrl.text.trim();
    final publisher = publisherText.isEmpty ? null : publisherText;
    final year = int.tryParse(_yearCtrl.text.trim());
    final description =
        _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim();
    final notes =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    // 新增/编辑统一先在保存时刻确定 id（新增 = 微秒时间戳），供封面复制落盘
    final id =
        _isAddMode ? 'b_${DateTime.now().microsecondsSinceEpoch}' : _book!.id;
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
        publisher: publisher,
        year: year,
        description: description,
        notes: notes,
        isbn: _isbnValue,
        source: _sourceTag,
        createdAt: _createdAt,
        startedAt: started,
        finishedAt: _completeWithDefault(started, _finishedAt),
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
        // publisher/year 为 sentinel 参数：显式传值（含 null 清空）均生效
        publisher: publisher,
        year: year,
        description: description,
        notes: notes,
        isbn: _isbnValue,
        // 未重新检索时保留原溯源标记（copyWith 传 null 会清字段）
        source: _sourceTag ?? original.source,
        startedAt: started,
        finishedAt: _completeWithDefault(started, _finishedAt),
      ));
    }
    if (!mounted) return;
    Navigator.of(context).pop(kEditResultSaved);
  }

  /// 已有完成记录却把已读页数改到未满 → 确认后清除完成记录
  Future<bool> _confirmClearFinished(DateTime finished) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceHigh,
        title: Text(
          '回退阅读进度？',
          style: TextStyle(color: context.colors.textPrimary, fontSize: 18),
        ),
        content: Text(
          '该书已有完成记录（${_fmtDate(finished)}），保存后将清除完成记录并回到「在读」。',
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
            child: Text('确认回退',
                style: TextStyle(
                    color: context.colors.warning,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// 计算保存时的封面引用：
  /// - 选中了本地图 → 先复制进 images/<id><ext> 再返回 local 引用；
  /// - 没动过封面 → 沿用原图（含 null）；
  /// - 动过：填了 URL → **先缓存到本地**（成功 = local+remote 双引用，
  ///   展示优先读本地、离线回退 URL；缓存失败 = 纯网络引用）；URL 空 → 移除。
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
    if (url.isEmpty) return null;
    final cached = await provider.cacheRemoteImage(url, 'book_cover');
    if (cached != null) return MediaRef(localFile: cached, remoteUrl: url);
    return MediaRef.network(url);
  }

  /// 完成时间兜底：进度 100% 却无完成记录时补今天（如旧数据/直接填满场景）。
  /// 传参会覆盖 copyWith 保留语义——因此仅在有值或需补全时返回非 null。
  DateTime? _completeWithDefault(DateTime? started, DateTime? finished) {
    if (_effectiveCurrentPages < _effectiveTotalPages) return finished;
    return finished ?? _dateOnly(DateTime.now());
  }

  /// 弹出日期选择器并回写（完成时间选择 = 读完 → 已读页数拉满）
  Future<void> _pickDate({required bool isFinished}) async {
    final initial = isFinished
        ? (_finishedAt ?? DateTime.now())
        : (_startedAt ?? _createdAt);
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
        _currentPagesCtrl.text = '$_effectiveTotalPages';
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
    if (_saving) return;
    final book = _book;
    if (book == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceHigh,
        title: Text(
          '删除这本书？',
          style: TextStyle(color: context.colors.textPrimary, fontSize: 18),
        ),
        content: Text(
          '《${book.title}》将从书库中移除，此操作不可撤销。',
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

    context.read<LibraryProvider>().deleteBook(book.id);
    Navigator.of(context).pop(kEditResultDeleted);
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        centerTitle: true,
        title: Text(
          _isAddMode ? '添加图书' : '修改书籍记录',
          style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        leadingWidth: 68,
        leading: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: Text(
              '取消',
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 15,
              ),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Material(
              color: _saving
                  ? context.colors.accent.withOpacity(0.5)
                  : context.colors.accent,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _saving ? null : _save,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '保存',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: !_isAddMode && _notFound
          ? Center(
              child: Text('未找到该书',
                  style: TextStyle(color: context.colors.textMuted)),
            )
          : SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 快速检索（联网补全）：无默认书籍数据源时整块隐藏
                    ..._quickSearchBlocks(),
                    _buildHeaderCard(),
                    const SizedBox(height: 16),
                    _buildRatingCard(),
                    const SizedBox(height: 16),
                    _buildProgressCard(),
                    // 阅读时间区块：想读且无任何记录时整块隐藏
                    ..._readingTimeBlocks(),
                    const SizedBox(height: 16),
                    _buildMetaCard(),
                    const SizedBox(height: 16),
                    _buildDescCard(),
                    const SizedBox(height: 16),
                    _buildNotesCard(),
                    // 底部删除（仅编辑模式；新增模式无删除入口）
                    if (!_isAddMode) ...[
                      const SizedBox(height: 28),
                      _buildDeleteButton(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  // ---------- 通用卡片容器 ----------

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }

  // ---------- 卡片 1：封面 + 书名 / 作者 / 标签 ----------

  /// 封面预览输入：编辑态未改动 → 原图；动过后 → URL 文本（网络）或空（占位）；
  /// 选中本地图时由 [MediaCover.pendingFile] 优先展示，[media] 归位 null。
  MediaRef? get _previewCoverMedia {
    if (_coverEdited) {
      final url = _coverUrlCtrl.text.trim();
      return url.isEmpty ? null : MediaRef.network(url);
    }
    return _book?.cover;
  }

  Widget _buildHeaderCard() {
    // 色相为 initState 生成的随机值
    final hue = _book?.coverHue ?? _addCoverHue;
    final emoji = _book?.emoji ?? '';
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面（点按更换）
          Tooltip(
            message: '更换封面',
            child: GestureDetector(
              onTap: _openCoverMenu,
              child: SizedBox(
                width: 88,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  // H4：封面预览实时跟随书名输入，但只重建封面本身
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _titleCtrl,
                    builder: (_, value, __) {
                      final title = value.text.trim();
                      return MediaCover(
                        media: _previewCoverMedia,
                        pendingFile: _pendingCoverFile,
                        title: title.isEmpty ? '书籍' : title,
                        emoji: emoji,
                        hue: hue,
                        aspectRatio: 3 / 4,
                        borderRadius: 0,
                        fontSize: 26,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // 书名 / 作者 / 标签
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _titleCtrl,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                  cursorColor: context.colors.accent,
                  decoration: _borderless('输入书名', 16),
                ),
                const SizedBox(height: 2),
                TextField(
                  controller: _authorCtrl,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 13.5,
                  ),
                  cursorColor: context.colors.accent,
                  decoration: _borderless('输入作者', 13),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // 出版社标签（检索回填或「出版社」行编辑后展示）
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _publisherCtrl,
                      builder: (_, value, __) {
                        final p = value.text.trim();
                        return p.isEmpty
                            ? const SizedBox.shrink()
                            : _MetaChip(label: p);
                      },
                    ),
                    _buildCategoryChipField(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 无边框输入装饰（卡片内书名 / 作者行）
  InputDecoration _borderless(String hint, double hintFontSize) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(
        color: context.colors.textMuted.withOpacity(0.8),
        fontSize: hintFontSize,
      ),
      border: InputBorder.none,
      contentPadding: EdgeInsets.zero,
    );
  }

  // ---------- 分类标签输入（联想 + 自定义）----------

  /// 分类联想候选：预设分类 ∪ 书库实际使用过的分类（去重，预设在前）
  List<String> get _categoryOptions {
    final used = context.read<LibraryProvider>().usedCategories;
    return <String>{...kBookCategories, ...used}.toList(growable: false);
  }

  /// 分类输入：胶囊样式 + Autocomplete 联想（包含匹配），可直接输入自定义分类。
  Widget _buildCategoryChipField() {
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
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.colors.outline, width: 0.8),
          ),
          child: SizedBox(
            width: 110,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onSubmitted: (_) => onFieldSubmitted(),
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: context.colors.accent,
              decoration: InputDecoration(
                isDense: true,
                hintText: '分类',
                hintStyle: TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
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
      },
    );
  }

  // ---------- 卡片 2：我的评分 ----------

  Widget _buildRatingCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '我的评分',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                _rating > 0 ? '${_rating.toStringAsFixed(1)} 分' : '未评分',
                style: TextStyle(
                  color: _rating > 0
                      ? context.colors.star
                      : context.colors.textMuted,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: StarRatingPicker(
                  rating: _rating,
                  size: 30,
                  onChanged: (v) => setState(() => _rating = v),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '轻按星星评分\n再点一次清除',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: context.colors.textMuted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 卡片 3：阅读进度更新 ----------

  Widget _buildProgressCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题 + 状态胶囊（页数输入实时联动）
          Row(
            children: [
              Icon(Icons.menu_book_rounded,
                  size: 16, color: context.colors.textSecondary),
              const SizedBox(width: 8),
              Text(
                '阅读进度更新',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              // H4：状态胶囊只随两个页数输入重建
              ListenableBuilder(
                listenable: Listenable.merge([_pagesCtrl, _currentPagesCtrl]),
                builder: (_, __) => _statusPill(context, _statusFromProgress),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 已读 / 总页数输入行
          Row(
            children: [
              Text(
                '已读页数：',
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 13.5),
              ),
              _numBox(_currentPagesCtrl, '0'),
              const SizedBox(width: 10),
              Text('/',
                  style:
                      TextStyle(color: context.colors.textMuted, fontSize: 13)),
              const SizedBox(width: 10),
              Text(
                '总页数：',
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 13.5),
              ),
              _numBox(_pagesCtrl, '300'),
            ],
          ),
          const SizedBox(height: 10),
          // 自动状态说明（总页数实时带入）
          ListenableBuilder(
            listenable: _pagesCtrl,
            builder: (_, __) => Text(
              '* 填 0 页自动为「想读」，填满 $_effectiveTotalPages 页自动为「完成」',
              style: TextStyle(
                color: context.colors.textMuted,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numBox(TextEditingController controller, String hint) {
    return Container(
      width: 82,
      height: 42,
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.outline, width: 0.8),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: context.colors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        cursorColor: context.colors.accent,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(
            color: context.colors.textMuted.withOpacity(0.7),
            fontSize: 14,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _statusPill(BuildContext context, BookStatus status) {
    final color = switch (status) {
      BookStatus.reading => context.colors.success,
      BookStatus.finished => context.colors.star,
      BookStatus.planToRead => context.colors.accent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.7), width: 1),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ---------- 阅读时间 ----------

  /// 阅读时间区块（想读且无任何记录时返回空，整块隐藏）
  List<Widget> _readingTimeBlocks() {
    final inReading =
        _effectiveCurrentPages > 0 || _startedAt != null || _finishedAt != null;
    if (!inReading) return const [];

    final blocks = <Widget>[
      const SizedBox(height: 16),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dateField(
              label: '开始阅读',
              date: _startedAt,
              hint: '默认添加时间，点击选择',
              onTap: () => _pickDate(isFinished: false),
              onClear: _startedAt == null
                  ? null
                  : () => setState(() => _startedAt = null),
            ),
            if (_progressAtLeastFull || _finishedAt != null) ...[
              const SizedBox(height: 10),
              _dateField(
                label: '阅读完成',
                date: _finishedAt,
                hint: '填满总页数时自动记录，点击修改',
                onTap: () => _pickDate(isFinished: true),
                // 完成时间无独立清除入口：改小已读页数保存时二次确认清除
                onClear: null,
              ),
            ],
          ],
        ),
      ),
    ];
    return blocks;
  }

  bool get _progressAtLeastFull =>
      _effectiveCurrentPages >= _effectiveTotalPages;

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
      color: context.colors.surface,
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
                color: hasValue
                    ? context.colors.readingStart
                    : context.colors.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
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
                        fontWeight:
                            hasValue ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (onClear != null)
                GestureDetector(
                  onTap: onClear,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
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

  // ---------- 卡片 4：出版社 / 出版年份 / ISBN ----------

  Widget _buildMetaCard() {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          _metaRow(
            icon: Icons.business_outlined,
            label: '出版社',
            controller: _publisherCtrl,
            onTap: _editPublisher,
          ),
          _metaDivider(),
          _metaRow(
            icon: Icons.calendar_today_rounded,
            label: '出版年份',
            controller: _yearCtrl,
            onTap: _editYear,
          ),
          _metaDivider(),
          _metaRow(
            icon: Icons.tag_rounded,
            label: 'ISBN / 标识',
            controller: _isbnCtrl,
            onTap: _editIsbn,
          ),
        ],
      ),
    );
  }

  Widget _metaDivider() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(height: 0.6, color: context.colors.outline),
      );

  Widget _metaRow({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              Icon(icon, size: 16, color: context.colors.textSecondary),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // H4：值文本只随自身 controller 重建
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (_, value, __) {
                  final v = value.text.trim();
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(
                      v.isEmpty ? '未设置' : v,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: v.isEmpty
                            ? context.colors.textMuted
                            : context.colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: context.colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  /// 通用单行文本编辑弹窗。返回 null = 取消；'' = 清除；其他 = 新值。
  Future<String?> _promptTextDialog({
    required String title,
    required String initial,
    TextInputType? keyboardType,
    String? hint,
    bool allowClear = false,
  }) {
    var value = initial;
    final ctrl = TextEditingController(text: initial)
      ..selection = TextSelection.collapsed(offset: initial.length);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceHigh,
        title: Text(
          title,
          style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700),
        ),
        content: TextField(
          autofocus: true,
          keyboardType: keyboardType,
          controller: ctrl,
          style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
          cursorColor: context.colors.accent,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: context.colors.textMuted, fontSize: 13),
            filled: true,
            fillColor: context.colors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.outline, width: 0.8),
            ),
          ),
          onChanged: (s) => value = s,
          onSubmitted: (s) => Navigator.of(ctx).pop(s),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                Text('取消', style: TextStyle(color: context.colors.textMuted)),
          ),
          if (allowClear && initial.trim().isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: Text(
                '清除',
                style: TextStyle(
                    color: context.colors.danger, fontWeight: FontWeight.w700),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(value),
            child: Text(
              '确定',
              style: TextStyle(
                  color: context.colors.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editPublisher() async {
    final r = await _promptTextDialog(
      title: '出版社',
      initial: _publisherCtrl.text,
      hint: '如 南海出版公司',
      allowClear: true,
    );
    if (r == null || !mounted) return;
    setState(() => _publisherCtrl.text = r.trim());
  }

  Future<void> _editYear() async {
    final r = await _promptTextDialog(
      title: '出版年份',
      initial: _yearCtrl.text,
      hint: '如 2011',
      keyboardType: TextInputType.number,
      allowClear: true,
    );
    if (r == null || !mounted) return;
    final trimmed = r.trim();
    if (trimmed.isNotEmpty && int.tryParse(trimmed) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('年份需为数字，如 2011')),
      );
      return;
    }
    setState(() => _yearCtrl.text = trimmed);
  }

  Future<void> _editIsbn() async {
    final r = await _promptTextDialog(
      title: 'ISBN / 标识',
      initial: _isbnCtrl.text,
      hint: 'ISBN-13 / ISBN-10',
      allowClear: true,
    );
    if (r == null || !mounted) return;
    setState(() => _isbnCtrl.text = r.trim());
  }

  // ---------- 卡片 5/6：内容简介 / 阅读感悟 & 划线 ----------

  Widget _buildDescCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '内容简介',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _buildMultilineInCard(
            controller: _descCtrl,
            hint: '用几句话介绍这本书讲什么…',
            minLines: 3,
            maxLines: 5,
          ),
        ],
      ),
    );
  }

  Widget _buildNotesCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '阅读感悟 & 划线',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _buildMultilineInCard(
            controller: _notesCtrl,
            hint: '写下你的阅读感悟与划线摘录…',
            minLines: 3,
            maxLines: 8,
            maxLength: 1000,
          ),
        ],
      ),
    );
  }

  /// 卡片内无边框多行输入；[maxLength] 非空时右下角显示「n / max」计数
  Widget _buildMultilineInCard({
    required TextEditingController controller,
    required String hint,
    int minLines = 3,
    int maxLines = 5,
    int? maxLength,
  }) {
    final field = TextField(
      controller: controller,
      maxLines: maxLines,
      minLines: minLines,
      maxLength: maxLength,
      style: TextStyle(
        color: context.colors.textPrimary,
        fontSize: 14,
        height: 1.6,
      ),
      cursorColor: context.colors.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
            color: context.colors.textMuted.withOpacity(0.8), fontSize: 13.5),
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
        // 计数由下方自绘（对齐设计稿样式），隐藏 Flutter 自带 counter
        counterText: '',
      ),
    );
    if (maxLength == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field,
        const SizedBox(height: 6),
        // H4：计数只随自身输入重建
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, __) => Align(
            alignment: Alignment.centerRight,
            child: Text(
              '${value.text.characters.length} / $maxLength',
              style: TextStyle(
                color: context.colors.textMuted,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- 底部删除 ----------

  Widget _buildDeleteButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: _confirmDelete,
        style: OutlinedButton.styleFrom(
          foregroundColor: context.colors.danger,
          side: BorderSide(color: context.colors.danger.withOpacity(0.45)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline_rounded, size: 18),
            SizedBox(width: 6),
            Text('删除图书',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ---------- 快速检索（联网信息补全）----------

  /// 检索区块：未注入 DataSourceProvider（部分测试只给 LibraryProvider）
  /// 或无默认书籍数据源时整块隐藏，不影响手动录入。
  /// 呈现由 [QuickSearchPanel] 承担（M5 与 movie_edit 共用）；
  /// 搜索触发（debounce）与结果回填差异留在本 State。
  List<Widget> _quickSearchBlocks() {
    final DataSourceProvider? ds = _tryReadDataSource(context);
    final source = ds?.defaultBookSource;
    if (ds == null || source == null) return const [];
    return [
      QuickSearchPanel(
        controller: _searchCtrl,
        hint: '输入书名 / 作者，联网搜索并回填',
        sourceName: source.name,
        isSearching: ds.isSearching,
        error: ds.searchError,
        results: ds.bookResults
            ?.map((r) => QuickSearchItem(
                  title: r.title,
                  subtitle: r.subtitle,
                  coverUrl: r.coverUrl,
                  externalId: r.externalId,
                ))
            .toList(),
        filledExternalId: _filledResult?.externalId,
        filledTitle: _filledResult?.title,
        tagColor: context.colors.readingStart,
        fallbackIcon: Icons.menu_book_outlined,
        onClear: () {
          _searchDebounce?.cancel();
          _searchCtrl.clear();
          ds.clearResults();
          setState(() {});
        },
        onPick: (item) async {
          // 从展示投影找回原始结果对象再回填（回填消费完整模型字段）
          final matches =
              ds.bookResults?.where((r) => r.externalId == item.externalId);
          if (matches == null || matches.isEmpty) return;
          final searchResult = matches.first;
          setState(() {});

          // 先用搜索结果回填基本信息，同时拉详情补全
          BookSearchResult? detailResult;
          try {
            detailResult = await ds.fetchBookDetail(searchResult);
          } catch (_) {
            // 详情失败静默回退搜索结果
          }
          // 合并而非替换：搜索结果 = 基础，详情非空字段覆盖。
          // 避免「详情接口不返回 isbn/页数/出版社时被 null 覆盖丢失」。
          final resultToApply = detailResult == null
              ? searchResult
              : searchResult.mergeWith(detailResult);

          // 页面可能在详情请求期间被关闭；此时不能再触碰 State 或页面上下文。
          if (!mounted) return;
          // 详情拉完后清空列表（保留搜索框文本），再回填
          ds.clearResults();
          _applyBookResult(resultToApply, ds);
        },
      ),
      const SizedBox(height: 16),
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
  /// - M8：清除按钮显隐改用 QuickSearchPanel 内 ValueListenableBuilder，
  ///   不再因输入触发整页 setState / rebuild；
  /// - IME 拼音组合输入中（composing 有效）不发起搜索，避免输入
  ///   「三体」的拼音过程打出多次半成品查询；
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
      _tryReadDataSource(context, listen: false)?.searchBooks(q);
    });
  }

  /// 选中搜索结果 → 自动回填表单（可继续手动修改；封面走网络 URL 通道）
  void _applyBookResult(BookSearchResult r, DataSourceProvider ds) {
    final source = ds.defaultBookSource;
    setState(() {
      _titleCtrl.text = r.title;
      _authorCtrl.text = r.authorsText;
      if (r.pageCount != null && r.pageCount! > 0) {
        _pagesCtrl.text = '${r.pageCount}';
      }
      if (r.isbn != null && r.isbn!.isNotEmpty) _isbnCtrl.text = r.isbn!;
      if (r.publisher != null && r.publisher!.trim().isNotEmpty) {
        _publisherCtrl.text = r.publisher!.trim();
      }
      if (r.year != null) _yearCtrl.text = '${r.year}';
      if (r.description != null && r.description!.isNotEmpty) {
        _descCtrl.text = r.description!;
      }
      // 分类：多值时取第一个（书籍 category 是单值）
      final primary = r.primaryCategory;
      if (primary != null && _categoryCtrl.text.trim().isEmpty) {
        _categoryCtrl.text = primary;
      }
      if (r.rating != null && r.rating! > 0) _rating = r.rating!;
      if (r.coverUrl != null && r.coverUrl!.isNotEmpty) {
        _coverEdited = true;
        _pendingCoverFile = null;
        _coverUrlCtrl.text = r.coverUrl!;
      }
      _filledResult = r;
      _sourceTag =
          source == null ? null : '${source.type.name}:${r.externalId}';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已自动填充《${r.title}》'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------- 封面编辑（选图 / URL / 移除）----------

  /// 更换封面菜单：从相册选择（持久模式）/ 粘贴网络链接 / 移除封面
  Future<void> _openCoverMenu() async {
    final lib = context.read<LibraryProvider>();
    final action = await showCoverActionSheet(
      context: context,
      canPickImage: lib.canPickImage,
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
    final result = await _promptTextDialog(
      title: '网络图片链接',
      initial: _coverUrlCtrl.text,
      hint: 'https://…',
      keyboardType: TextInputType.url,
    );
    if (result == null || !mounted) return;
    final trimmed = result.trim();
    setState(() {
      _coverEdited = true;
      _pendingCoverFile = null;
      _coverUrlCtrl.text = trimmed;
    });
  }
}

/// 编辑页头部卡片的小标签（出版社 / 分类胶囊）
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.outline, width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.textSecondary,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
