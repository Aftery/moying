/// 自定义数据源（用户自建代理 / 私有服务，智能解析返回数据）
///
/// 核心思路：**不强制用户遵循固定协议**，而是启发式解析返回 JSON——
/// 从任意嵌套结构中递归找到「数据列表」（数组），再按常见字段别名
/// （title/name/书名、cover/image/封面…）提取可用信息；缺什么字段
/// 就留空，绝不因个别字段缺失丢弃整条结果。
///
/// 接口约定（宽松）：
/// - 搜索：依次尝试 `{base}/search?q=`、`{base}?q=`、`{base}/api/search?q=`；
/// - 鉴权：填了 API Key → 同时带 `Authorization: Bearer` 与 `?key=` 参数；
/// - 测试连接：可达 + 有效 JSON + 存在类列表 + 首条含可识别字段，
///   不满足时给出具体中文提示（"自定义 API 返回格式不正确：…"）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/data_source.dart';
import '../data_source_interface.dart';

/// 智能响应解析器（书籍/影视共用）
class SmartResponseParser {
  SmartResponseParser._();

  /// 字段别名表（按优先级，首个命中者生效）
  static const Map<String, List<String>> _aliases = {
    'title': [
      'title', 'name', 'book_name', 'movie_title', 'film_name',
      'display_name', 'label', '书名', '名称', '片名',
    ],
    'cover': [
      'cover', 'cover_url', 'image', 'image_url', 'poster', 'poster_url',
      'pic', 'thumbnail', 'thumb', 'photo', 'avatar', 'url', '封面', '图片',
    ],
    'author': ['author', 'authors', 'author_name', 'writer', 'creator', '作者'],
    'publisher': ['publisher', 'press', 'publish_house', '出版社'],
    'year': ['year', 'publish_year', 'pub_year', 'date', '出版年份', '年份'],
    'isbn': ['isbn', 'isbn13', 'isbn10'],
    'pageCount': ['page_count', 'pages', 'number_of_pages', '页数'],
    'description': [
      'description', 'desc', 'summary', 'intro', 'introduction', 'abstract',
      'overview', 'content', '简介', '内容简介', '剧情简介',
    ],
    'rating': ['rating', 'score', 'rate', 'star', '评分'],
    'director': ['director', 'directed_by', 'director_name', '导演'],
    'genres': ['genres', 'genre', 'categories', 'category', 'tags', '类型', '标签'],
    'runtime': ['runtime', 'duration', 'length', '片长', '时长'],
    'originalTitle': ['original_title', 'original_name', 'originaltitle', '原名'],
    'externalId': ['id', 'key', '_id', 'uid', 'uuid', 'oid', 'object_id'],
  };

  /// 常见「列表容器」键名（递归兜底前的优先探测）
  static const List<String> _listKeys = [
    'data', 'results', 'items', 'list', 'records', 'docs', 'books',
    'movies', 'entries', 'content', 'rows', 'subjects', 'search',
  ];

  /// 递归查找第一个「元素为对象」且非空的数组。
  /// 返回 null = 未找到可用列表。
  static List<Map<String, dynamic>>? findFirstList(dynamic json) {
    if (json is List) {
      final items =
          json.whereType<Map<String, dynamic>>().toList(growable: false);
      if (items.isNotEmpty) return items;
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    for (final key in _listKeys) {
      final v = json[key];
      if (v is List) {
        final items =
            v.whereType<Map<String, dynamic>>().toList(growable: false);
        if (items.isNotEmpty) return items;
      }
    }
    for (final v in json.values) {
      final found = findFirstList(v);
      if (found != null) return found;
    }
    return null;
  }

  /// 按 [aliases] 优先级从对象中提取字符串字段
  static String? extractString(Map<String, dynamic> obj, List<String> aliases) {
    for (final key in aliases) {
      final v = obj[key];
      if (v == null) continue;
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is num) return '$v';
    }
    return null;
  }

  /// 提取字符串列表（数组或分隔串皆可）
  static List<String> extractList(Map<String, dynamic> obj, List<String> aliases) {
    for (final key in aliases) {
      final v = obj[key];
      if (v is List) {
        final out = v
            .map((e) => e is String ? e.trim() : (e is Map ? _mapToLabel(e) : null))
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .toList();
        if (out.isNotEmpty) return out;
      } else if (v is String && v.trim().isNotEmpty) {
        // "科幻,动作" / "科幻、动作" / "科幻|动作" 单串按分隔符拆
        return v
            .split(RegExp(r'[,，、/|]'))
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }
    return const [];
  }

  static String? _mapToLabel(Map<dynamic, dynamic> m) {
    for (final k in ['name', 'title', 'label', 'value', 'text']) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  /// 提取整数
  static int? extractInt(Map<String, dynamic> obj, List<String> aliases) {
    for (final key in aliases) {
      final v = obj[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) {
        final match = RegExp(r'\d{3,4}').firstMatch(v);
        if (match != null) return int.tryParse(match.group(0)!);
      }
    }
    return null;
  }

  /// 提取浮点（0-5 评分，超出按 10 分制折算）
  static double? extractRating(Map<String, dynamic> obj) {
    final v = extractDouble(obj, _aliases['rating']!);
    if (v == null) return null;
    if (v > 5 && v <= 10) return v / 2;
    if (v > 0 && v <= 5) return v;
    return null;
  }

  static double? extractDouble(Map<String, dynamic> obj, List<String> aliases) {
    for (final key in aliases) {
      final v = obj[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.trim());
    }
    return null;
  }

  /// 从单条对象解析书籍结果（title 无法识别 → null）
  static BookSearchResult? parseBookItem(Map<String, dynamic> obj) {
    final title = extractString(obj, _aliases['title']!);
    if (title == null || title.isEmpty) return null;
    return BookSearchResult(
      externalId: extractString(obj, _aliases['externalId']!) ??
          'c${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      authors: extractList(obj, _aliases['author']!),
      publisher: extractString(obj, _aliases['publisher']!),
      year: extractInt(obj, _aliases['year']!),
      isbn: extractString(obj, _aliases['isbn']!),
      pageCount: extractInt(obj, _aliases['pageCount']!),
      coverUrl: extractString(obj, _aliases['cover']!),
      rating: extractRating(obj),
      description: extractString(obj, _aliases['description']!),
      // genres 别名表同时覆盖 category / categories / tags / 类型 / 标签；
      // 此前漏传 → 自定义源分类恒空（即使 API 返回了）
      categories: extractList(obj, _aliases['genres']!),
    );
  }

  /// 从单条对象解析影视结果（title 无法识别 → null）
  static MovieSearchResult? parseMovieItem(Map<String, dynamic> obj) {
    final title = extractString(obj, _aliases['title']!);
    if (title == null || title.isEmpty) return null;
    return MovieSearchResult(
      externalId: extractString(obj, _aliases['externalId']!) ??
          'c${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      originalTitle: extractString(obj, _aliases['originalTitle']!),
      year: extractInt(obj, _aliases['year']!),
      director: extractString(obj, _aliases['director']!),
      genres: extractList(obj, _aliases['genres']!),
      posterUrl: extractString(obj, _aliases['cover']!),
      rating: extractRating(obj),
      overview: extractString(obj, _aliases['description']!),
      runtimeMinutes: extractInt(obj, _aliases['runtime']!),
    );
  }

  /// 测试连接用的结构校验：返回错误提示（null = 通过）
  static String? validateStructure(dynamic json) {
    if (json is! Map<String, dynamic> && json is! List) {
      return '自定义 API 返回格式不正确：返回内容不是有效的 JSON 对象或数组';
    }
    final list = findFirstList(json);
    if (list == null) {
      return '自定义 API 返回格式不正确：未找到数据列表\n\n'
          '期望返回形如：\n'
          '[{"title":"…","cover":"…"}, …]\n'
          '或 {"data":[{"title":"…"}, …]}、{"results":[…]}';
    }
    final first = list.first;
    final hasTitle =
        extractString(first, _aliases['title']!)?.isNotEmpty ?? false;
    if (!hasTitle) {
      return '自定义 API 返回格式不正确：数据缺少可识别的标题字段\n\n'
          '建议每条数据包含以下字段之一：\n'
          'title / name / book_name / 片名 / 书名';
    }
    return null;
  }
}

/// 自定义数据源公共基类（网络请求 + 智能解析）
abstract class _CustomDataSourceBase {
  _CustomDataSourceBase({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _kTimeout = Duration(seconds: 15);
  static Never _onTimeout() =>
      throw const DataSourceException('请求超时，请检查网络或自定义 API 地址');

  /// 搜索路径模板（'' = 直接拼在 base 后；其余以 / 开头）。
  /// 实际请求按顺序尝试，`?q={query}&limit={limit}` 由基类统一拼接。
  List<String> get searchPathTemplates;

  /// 搜索参数附加（影视可能带语言参数，书籍无）
  Map<String, String> extraParams() => const {};

  String _baseUrlOf(Map<String, dynamic> config) {
    final raw = (config['baseUrl'] as String? ?? '').trim();
    if (raw.isEmpty) {
      throw const DataSourceException('请先填写 Base URL');
    }
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  Map<String, String> _headersOf(Map<String, String> credentials) {
    final apiKey = credentials['apiKey']?.trim();
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'MoYing/0.8 (custom data source)',
    };
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    return headers;
  }

  /// 请求 URL：带 key 时附加 `?key=`（部分自建服务只认 query 传参）
  Uri _buildUri(String url, String? apiKey) {
    final uri = Uri.parse(url);
    if (apiKey == null || apiKey.isEmpty) return uri;
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      'key': apiKey,
      ...extraParams(),
    });
  }

  /// 发起 GET 并解析 JSON（网络失败 / 非 200 / 解析失败统一抛异常）
  Future<dynamic> _getJson(
    String url, {
    required Map<String, String> credentials,
  }) async {
    final apiKey = credentials['apiKey']?.trim();
    final uri = _buildUri(url, apiKey);
    late final http.Response resp;
    try {
      resp = await _client
          .get(uri, headers: _headersOf(credentials))
          .timeout(_kTimeout, onTimeout: _onTimeout);
    } on DataSourceException {
      rethrow;
    } on Exception catch (_) {
      throw const DataSourceException('网络请求失败，请检查网络与自定义 API 地址');
    }
    if (resp.statusCode != 200) {
      throw DataSourceException('自定义 API 响应异常（HTTP ${resp.statusCode}）');
    }
    try {
      return jsonDecode(resp.body);
    } on FormatException {
      throw const DataSourceException('自定义 API 返回格式不正确：返回内容不是有效 JSON');
    }
  }

  /// 依次尝试多个搜索 URL 模式，首个能解析出结果列表的生效。
  /// [fromJsonItem] 把单条 JSON 对象转为结果模型。
  Future<List<T>> _search<T>(
    String query, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
    required int limit,
    required T? Function(Map<String, dynamic>) fromJsonItem,
    required String notFoundMessage,
  }) async {
    final base = _baseUrlOf(config);
    final qs =
        '?q=${Uri.encodeQueryComponent(query)}&limit=$limit';
    for (final template in searchPathTemplates) {
      try {
        final json = await _getJson(
          '$base$template$qs',
          credentials: credentials,
        );
        final list = SmartResponseParser.findFirstList(json);
        if (list == null) continue;
        final results = list
            .map(fromJsonItem)
            .whereType<T>()
            .take(limit)
            .toList();
        if (results.isNotEmpty) return results;
        // 列表存在但一条都解析不出 → 继续尝试下一路径模板
      } on DataSourceException {
        continue; // 下一路径
      }
    }
    throw DataSourceException(notFoundMessage);
  }

  /// 释放底层 HTTP 连接池
  void close() => _client.close();
}

/// 自定义书籍数据源
class CustomBookDataSource extends _CustomDataSourceBase
    implements BookDataSource {
  CustomBookDataSource({super.client});

  @override
  DataSourceType get type => DataSourceType.customBook;

  @override
  List<ConfigField> get configFields => const [
        ConfigField(
          key: 'baseUrl',
          label: 'Base URL',
          hint: 'https://api.example.com/v1',
          required: true,
        ),
        ConfigField(
          key: 'apiKey',
          label: 'API Key / Access Token',
          hint: '选填，走 Bearer 头与 ?key= 参数',
          isSecret: true,
        ),
        ConfigField(
          key: 'detailUrlTemplate',
          label: '详情接口模板',
          hint: '选填，如 https://api.example.com/book/{id}；不填则跳过详情补全',
        ),
      ];

  @override
  List<String> get searchPathTemplates => const [
        '/search',
        '',
        '/api/search',
        '/v1/search',
        '/books/search',
      ];

  @override
  Future<bool> testConnection({
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async {
    final base = _baseUrlOf(config);
    final json = await _getJson(
      '$base${searchPathTemplates.first}?q=test&limit=1',
      credentials: credentials,
    );
    final error = SmartResponseParser.validateStructure(json);
    if (error != null) throw DataSourceException(error);
    return true;
  }

  @override
  Future<List<BookSearchResult>> searchBooks(
    String query, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
    int limit = 10,
  }) {
    return _search<BookSearchResult>(
      query,
      config: config,
      credentials: credentials,
      limit: limit,
      fromJsonItem: SmartResponseParser.parseBookItem,
      notFoundMessage: '自定义 API 返回格式不正确：未能从返回数据中解析出书籍信息',
    );
  }

  @override
  Future<BookSearchResult> getBookDetail(
    String externalId, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async {
    final template = (config['detailUrlTemplate'] as String? ?? '').trim();
    if (template.isEmpty) {
      throw const DataSourceException(
        '该数据源未配置「详情接口模板」，简介 / 页数等字段需由详情接口补全',
      );
    }
    final url = template.replaceAll('{id}', Uri.encodeComponent(externalId));
    final json = await _getJson(url, credentials: credentials);
    final list = SmartResponseParser.findFirstList(json);
    if (list == null || list.isEmpty) {
      throw const DataSourceException('自定义 API 详情返回格式不正确：未找到数据');
    }
    final item = SmartResponseParser.parseBookItem(list.first);
    if (item == null) {
      throw const DataSourceException('自定义 API 详情返回格式不正确：无法解析条目');
    }
    return item;
  }
}

/// 自定义影视数据源
class CustomMovieDataSource extends _CustomDataSourceBase
    implements MovieDataSource {
  CustomMovieDataSource({super.client});

  @override
  DataSourceType get type => DataSourceType.customMovie;

  @override
  List<ConfigField> get configFields => const [
        ConfigField(
          key: 'baseUrl',
          label: 'Base URL',
          hint: 'https://api.example.com/v1',
          required: true,
        ),
        ConfigField(
          key: 'apiKey',
          label: 'API Key / Access Token',
          hint: '选填，走 Bearer 头与 ?key= 参数',
          isSecret: true,
        ),
      ];

  @override
  List<String> get searchPathTemplates => const [
        '/search',
        '',
        '/api/search',
        '/v1/search',
        '/movies/search',
      ];

  @override
  Future<bool> testConnection({
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async {
    final base = _baseUrlOf(config);
    final json = await _getJson(
      '$base${searchPathTemplates.first}?q=test&limit=1',
      credentials: credentials,
    );
    final error = SmartResponseParser.validateStructure(json);
    if (error != null) throw DataSourceException(error);
    return true;
  }

  @override
  Future<List<MovieSearchResult>> searchMovies(
    String query, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
    int limit = 10,
  }) {
    return _search<MovieSearchResult>(
      query,
      config: config,
      credentials: credentials,
      limit: limit,
      fromJsonItem: SmartResponseParser.parseMovieItem,
      notFoundMessage: '自定义 API 返回格式不正确：未能从返回数据中解析出影视信息',
    );
  }

  /// 自定义源暂不支持详情接口（搜索结果已含启发式提取的全部字段）
  @override
  Future<MovieSearchResult> getMovieDetail(
    String externalId, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) {
    throw const DataSourceException('自定义 API 暂不支持详情查询');
  }
}
