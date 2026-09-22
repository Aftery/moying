import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../../component/media/model/media_ref.dart';
import '../../../foundation/utils/date_format.dart';
import '../../shared/model/book.dart';
import 'library_provider.dart';

/// 图书编辑页的表单状态与业务逻辑（M-5）。
///
/// 迁出 [BookEditPage] 之前散落在 State 里的三件事：
/// 1. **表单字段**（12 个 `TextEditingController` + 评分 / 时间 / 封面草稿）；
/// 2. **推导与校验**（有效页数、状态判定、ISBN 归一、保存前校验）；
/// 3. **保存组装**（封面落盘 → 组装 `Book` 或 `copyWith` 原书）。
///
/// State 只保留 Widget 构建与弹窗 / 导航，于是上述逻辑可以脱离 Widget 树
/// 直接跑单元测试（此前只能写慢且脆的 widget test）。
///
/// **通知约定**：控制器只对自己**内部推导**引起的变化 `notifyListeners()`
/// （典型是「已读页数变化 → 自动补开始 / 完成时间」）；用户在 UI 上的直接
/// 编辑仍由 State 用 `setState` 触发重建，避免同一次改动被重建两次。
class BookEditController extends ChangeNotifier {
  BookEditController({this.bookId, Book? initialBook})
      : _book = initialBook,
        rating = initialBook?.rating ?? 0,
        notFound = bookId != null && initialBook == null,
        addCoverHue = Random().nextDouble() * 360 {
    createdAt = _book?.createdAt ?? DateTime.now();
    startedAt = _book?.startedAt;
    finishedAt = _book?.finishedAt;

    titleCtrl = TextEditingController(text: _book?.title ?? '');
    authorCtrl = TextEditingController(text: _book?.author ?? '');
    isbnCtrl = TextEditingController(text: _book?.isbn ?? '');
    pagesCtrl = TextEditingController(
        text: _book == null ? '300' : '${_book.totalPages}');
    currentPagesCtrl =
        TextEditingController(text: '${_book?.currentPage ?? 0}');
    publisherCtrl = TextEditingController(text: _book?.publisher ?? '');
    yearCtrl = TextEditingController(
        text: _book?.year == null ? '' : '${_book!.year}');
    descCtrl = TextEditingController(text: _book?.description ?? '');
    notesCtrl = TextEditingController(text: _book?.notes ?? '');
    categoryCtrl = TextEditingController(text: _book?.category ?? '');
    categoryFocus = FocusNode();

    // 已读页数变化 → 自动补开始 / 完成时间（见 [_onCurrentPagesChanged]）
    currentPagesCtrl.addListener(_onCurrentPagesChanged);
  }

  /// 编辑目标 id；null = 新增模式
  final String? bookId;

  /// 新增模式（无 id）→ 保存走 `addBook`，且无删除入口
  bool get isAddMode => bookId == null;

  /// 编辑模式下按 id 查找失败（书已被删除等）
  final bool notFound;

  /// 新增模式下随机生成的封面色相（仅生成一次，避免 rebuild 变色）
  final double addCoverHue;

  final Book? _book;

  /// 编辑模式的原书（新增模式为 null）；保存时作为 `copyWith` 的基底
  Book? get book => _book;

  // ---------- 表单字段 ----------

  late final TextEditingController titleCtrl;
  late final TextEditingController authorCtrl;
  late final TextEditingController isbnCtrl;
  late final TextEditingController pagesCtrl;

  /// 已读页数（替代旧滑杆；0 = 想读，填满总页数 = 完成）
  late final TextEditingController currentPagesCtrl;

  late final TextEditingController publisherCtrl;
  late final TextEditingController yearCtrl;
  late final TextEditingController descCtrl;
  late final TextEditingController notesCtrl;
  late final TextEditingController categoryCtrl;
  late final FocusNode categoryFocus;

  /// 网络封面地址输入（粘贴图片链接）
  final TextEditingController coverUrlCtrl = TextEditingController();

  double rating;

  /// 添加时间：编辑 = 原书值；新增 = 当前时刻（开始阅读时间的默认值来源）
  late final DateTime createdAt;

  /// 开始阅读时间（想读状态隐藏字段，进入在读时默认为 [createdAt]）
  DateTime? startedAt;

  /// 阅读完成时间（填满总页数自动填今天；回退需保存时二次确认）
  DateTime? finishedAt;

  /// 从相册选中、尚未复制进 images/ 的封面（保存时 attach）
  File? pendingCoverFile;

  /// 封面是否被用户动过（选图/填 URL/移除）——决定保存时沿用原图还是覆盖
  bool coverEdited = false;

  /// 数据溯源标记（保存时写入 `Book.source`，如 `'googleBooks:xyz'`）
  String? sourceTag;

  /// 防止双击重复提交
  bool saving = false;

  // ---------- 页数与状态推导 ----------

  /// 表单当前生效的总页数（输入非法时回退：编辑 = 原书值，新增 = 300）
  int get effectiveTotalPages =>
      max(1, int.tryParse(pagesCtrl.text.trim()) ?? _book?.totalPages ?? 300);

  /// 表单当前生效的已读页数（非法输入按 0；超出总页数截断——填满即完成）
  int get effectiveCurrentPages {
    final v = int.tryParse(currentPagesCtrl.text.trim()) ?? 0;
    return v.clamp(0, effectiveTotalPages);
  }

  BookStatus get statusFromProgress {
    if (effectiveCurrentPages >= effectiveTotalPages) {
      return BookStatus.finished;
    }
    if (effectiveCurrentPages > 0) return BookStatus.reading;
    return BookStatus.planToRead;
  }

  /// 进度是否已拉满（填满总页数 = 完成）
  bool get progressAtLeastFull => effectiveCurrentPages >= effectiveTotalPages;

  /// ISBN 输入归一（空串 → null）
  String? get isbnValue {
    final v = isbnCtrl.text.trim();
    return v.isEmpty ? null : v;
  }

  /// 阅读时间区块是否应展示（想读且无任何记录时整块隐藏）
  bool get hasReadingTimeRecord =>
      effectiveCurrentPages > 0 || startedAt != null || finishedAt != null;

  /// 已读页数变化的自动联动：
  /// - >0 且无开始记录 → 默认开始时间 = 添加时间
  /// - 填满总页数且无完成记录 → 自动补今天
  void _onCurrentPagesChanged() {
    final cur = effectiveCurrentPages;
    final total = effectiveTotalPages;
    DateTime? start = startedAt;
    DateTime? fin = finishedAt;
    if (cur > 0 && start == null) start = dateOnly(createdAt);
    if (total > 0 && cur >= total && fin == null) {
      fin = dateOnly(DateTime.now());
    }
    if (start != startedAt || fin != finishedAt) {
      startedAt = start;
      finishedAt = fin;
      notifyListeners();
    }
  }

  /// 分类联想候选：预设分类 ∪ 书库实际使用过的分类（去重，预设在前）
  List<String> categoryOptions(List<String> usedCategories) =>
      <String>{...kBookCategories, ...usedCategories}.toList(growable: false);

  // ---------- 封面预览 ----------

  /// 封面预览输入：编辑态未改动 → 原图；动过后 → URL 文本（网络）或空（占位）；
  /// 选中本地图时由 `MediaCover.pendingFile` 优先展示，[media] 归位 null。
  MediaRef? get previewCoverMedia {
    if (coverEdited) {
      final url = coverUrlCtrl.text.trim();
      return url.isEmpty ? null : MediaRef.network(url);
    }
    return _book?.cover;
  }

  /// 封面（含色相 / emoji）的展示参数，供 State 构建头部卡片
  double get effectiveCoverHue => _book?.coverHue ?? addCoverHue;

  // ---------- 校验 ----------

  /// 保存前的表单校验；返回错误文案（null = 通过）。
  ///
  /// 与「二次确认」分开：这里只做纯判断，弹窗与提示文案由 State 负责。
  String? validate() {
    if (titleCtrl.text.trim().isEmpty || authorCtrl.text.trim().isEmpty) {
      return '书名与作者不能为空';
    }
    final finished = finishedAt;
    final started = startedAt;
    if (finished != null && started != null && finished.isBefore(started)) {
      return '完成时间不能早于开始时间';
    }
    return null;
  }

  /// 已读页数未填满但仍留有完成记录 → 保存前需二次确认（对应旧滑杆回退确认）
  bool get needsFinishedClearConfirm =>
      effectiveCurrentPages < effectiveTotalPages && finishedAt != null;

  /// 选择一个完成日期：进度拉满 + 写入完成时间（读完即完成）
  void applyFinishedDate(DateTime pick) {
    finishedAt = dateOnly(pick);
    currentPagesCtrl.text = '$effectiveTotalPages';
  }

  /// 选择一个开始阅读日期
  void applyStartedDate(DateTime pick) => startedAt = dateOnly(pick);

  // ---------- 保存组装 ----------

  /// 组装待保存的 `Book`（含封面落盘）。
  ///
  /// 返回 null = 无法组装（编辑模式下原书已不存在）。新增模式生成新实体，
  /// 编辑模式在原书基础上 `copyWith`。写库与导航由 State 负责。
  Future<Book?> composeBook(LibraryProvider provider) async {
    final original = _book;
    if (!isAddMode && original == null) return null;

    final title = titleCtrl.text.trim();
    final author = authorCtrl.text.trim();
    final started = startedAt;
    final totalPages = effectiveTotalPages;
    final currentPage = effectiveCurrentPages;

    final ratingValue = rating > 0 ? rating : null;
    final category = _nullable(categoryCtrl.text);
    final publisher = _nullable(publisherCtrl.text);
    final year = int.tryParse(yearCtrl.text.trim());
    final description = _nullable(descCtrl.text);
    final notes = _nullable(notesCtrl.text);

    // 新增/编辑统一先在保存时刻确定 id（新增 = 微秒时间戳），供封面复制落盘
    final id = isAddMode
        ? 'b_${DateTime.now().microsecondsSinceEpoch}'
        : original!.id;
    final cover = await _resolveDraftCover(provider, id);

    if (isAddMode) {
      return Book(
        id: id,
        title: title,
        author: author,
        totalPages: totalPages,
        currentPage: currentPage,
        status: statusFromProgress,
        coverHue: addCoverHue,
        cover: cover,
        rating: ratingValue,
        category: category,
        publisher: publisher,
        year: year,
        description: description,
        notes: notes,
        isbn: isbnValue,
        source: sourceTag,
        createdAt: createdAt,
        startedAt: started,
        finishedAt: _completeWithDefault(started, finishedAt),
      );
    }
    return original!.copyWith(
      title: title,
      author: author,
      totalPages: totalPages,
      currentPage: currentPage,
      status: statusFromProgress,
      cover: cover,
      rating: ratingValue,
      category: category,
      // publisher/year 为 sentinel 参数：显式传值（含 null 清空）均生效
      publisher: publisher,
      year: year,
      description: description,
      notes: notes,
      isbn: isbnValue,
      // 未重新检索时保留原溯源标记（copyWith 传 null 会清字段）
      source: sourceTag ?? original.source,
      startedAt: started,
      finishedAt: _completeWithDefault(started, finishedAt),
    );
  }

  /// 完成时间兜底：进度 100% 却无完成记录时补今天（如旧数据/直接填满场景）。
  /// 传参会覆盖 copyWith 保留语义——因此仅在有值或需补全时返回非 null。
  DateTime? _completeWithDefault(DateTime? started, DateTime? finished) {
    if (effectiveCurrentPages < effectiveTotalPages) return finished;
    return finished ?? dateOnly(DateTime.now());
  }

  /// 计算保存时的封面引用：
  /// - 选中了本地图 → 先复制进 images/<id><ext> 再返回 local 引用；
  /// - 没动过封面 → 沿用原图（含 null）；
  /// - 动过：填了 URL → **先缓存到本地**（成功 = local+remote 双引用，
  ///   展示优先读本地、离线回退 URL；缓存失败 = 纯网络引用）；URL 空 → 移除。
  Future<MediaRef?> _resolveDraftCover(LibraryProvider provider, String id) async {
    final pending = pendingCoverFile;
    if (pending != null) {
      final rel = await provider.attachImage(pending, id);
      return rel == null ? null : MediaRef.local(rel);
    }
    if (!coverEdited) return _book?.cover;
    final url = coverUrlCtrl.text.trim();
    if (url.isEmpty) return null;
    final cached = await provider.cacheRemoteImage(url, 'book_cover');
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
    authorCtrl.dispose();
    isbnCtrl.dispose();
    pagesCtrl.dispose();
    currentPagesCtrl.dispose();
    publisherCtrl.dispose();
    yearCtrl.dispose();
    categoryCtrl.dispose();
    categoryFocus.dispose();
    descCtrl.dispose();
    notesCtrl.dispose();
    coverUrlCtrl.dispose();
    super.dispose();
  }
}
