/// 联网信息补全 —— 数据源模型层
///
/// 配置持久化于 `data_sources.json`（非敏感：名称 / 类型 / base 配置 / 默认标记 /
/// 连接状态）；API Key / Token 等敏感凭据单独存系统安全存储
/// （`SecureStorageService`，key 前缀 `ds_credential_`），与 WebDAV 密码同一策略：
/// 即使配置文件被导出查看也拿不到凭据。
library;

/// 数据源类别
enum DataSourceCategory {
  /// 影视（TMDB / Bangumi / 自建代理…）
  movie('影视数据源'),

  /// 书籍（Google Books / 豆瓣 / OpenBD…）
  book('书籍数据源');

  const DataSourceCategory(this.label);

  /// 中文展示名（管理页区块标题）
  final String label;
}

/// 数据源类型（决定用哪个实现类处理搜索 / 详情 / 测试连接）
enum DataSourceType {
  /// TMDB —— The Movie Database（影视；需 API Key，免费申请）
  tmdb('TMDB (The Movie Database)', DataSourceCategory.movie),

  /// Google Books（书籍；免 API Key 开箱即用，国内访问不稳定）
  googleBooks('Google Books', DataSourceCategory.book),

  /// OpenLibrary（书籍；免 API Key，无速率限制，适合国内）
  openLibrary('Open Library', DataSourceCategory.book),

  /// 豆瓣（书籍；官方 API 已关闭，需自建代理，后续迭代开放）
  douban('豆瓣 Douban', DataSourceCategory.book),

  /// 自定义影视 API（用户自建代理 / 私有服务；智能解析返回数据）
  customMovie('自定义影视 API', DataSourceCategory.movie),

  /// 自定义书籍 API（用户自建代理 / 私有服务；智能解析返回数据）
  customBook('自定义书籍 API', DataSourceCategory.book);

  const DataSourceType(this.displayName, this.category);

  /// 内置数据源展示名
  final String displayName;

  /// 所属类别
  final DataSourceCategory category;

  /// 是否为自定义类型（智能解析源，UI 添加入口直接弹配置表单）
  bool get isCustom => this == customMovie || this == customBook;
}

/// 数据源连接状态（管理页状态标签）
enum DataSourceStatus {
  /// 已配置且测试连接通过
  connected('已连接'),

  /// 必填配置未填全（如 TMDB 缺 API Key）
  notConfigured('未配置'),

  /// 已配置但从未测试 / 被手动停用
  inactive('未激活'),

  /// 最近一次测试连接超时
  timeout('连接超时'),

  /// 最近一次测试连接失败（网络错误 / 凭据无效 / 接口异常）
  error('连接失败');

  const DataSourceStatus(this.label);

  /// 中文展示名（状态徽标）
  final String label;
}

/// 数据源配置（持久化形态；敏感凭据不在 [config] 内）
class DataSourceConfig {
  const DataSourceConfig({
    required this.id,
    required this.type,
    required this.name,
    this.isDefault = false,
    this.config = const {},
    this.status = DataSourceStatus.notConfigured,
    this.lastTestedAt,
    this.summary,
  });

  /// 唯一标识（内置源用 `builtin_<type>`，用户添加用 uuid）
  final String id;

  /// 数据源类型
  final DataSourceType type;

  /// 显示名（用户可改，默认取 [DataSourceType.displayName]）
  final String name;

  /// 是否为所属类别的默认源（同类别有且仅有一个 true）
  final bool isDefault;

  /// 非敏感配置项（如 baseUrl / 语言 / 地区）；凭据存安全存储不在此
  final Map<String, dynamic> config;

  /// 当前连接状态
  final DataSourceStatus status;

  /// 最近一次测试连接时间（null = 从未测试）
  final DateTime? lastTestedAt;

  /// 管理页展示的配置摘要（如 "API Key: v3_8f29…a92b" / "免 API Key 免配置"）；
  /// null 时 UI 由 [status] 与类型推导兜底文案
  final String? summary;

  /// 该源所属类别
  DataSourceCategory get category => type.category;

  /// 配置摘要展示（UI 兜底：未配置 → 提示语；否则取 [summary]）
  String get displaySummary {
    if (summary != null && summary!.isNotEmpty) return summary!;
    return status == DataSourceStatus.connected ? '已就绪' : '待配置';
  }

  DataSourceConfig copyWith({
    String? name,
    bool? isDefault,
    Map<String, dynamic>? config,
    DataSourceStatus? status,
    DateTime? lastTestedAt,
    String? summary,
    bool clearSummary = false,
  }) {
    return DataSourceConfig(
      id: id,
      type: type,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      config: config ?? this.config,
      status: status ?? this.status,
      lastTestedAt: lastTestedAt ?? this.lastTestedAt,
      summary: clearSummary ? null : (summary ?? this.summary),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'isDefault': isDefault,
        'config': config,
        'status': status.name,
        if (lastTestedAt != null) 'lastTestedAt': lastTestedAt!.toIso8601String(),
        if (summary != null) 'summary': summary,
      };

  factory DataSourceConfig.fromJson(Map<String, dynamic> json) {
    final lastTested = json['lastTestedAt'];
    return DataSourceConfig(
      id: json['id'] as String,
      type: DataSourceType.values.byName(json['type'] as String),
      name: json['name'] as String? ?? '',
      isDefault: json['isDefault'] as bool? ?? false,
      config: (json['config'] as Map<String, dynamic>?) ?? const {},
      status: json['status'] == null
          ? DataSourceStatus.notConfigured
          : DataSourceStatus.values.byName(json['status'] as String),
      lastTestedAt:
          lastTested is String ? DateTime.tryParse(lastTested) : null,
      summary: json['summary'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DataSourceConfig &&
          other.id == id &&
          other.type == type &&
          other.name == name &&
          other.isDefault == isDefault &&
          other.status == status &&
          other.lastTestedAt == lastTestedAt &&
          other.summary == summary;

  @override
  int get hashCode =>
      Object.hash(id, type, name, isDefault, status, lastTestedAt, summary);
}

// ==================== 搜索结果（数据源 → 应用的统一形态）====================

/// 书籍搜索结果条目（列表态；详情补全后用于回填）
class BookSearchResult {
  const BookSearchResult({
    required this.externalId,
    required this.title,
    this.authors = const [],
    this.publisher,
    this.year,
    this.isbn,
    this.pageCount,
    this.coverUrl,
    this.rating,
    this.description,
    this.categories = const [],
  });

  /// 外部数据源内的条目 id（取详情时回传）
  final String externalId;

  /// 书名
  final String title;

  /// 作者列表（多作者 join('、') 后回填）
  final List<String> authors;

  /// 出版社
  final String? publisher;

  /// 出版年份
  final int? year;

  /// ISBN（优先 13 位）
  final String? isbn;

  /// 总页数
  final int? pageCount;

  /// 封面 URL
  final String? coverUrl;

  /// 外部评分（0-5）
  final double? rating;

  /// 内容简介
  final String? description;

  /// 分类标签（多值；书籍 [category] 是单值，回填用 [primaryCategory]）
  final List<String> categories;

  /// 第一个非空分类（编辑页单值分类字段回填用）
  String? get primaryCategory {
    for (final c in categories) {
      final t = c.trim();
      if (t.isNotEmpty) return t;
    }
    return null;
  }

  /// 作者展示串（列表 UI 用）
  String get authorsText => authors.join('、');

  /// "作者 · 出版社 (年份)" 副标题（列表 UI 用）
  String get subtitle {
    final head = <String>[
      if (authors.isNotEmpty) authorsText,
      if (publisher != null && publisher!.isNotEmpty) publisher!,
    ].join(' · ');
    if (head.isEmpty) return year == null ? '' : '($year)';
    return year == null ? head : '$head ($year)';
  }
}

/// 演员条目（电影详情回填演员区用）
class CastMember {
  const CastMember({required this.name, this.character});

  /// 演员名
  final String name;

  /// 饰演角色（可为空）
  final String? character;
}

/// 电影搜索结果条目
class MovieSearchResult {
  const MovieSearchResult({
    required this.externalId,
    required this.title,
    this.originalTitle,
    this.year,
    this.director,
    this.genres = const [],
    this.posterUrl,
    this.rating,
    this.overview,
    this.runtimeMinutes,
    this.cast = const [],
  });

  /// 外部数据源内的条目 id
  final String externalId;

  /// 中文标题
  final String title;

  /// 原始标题（外语名）
  final String? originalTitle;

  /// 上映年份
  final int? year;

  /// 导演
  final String? director;

  /// 类型标签
  final List<String> genres;

  /// 海报 URL
  final String? posterUrl;

  /// 外部评分（0-5）
  final double? rating;

  /// 剧情简介
  final String? overview;

  /// 片长（分钟）
  final int? runtimeMinutes;

  /// 主演（详情接口才返回，搜索结果常为空）
  final List<CastMember> cast;

  /// "原名 (年份)" 副标题（列表 UI 用）
  String get subtitle {
    final parts = <String>[
      if (originalTitle != null && originalTitle!.isNotEmpty) originalTitle!,
      if (year != null) '$year',
    ];
    return parts.join(' · ');
  }
}

// ==================== 数据源操作异常 ====================

/// 数据源操作异常（网络失败 / 凭据无效 / 响应解析失败等，message 面向用户展示）
class DataSourceException implements Exception {
  const DataSourceException(this.message);

  final String message;

  @override
  String toString() => 'DataSourceException: $message';
}
