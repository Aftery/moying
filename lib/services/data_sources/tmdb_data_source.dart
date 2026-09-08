import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/data_source.dart';
import '../data_source_interface.dart';

/// TMDB（The Movie Database）影视数据源
///
/// API v3：搜索 `/search/movie`、详情 `/movie/{id}?append_to_response=credits`、
/// 连通性 `/configuration`。凭据支持两种形态（自动识别）：
/// - v3 API Key（32 位十六进制）→ `api_key` query 参数；
/// - v4 Read Access Token（`eyJ` 开头的 JWT）→ `Authorization: Bearer` 头。
///
/// 语言固定 `zh-CN`（标题 / 类型 / 简介走 TMDB 中文本地化，无中文时回退原文）。
class TmdbDataSource implements MovieDataSource {
  TmdbDataSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const String _baseUrl = 'https://api.themoviedb.org/3';
  static const String _imageBase = 'https://image.tmdb.org/t/p/w500';

  /// 演员头像（credits.cast[].profile_path）—— w185 在 56~62px 圆头像下足够清晰
  static const String _profileBase = 'https://image.tmdb.org/t/p/w185';

  /// 剧照（images.backdrops[].file_path）—— w780 兼顾清晰度与流量
  static const String _backdropBase = 'https://image.tmdb.org/t/p/w780';

  /// 请求超时（H3：弱网下不设超时会让 UI 永久转圈，无任何恢复路径）
  static const Duration _kTimeout = Duration(seconds: 15);
  static Never _onTimeout() =>
      throw const DataSourceException('请求超时，请检查网络连接后重试');

  /// 内置类型 id → 中文名（搜索结果只有 genre_ids 时兜底展示）
  static const Map<int, String> _genreNames = {
    28: '动作',
    12: '冒险',
    16: '动画',
    35: '喜剧',
    80: '犯罪',
    99: '纪录',
    18: '剧情',
    10751: '家庭',
    14: '奇幻',
    36: '历史',
    27: '恐怖',
    10402: '音乐',
    9648: '悬疑',
    10749: '爱情',
    878: '科幻',
    10770: '电视电影',
    53: '惊悚',
    10752: '战争',
    37: '西部',
  };

  @override
  DataSourceType get type => DataSourceType.tmdb;

  @override
  List<ConfigField> get configFields => const [
        ConfigField(
          key: 'apiKey',
          label: 'API Key / Read Access Token',
          hint: 'themoviedb.org 免费申请',
          isSecret: true,
          required: true,
        ),
        ConfigField(
          key: 'language',
          label: '语言',
          hint: '默认 zh-CN',
        ),
      ];

  /// 组装认证（v3 key → query；v4 token → header）
  ({Map<String, String> query, Map<String, String> headers}) _auth(
    String apiKey,
  ) {
    if (apiKey.startsWith('eyJ')) {
      return (
        query: <String, String>{},
        headers: <String, String>{'Authorization': 'Bearer $apiKey'},
      );
    }
    return (query: <String, String>{'api_key': apiKey}, headers: const {});
  }

  /// 拉取 JSON（网络失败 / 非 200 / 解析失败统一抛 [DataSourceException]）
  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> query,
    Map<String, String> headers,
  ) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    late final http.Response resp;
    try {
      resp = await _client
          .get(uri, headers: headers)
          .timeout(_kTimeout, onTimeout: _onTimeout);
    } on DataSourceException {
      rethrow;
    } on Exception catch (_) {
      throw const DataSourceException('网络请求失败，请检查网络连接');
    }
    if (resp.statusCode == 401) {
      throw const DataSourceException('API Key 无效或已过期（401）');
    }
    if (resp.statusCode != 200) {
      throw DataSourceException('TMDB 接口异常（HTTP ${resp.statusCode}）');
    }
    try {
      final root = jsonDecode(resp.body);
      if (root is! Map<String, dynamic>) {
        throw const DataSourceException('TMDB 返回格式异常');
      }
      return root;
    } on FormatException {
      throw const DataSourceException('TMDB 返回内容解析失败');
    }
  }

  @override
  Future<bool> testConnection({
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async {
    final key = credentials['apiKey']?.trim() ?? '';
    if (key.isEmpty) throw const DataSourceException('请先填写 API Key');
    final auth = _auth(key);
    final json = await _getJson('/configuration', auth.query, auth.headers);
    return json.containsKey('images');
  }

  @override
  Future<List<MovieSearchResult>> searchMovies(
    String query, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
    int limit = 10,
  }) async {
    final auth = _requireAuth(credentials);
    final language = _language(config);
    final json = await _getJson(
      '/search/movie',
      {
        ...auth.query,
        'query': query,
        'language': language,
        'include_adult': 'false',
      },
      auth.headers,
    );
    return (json['results'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .take(limit)
        .map(_parseSearchItem)
        .toList();
  }

  /// 影视详情：补全导演 / 主演 / 片长 / 类型（快速检索选中后回填用）
  @override
  Future<MovieSearchResult> getMovieDetail(
    String externalId, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async {
    final auth = _requireAuth(credentials);
    final json = await _getJson(
      '/movie/$externalId',
      {
        ...auth.query,
        'language': _language(config),
        // images 与 credits 一次取回：演职员头像(profile_path) + 剧照/海报墙
        'append_to_response': 'credits,images',
        // 中文物料优先，无中文时回退无语言图（null），避免清一色外文宣传图
        'include_image_language': 'zh-CN,null',
      },
      auth.headers,
    );

    final credits = json['credits'] as Map<String, dynamic>? ?? const {};
    final crew = credits['crew'] as List? ?? const [];
    final director = crew
        .whereType<Map<String, dynamic>>()
        .firstWhere(
          (c) => c['job'] == 'Director',
          orElse: () => const {},
        )['name'] as String?;

    final castList = (credits['cast'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .take(10)
        .map((c) => CastMember(
              name: (c['name'] ?? '') as String,
              character: c['character'] as String?,
              profilePath: _imageUrl(c['profile_path'] as String?, _profileBase),
            ))
        .toList();

    final runtime = (json['runtime'] as num?)?.toInt();
    final genres = (json['genres'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((g) => g['name'] as String?)
        .whereType<String>()
        .toList();

    // 剧照 / 海报墙（images 由 append_to_response 一并返回，缺失时为空数组）
    final images = json['images'] as Map<String, dynamic>? ?? const {};
    final backdrops = _imageUrls(images['backdrops'], _backdropBase);
    final posters = _imageUrls(images['posters'], _imageBase);

    final base = _parseSearchItem(json);
    return MovieSearchResult(
      externalId: base.externalId,
      title: base.title,
      originalTitle: base.originalTitle,
      year: base.year,
      director: (director == null || director.isEmpty) ? null : director,
      genres: genres,
      posterUrl: base.posterUrl,
      rating: base.rating,
      overview: base.overview,
      runtimeMinutes: runtime,
      cast: castList,
      backdrops: backdrops,
      posters: posters,
    );
  }

  // ---------- 内部工具 ----------

  ({Map<String, String> query, Map<String, String> headers}) _requireAuth(
    Map<String, String> credentials,
  ) {
    final key = credentials['apiKey']?.trim() ?? '';
    if (key.isEmpty) {
      throw const DataSourceException('请先在数据源管理中填写 TMDB API Key');
    }
    return _auth(key);
  }

  String _language(Map<String, dynamic> config) {
    final lang = (config['language'] as String?)?.trim();
    return (lang == null || lang.isEmpty) ? 'zh-CN' : lang;
  }

  /// 单张图：相对路径 → 完整 URL（路径为空返回 null，UI 回退占位）
  String? _imageUrl(String? path, String base) =>
      (path == null || path.isEmpty) ? null : '$base$path';

  /// 图片数组 → 完整 URL 列表（限 [limit] 张，避免剧照过多撑大落盘体积）
  List<String> _imageUrls(Object? list, String base, {int limit = 20}) {
    return (list as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((e) => e['file_path'] as String?)
        .whereType<String>()
        .where((p) => p.isNotEmpty)
        .take(limit)
        .map((p) => '$base$p')
        .toList();
  }

  /// 搜索结果条目解析（credits 搜索接口不返回，详情接口再补）
  MovieSearchResult _parseSearchItem(Map<String, dynamic> item) {
    final posterPath = item['poster_path'] as String?;
    final releaseDate = item['release_date'] as String?;
    final title = (item['title'] ?? item['original_title'] ?? '') as String;
    final original = item['original_title'] as String?;
    final genreIds = (item['genre_ids'] as List? ?? const [])
        .whereType<num>()
        .map((id) => _genreNames[id.toInt()])
        .whereType<String>()
        .toList();
    final overview = (item['overview'] as String?)?.trim();
    return MovieSearchResult(
      externalId: '${item['id']}',
      title: title,
      originalTitle:
          (original == null || original.isEmpty || original == title)
              ? null
              : original,
      year: releaseDate != null && releaseDate.length >= 4
          ? int.tryParse(releaseDate.substring(0, 4))
          : null,
      genres: genreIds,
      posterUrl: posterPath == null ? null : '$_imageBase$posterPath',
      rating: (item['vote_average'] as num?) == null
          ? null
          : (item['vote_average'] as num).toDouble() / 2,
      overview: (overview == null || overview.isEmpty) ? null : overview,
    );
  }

  /// 释放底层 HTTP 客户端连接池
  void close() => _client.close();
}
