import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../component/media/media_cover.dart';
import '../../../component/theme/app_palette.dart';
import '../../../foundation/constants/app_strings.dart';
import '../../../foundation/utils/date_format.dart';
import '../../data_source/model/data_source.dart';
import '../../data_source/service/book_category_mapper.dart';
import '../../data_source/view_model/data_source_provider.dart';
import '../model/book.dart';
import '../model/edit_result.dart';
import '../view/edit_form_view.dart'
    show TextPromptDialog, showCoverActionSheet;
import '../view/quick_search_panel.dart';
import '../view/star_rating_picker.dart';
import '../view_model/book_edit_controller.dart';
import '../view_model/library_provider.dart';

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
class BookEditPage extends StatefulWidget {
  const BookEditPage({super.key, this.bookId});

  final String? bookId;

  @override
  State<BookEditPage> createState() => _BookEditPageState();
}

class _BookEditPageState extends State<BookEditPage> {
  /// 表单状态与业务逻辑（M-5）：校验、页数 / 状态推导、封面解析、保存组装。
  /// 放在控制器里，可脱离 Widget 树直接单测。
  late final BookEditController _c;

  // ---------- 快速检索（联网信息补全）状态：与 Provider / BuildContext 强耦合，留在页面 ----------

  /// 搜索词输入
  final TextEditingController _searchCtrl = TextEditingController();

  /// 搜索 debounce 定时器（800ms，避免逐字符/逐拼音打接口）
  Timer? _searchDebounce;

  /// 最近一次选中回填的搜索结果（收起态「已填充《书名》」标记）
  BookSearchResult? _filledResult;

  @override
  void initState() {
    super.initState();
    final String? bookId = widget.bookId;
    Book? initial;
    if (bookId != null) {
      final matches =
          context.read<LibraryProvider>().books.where((b) => b.id == bookId);
      initial = matches.isEmpty ? null : matches.first;
    }
    _c = BookEditController(bookId: bookId, initialBook: initial);
    // 控制器**内部推导**的变化（如页数变化自动补开始 / 完成时间）→ 重建页面；
    // 用户在 UI 上的直接编辑仍由 setState 驱动，避免同一次改动重建两次。
    _c.addListener(_onControllerChanged);
    // 快速检索框：listener 驱动搜索（可读 IME composing，见 _onSearchCtrlChanged）
    _searchCtrl.addListener(_onSearchCtrlChanged);
  }

  /// 控制器内部推导引起的变化 → 重建页面
  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_onControllerChanged);
    _c.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ---------- 保存 ----------

  Future<void> _save() async {
    if (_c.saving) return;
    // 校验与二次确认必须在进 loading 之前完成：确认框弹出时保存按钮若已转圈，
    // 会呈现「用户尚未确认却在保存」的错误状态（且 loading 是无限动画，
    // 会让 pumpAndSettle 无法收敛）。
    if (!await _confirmBeforeSave()) return;
    if (!mounted) return;
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

  /// 保存前的校验与二次确认。返回 false = 中断保存（已提示或用户取消）。
  ///
  /// 判断逻辑在 [BookEditController.validate] / `needsFinishedClearConfirm`；
  /// 这里只负责提示、弹窗与取消。
  Future<bool> _confirmBeforeSave() async {
    final error = _c.validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return false;
    }
    // 已读页数未填满但仍有完成记录 → 回退需二次确认（对应旧滑杆回退确认）
    if (_c.needsFinishedClearConfirm) {
      final confirmed = await _confirmClearFinished(_c.finishedAt!);
      if (!confirmed) return false;
      _c.finishedAt = null;
    }
    return true;
  }

  Future<void> _doSave() async {
    final provider = context.read<LibraryProvider>();
    final book = await _c.composeBook(provider);
    if (book == null) return;
    if (_c.isAddMode) {
      provider.addBook(book);
    } else {
      provider.updateBook(book);
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
          '该书已有完成记录（${formatDateYmd(finished)}），保存后将清除完成记录并回到「在读」。',
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

  /// 弹出日期选择器并回写（完成时间选择 = 读完 → 已读页数拉满）
  Future<void> _pickDate({required bool isFinished}) async {
    final initial = isFinished
        ? (_c.finishedAt ?? DateTime.now())
        : (_c.startedAt ?? _c.createdAt);
    final picked = await showDatePicker(
      context: context,
      initialDate: dateOnly(initial),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: isFinished ? '选择阅读完成时间' : '选择开始阅读时间',
    );
    if (picked == null || !mounted) return;
    if (isFinished) {
      _c.applyFinishedDate(picked);
    } else {
      _c.applyStartedDate(picked);
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _confirmDelete() async {
    if (_c.saving) return;
    final book = _c.book;
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
      appBar: _buildAppBar(),
      body: !_c.isAddMode && _c.notFound
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
                    if (!_c.isAddMode) ...[
                      const SizedBox(height: 28),
                      _buildDeleteButton(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  /// 顶部导航栏：标题 + 取消（左）与保存（右，含加载态）。
  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      centerTitle: true,
      title: Text(
        _c.isAddMode ? AppStrings.addBook : '修改书籍记录',
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
            color: _c.saving
                ? context.colors.accent.withOpacity(0.5)
                : context.colors.accent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: _c.saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: _c.saving
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

  Widget _buildHeaderCard() {
    // 色相为 initState 生成的随机值
    final hue = _c.book?.coverHue ?? _c.addCoverHue;
    final emoji = _c.book?.emoji ?? '';
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCoverTile(hue, emoji),
          const SizedBox(width: 14),
          _buildTitleAuthorColumn(),
        ],
      ),
    );
  }

  /// 封面缩略图（点按更换，实时跟随书名）。
  Widget _buildCoverTile(double hue, String emoji) {
    return Tooltip(
      message: '更换封面',
      child: GestureDetector(
        onTap: _openCoverMenu,
        child: SizedBox(
          width: 88,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            // H4：封面预览实时跟随书名输入，但只重建封面本身
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _c.titleCtrl,
              builder: (_, value, __) {
                final title = value.text.trim();
                return MediaCover(
                  media: _c.previewCoverMedia,
                  pendingFile: _c.pendingCoverFile,
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
    );
  }

  /// 书名 / 作者 / 出版社 / 分类标签列。
  Widget _buildTitleAuthorColumn() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _c.titleCtrl,
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
            controller: _c.authorCtrl,
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
                valueListenable: _c.publisherCtrl,
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

  /// 分类输入：胶囊样式 + Autocomplete 联想（包含匹配），可直接输入自定义分类。
  Widget _buildCategoryChipField() {
    return RawAutocomplete<String>(
      textEditingController: _c.categoryCtrl,
      focusNode: _c.categoryFocus,
      optionsBuilder: (value) {
        final query = value.text.trim();
        final options = _c.categoryOptions(
          context.read<LibraryProvider>().usedCategories,
        );
        if (query.isEmpty) return options;
        return options.where((c) => c.contains(query)).toList(growable: false);
      },
      displayStringForOption: (c) => c,
      onSelected: (_) => _c.categoryFocus.unfocus(),
      // 注意：fieldViewBuilder 第 4 参数是 onFieldSubmitted（回车确认选中项），
      // 不是 onChanged！文本变化由 RawAutocomplete 通过 controller 监听自行响应。
      fieldViewBuilder: _buildCategoryFieldView,
      optionsViewBuilder: _buildCategoryOptionsView,
    );
  }

  /// 分类输入框（RawAutocomplete 的 fieldViewBuilder）。
  Widget _buildCategoryFieldView(
    BuildContext context,
    TextEditingController controller,
    FocusNode focusNode,
    void Function() onFieldSubmitted,
  ) {
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
  }

  /// 分类联想下拉（RawAutocomplete 的 optionsViewBuilder）。
  Widget _buildCategoryOptionsView(
    BuildContext context,
    AutocompleteOnSelected<String> onSelected,
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
              return InkWell(
                onTap: () => onSelected(option),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                AppStrings.myRating,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                _c.rating > 0 ? '${_c.rating.toStringAsFixed(1)} 分' : AppStrings.unrated,
                style: TextStyle(
                  color: _c.rating > 0
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
                  rating: _c.rating,
                  size: 30,
                  onChanged: (v) => setState(() => _c.rating = v),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '轻按或拖动星星打分\n再点一次清除',
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
                listenable: Listenable.merge([_c.pagesCtrl, _c.currentPagesCtrl]),
                builder: (_, __) => _statusPill(context, _c.statusFromProgress),
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
              _numBox(_c.currentPagesCtrl, '0'),
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
              _numBox(_c.pagesCtrl, '300'),
            ],
          ),
          const SizedBox(height: 10),
          // 自动状态说明（总页数实时带入）
          ListenableBuilder(
            listenable: _c.pagesCtrl,
            builder: (_, __) => Text(
              '* 填 0 页自动为「想读」，填满 $_c.effectiveTotalPages 页自动为「完成」',
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
        _c.effectiveCurrentPages > 0 || _c.startedAt != null || _c.finishedAt != null;
    if (!inReading) return const [];

    final blocks = <Widget>[
      const SizedBox(height: 16),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dateField(
              label: AppStrings.readingStart,
              date: _c.startedAt,
              hint: '默认添加时间，点击选择',
              onTap: () => _pickDate(isFinished: false),
              onClear: _c.startedAt == null
                  ? null
                  : () => setState(() => _c.startedAt = null),
            ),
            if (_c.progressAtLeastFull || _c.finishedAt != null) ...[
              const SizedBox(height: 10),
              _dateField(
                label: AppStrings.readingFinished,
                date: _c.finishedAt,
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
                      date != null ? formatDateYmd(date) : hint,
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
            controller: _c.publisherCtrl,
            onTap: _editPublisher,
          ),
          _metaDivider(),
          _metaRow(
            icon: Icons.calendar_today_rounded,
            label: AppStrings.publishYear,
            controller: _c.yearCtrl,
            onTap: _editYear,
          ),
          _metaDivider(),
          _metaRow(
            icon: Icons.tag_rounded,
            label: AppStrings.isbnLabel,
            controller: _c.isbnCtrl,
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
  /// 单行文本输入对话框（出版社 / 年份 / ISBN / 封面链接共用）
  ///
  /// controller 的生命周期交给 [TextPromptDialog] 自己管理——不能在这里
  /// 「showDialog 返回后 dispose」：对话框退场动画期间 TextField 会重建并
  /// 重新 addListener，提前释放会抛 used after being disposed。
  Future<String?> _promptTextDialog({
    required String title,
    required String initial,
    TextInputType? keyboardType,
    String? hint,
    bool allowClear = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => TextPromptDialog(
        title: title,
        initial: initial,
        keyboardType: keyboardType,
        hint: hint,
        allowClear: allowClear,
      ),
    );
  }

  Future<void> _editPublisher() async {
    final r = await _promptTextDialog(
      title: '出版社',
      initial: _c.publisherCtrl.text,
      hint: '如 南海出版公司',
      allowClear: true,
    );
    if (r == null || !mounted) return;
    setState(() => _c.publisherCtrl.text = r.trim());
  }

  Future<void> _editYear() async {
    final r = await _promptTextDialog(
      title: AppStrings.publishYear,
      initial: _c.yearCtrl.text,
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
    setState(() => _c.yearCtrl.text = trimmed);
  }

  Future<void> _editIsbn() async {
    final r = await _promptTextDialog(
      title: AppStrings.isbnLabel,
      initial: _c.isbnCtrl.text,
      hint: 'ISBN-13 / ISBN-10',
      allowClear: true,
    );
    if (r == null || !mounted) return;
    setState(() => _c.isbnCtrl.text = r.trim());
  }

  // ---------- 卡片 5/6：内容简介 / 阅读感悟 & 划线 ----------

  Widget _buildDescCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.synopsis,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _buildMultilineInCard(
            controller: _c.descCtrl,
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
            AppStrings.bookNotes,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _buildMultilineInCard(
            controller: _c.notesCtrl,
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
    // 聚合检索时结果可能来自多个源（默认源 + 备用源），如实标注来源，
    // 不让用户以为手上这条一定出自默认源。
    final usedSources = ds.bookSearchSourceNames;
    final sourceLabel = usedSources.length > 1
        ? '${usedSources.first} 等 ${usedSources.length} 个源'
        : (usedSources.isNotEmpty ? usedSources.first : source.name);
    return [
      QuickSearchPanel(
        controller: _searchCtrl,
        hint: '输入书名 / 作者，联网搜索并回填',
        sourceName: sourceLabel,
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
          // 详情失败原因（null = 成功）：简介 / 分类依赖详情，失败要让用户看见
          final detailError = ds.lastDetailError;

          // 页面可能在详情请求期间被关闭；此时不能再触碰 State 或页面上下文。
          if (!mounted) return;
          // 详情拉完后清空列表（保留搜索框文本），再回填
          ds.clearResults();
          _applyBookResult(resultToApply, ds, detailWarning: detailError);
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
  ///
  /// [detailWarning] 详情补全的失败原因（null = 详情成功）；
  /// 简介 / 分类多数来自详情接口，失败时必须在提示里说明，不能静默。
  void _applyBookResult(
    BookSearchResult r,
    DataSourceProvider ds, {
    String? detailWarning,
  }) {
    final source = ds.defaultBookSource;
    setState(() {
      _c.titleCtrl.text = r.title;
      _c.authorCtrl.text = r.authorsText;
      if (r.pageCount != null && r.pageCount! > 0) {
        _c.pagesCtrl.text = '${r.pageCount}';
      }
      if (r.isbn != null && r.isbn!.isNotEmpty) _c.isbnCtrl.text = r.isbn!;
      if (r.publisher != null && r.publisher!.trim().isNotEmpty) {
        _c.publisherCtrl.text = r.publisher!.trim();
      }
      if (r.year != null) _c.yearCtrl.text = '${r.year}';
      if (r.description != null && r.description!.isNotEmpty) {
        _c.descCtrl.text = r.description!;
      }
      // 分类：数据源给的是英文主题词（Fiction / Science fiction…），
      // 经 BookCategoryMapper 映射成本地中文分类（未命中则保留原文）。
      // 换选新书时一律覆盖——否则会残留上一本书的分类。
      final mapped = BookCategoryMapper.map(r.categories);
      if (mapped != null) _c.categoryCtrl.text = mapped;
      // 评分**刻意不自动填充**：数据源给的是豆瓣 / OpenLibrary 的「大众平均分」，
      // 与用户自己的打分不是一回事——混进来会让「我的评分」变成别人的均分。
      // 评分只由用户在上方星级里自己打。
      if (r.coverUrl != null && r.coverUrl!.isNotEmpty) {
        _c.coverEdited = true;
        _c.pendingCoverFile = null;
        _c.coverUrlCtrl.text = r.coverUrl!;
      }
      _filledResult = r;
      _c.sourceTag =
          source == null ? null : '${source.type.name}:${r.externalId}';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          detailWarning == null
              ? '已自动填充《${r.title}》'
              : '已填充《${r.title}》（基础信息）；简介/分类补全失败：$detailWarning',
        ),
        duration: detailWarning == null
            ? const Duration(seconds: 2)
            : const Duration(seconds: 4),
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
      // 有书籍默认源才给「联网自动找封面」——没配源时点了也只会白等
      canLookup:
          _tryReadDataSource(context, listen: false)?.defaultBookSource != null,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'pick':
        await _pickFromGallery();
      case 'url':
        await _promptCoverUrl();
      case 'lookup':
        await _lookupCoverOnline();
      case 'remove':
        setState(() {
          _c.coverEdited = true;
          _c.pendingCoverFile = null;
          _c.coverUrlCtrl.clear();
        });
    }
  }

  /// 联网给「手动录入」的书找一张封面（按 ISBN 优先、否则书名）。
  ///
  /// 网络要 2–5s，用一个不自动消失的 SnackBar 当进度提示（结束主动收起），
  /// 省掉一个只服务单次交互的 State 字段。命中即写入封面 URL，走「粘贴链接」
  /// 同一条通道；保存时由 [_resolveDraftCover] 缓存到本地。
  Future<void> _lookupCoverOnline() async {
    final ds = _tryReadDataSource(context, listen: false);
    final title = _c.titleCtrl.text.trim();
    final isbn = _c.isbnCtrl.text.trim();
    if (ds == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.noBookSourceForCover)),
      );
      return;
    }
    if (title.isEmpty && isbn.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先填上书名或 ISBN，再做联网查找')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('正在联网查找封面…'),
      // 正常情况下结束时会 hide；给个长时长只是防「异常路径下永久挂着」
      duration: Duration(minutes: 1),
    ));
    String? url;
    try {
      url = await ds.lookupBookCover(title: title, isbn: isbn);
    } finally {
      if (mounted) messenger.hideCurrentSnackBar();
    }
    if (!mounted) return;

    if (url == null || url.isEmpty) {
      // L-8：区分两种成因——「数据源没返回」vs「返回了但该记录无封面图」——
      // 减少用户无效重试。
      messenger.showSnackBar(SnackBar(
        content: Text(
          isbn.isEmpty
              ? '按书名没找到封面，填上 ISBN 再试会更准'
              : '这个 ISBN 在数据源里没有封面图，可改用「粘贴网络图片链接」',
        ),
      ));
      return;
    }
    setState(() {
      _c.coverEdited = true;
      _c.pendingCoverFile = null;
      _c.coverUrlCtrl.text = url!;
    });
    messenger.showSnackBar(const SnackBar(content: Text('已找到封面，保存后生效')));
  }

  /// 系统相册选图（保存时才复制进 images/，取消/失败则维持现状）
  Future<void> _pickFromGallery() async {
    final lib = context.read<LibraryProvider>();
    final picked = await lib.pickImageFile();
    if (picked == null || !mounted) return; // 用户取消
    setState(() {
      _c.coverEdited = true;
      _c.pendingCoverFile = picked;
      _c.coverUrlCtrl.clear();
    });
  }

  /// 弹出 URL 输入框；非空则设为网络封面
  Future<void> _promptCoverUrl() async {
    final result = await _promptTextDialog(
      title: AppStrings.networkImageUrl,
      initial: _c.coverUrlCtrl.text,
      hint: 'https://…',
      keyboardType: TextInputType.url,
    );
    if (result == null || !mounted) return;
    final trimmed = result.trim();
    setState(() {
      _c.coverEdited = true;
      _c.pendingCoverFile = null;
      _c.coverUrlCtrl.text = trimmed;
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
