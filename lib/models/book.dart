import 'media_ref.dart';

/// 书籍阅读状态
enum BookStatus {
  /// 在读
  reading('在读'),

  /// 已完成
  finished('已完成'),

  /// 想读
  planToRead('想读');

  const BookStatus(this.label);

  /// 中文展示名
  final String label;
}

/// 可选的图书分类（列表筛选与编辑页下拉共用同一数据源）
///
/// 新增分类只需在此追加，UI 的「分类筛选」与「编辑页 Category」自动同步。
const List<String> kBookCategories = [
  '科幻',
  '奇幻',
  '历史',
  '反乌托邦',
  '魔幻现实主义',
  '经典',
  '悬疑',
  '传记',
  '文学',
];

/// 书籍记录模型
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.totalPages,
    required this.createdAt,
    DateTime? updatedAt,
    this.currentPage = 0,
    this.status = BookStatus.planToRead,
    this.coverHue = 250,
    this.rating,
    this.year,
    this.emoji,
    this.category,
    this.description,
    this.notes,
    this.startedAt,
    this.finishedAt,
    this.cover,
    this.isbn,
    this.source,
  }) : updatedAt = updatedAt ?? createdAt;

  /// 唯一标识
  final String id;

  /// 书名
  final String title;

  /// 作者
  final String author;

  /// 总页数
  final int totalPages;

  /// 添加时间（开始阅读时间的默认值来源）
  final DateTime createdAt;

  /// 最后修改时间（WebDAV 记录级 LWW 合并的时间戳基准；新增即创建时间）
  final DateTime updatedAt;

  /// 开始阅读时间（可为空：尚未开始阅读）
  final DateTime? startedAt;

  /// 阅读完成时间（可为空：尚未读完）
  final DateTime? finishedAt;

  /// 当前读到第几页
  final int currentPage;

  /// 阅读状态
  final BookStatus status;

  /// 占位封面主色相（0-360，用于生成渐变占位图，避免依赖网络图片）
  final double coverHue;

  /// 评分（0-5，可为空）
  final double? rating;

  /// 出版年份
  final int? year;

  /// 占位封面 emoji
  final String? emoji;

  /// 图书分类（来自 [kBookCategories]）
  final String? category;

  /// 内容简介（这本书讲什么，供详情页展示）
  final String? description;

  /// 阅读感悟 / 书评
  final String? notes;

  /// 封面图引用（可空：无图时 UI 用 coverHue + emoji 渐变占位）
  final MediaRef? cover;

  /// ISBN（ISBN-13 / ISBN-10，快速检索回填与手工录入均可）
  final String? isbn;

  /// 数据溯源标记（可空：P6 网络补全落地后记录来源与外部 id，如 googleBooksId）
  final String? source;

  /// 阅读进度 0.0 - 1.0
  double get progress =>
      totalPages <= 0 ? 0.0 : (currentPage / totalPages).clamp(0.0, 1.0);

  /// 进度百分比（整数展示用）
  int get progressPercent => (progress * 100).round();

  /// 阅读历时天数（开始与完成同天按 1 天计；两者缺一返回 0）
  int get readingDays {
    final start = startedAt;
    final finish = finishedAt;
    if (start == null || finish == null) return 0;
    // 归一化到日再求差，避免「当天开始次日凌晨完成」这类时刻差少算 1 天
    final s = DateTime(start.year, start.month, start.day);
    final f = DateTime(finish.year, finish.month, finish.day);
    return f.difference(s).inDays + 1;
  }

  /// 复制并替换部分字段（编辑页保存时构造新实例）
  ///
  /// 省略参数表示保留原值；`startedAt` / `finishedAt` 显式传 `null` 可清空。
  Book copyWith({
    String? title,
    String? author,
    int? totalPages,
    int? currentPage,
    BookStatus? status,
    double? coverHue,
    double? rating,
    int? year,
    String? emoji,
    String? category,
    String? description,
    String? notes,
    Object? startedAt = _unset,
    Object? finishedAt = _unset,
    Object? cover = _unset,
    Object? isbn = _unset,
    Object? source = _unset,
    Object? updatedAt = _unset,
  }) {
    return Book(
      id: id,
      title: title ?? this.title,
      author: author ?? this.author,
      totalPages: totalPages ?? this.totalPages,
      currentPage: currentPage ?? this.currentPage,
      status: status ?? this.status,
      coverHue: coverHue ?? this.coverHue,
      rating: rating ?? this.rating,
      year: year ?? this.year,
      emoji: emoji ?? this.emoji,
      category: category ?? this.category,
      description: description ?? this.description,
      notes: notes ?? this.notes,
      createdAt: createdAt,
      startedAt: _take(startedAt, this.startedAt),
      finishedAt: _take(finishedAt, this.finishedAt),
      cover: _take(cover, this.cover),
      isbn: _take(isbn, this.isbn),
      source: _take(source, this.source),
      updatedAt: _take(updatedAt, this.updatedAt),
    );
  }

  /// sentinel：区分「省略（保留原值）」与「显式置 null（清空）」
  static const Object _unset = Object();

  /// 取参：省略保留原值，显式传 null(或值) 则采用
  static T? _take<T>(Object? param, T? current) =>
      identical(param, _unset) ? current : param as T?;

  // ==================== 序列化 ====================
  //
  // 约定：必填字段总写；可空字段 null 省略（文件紧凑、diff 干净）；
  // 枚举存 name；DateTime 存本地时间 ISO8601（parse 无时区后缀即本地，round-trip 一致）。

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'totalPages': totalPages,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'currentPage': currentPage,
        'status': status.name,
        'coverHue': coverHue,
        if (rating != null) 'rating': rating,
        if (year != null) 'year': year,
        if (emoji != null) 'emoji': emoji,
        if (category != null) 'category': category,
        if (description != null) 'description': description,
        if (notes != null) 'notes': notes,
        if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
        if (cover != null) 'cover': cover!.toJson(),
        if (isbn != null) 'isbn': isbn,
        if (source != null) 'source': source,
      };

  factory Book.fromJson(Map<String, dynamic> json) => Book(
        id: json['id'] as String,
        title: json['title'] as String,
        author: json['author'] as String,
        totalPages: (json['totalPages'] as num).toInt(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: json['updatedAt'] == null
            ? DateTime.parse(json['createdAt'] as String) // 旧数据兜底
            : DateTime.parse(json['updatedAt'] as String),
        currentPage: (json['currentPage'] as num?)?.toInt() ?? 0,
        status: json['status'] == null
            ? BookStatus.planToRead
            : BookStatus.values.byName(json['status'] as String),
        coverHue: (json['coverHue'] as num?)?.toDouble() ?? 250,
        rating: (json['rating'] as num?)?.toDouble(),
        year: (json['year'] as num?)?.toInt(),
        emoji: json['emoji'] as String?,
        category: json['category'] as String?,
        description: json['description'] as String?,
        notes: json['notes'] as String?,
        startedAt: json['startedAt'] == null
            ? null
            : DateTime.parse(json['startedAt'] as String),
        finishedAt: json['finishedAt'] == null
            ? null
            : DateTime.parse(json['finishedAt'] as String),
        cover: json['cover'] == null
            ? null
            : MediaRef.fromJson(json['cover'] as Map<String, dynamic>),
        isbn: json['isbn'] as String?,
        source: json['source'] as String?,
      );

  // ==================== 值相等（round-trip 测试与数据保持断言用）====================

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Book &&
          other.id == id &&
          other.title == title &&
          other.author == author &&
          other.totalPages == totalPages &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.currentPage == currentPage &&
          other.status == status &&
          other.coverHue == coverHue &&
          other.rating == rating &&
          other.year == year &&
          other.emoji == emoji &&
          other.category == category &&
          other.description == description &&
          other.notes == notes &&
          other.startedAt == startedAt &&
          other.finishedAt == finishedAt &&
          other.cover == cover &&
          other.isbn == isbn &&
          other.source == source;

  @override
  int get hashCode => Object.hash(id, title, author, totalPages, createdAt,
      updatedAt, currentPage, status, coverHue, rating, year, emoji, category,
      description, notes, startedAt, finishedAt, cover, isbn, source);
}
