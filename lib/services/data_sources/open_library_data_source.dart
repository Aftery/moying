import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/data_source.dart';
import '../data_source_interface.dart';

/// OpenLibrary 书籍数据源（免 API Key，开箱即用，无 429 限制）
///
/// - 搜索：`https://openlibrary.org/search.json?q={query}&limit={limit}`
/// - 封面：`https://covers.openlibrary.org/b/id/{cover_id}-M.jpg`（支持 L/M/S）
/// - 详情：`https://openlibrary.org/works/{olid}.json`（作者/出版社/描述等）
/// - 无需 API Key，无严格速率限制，适合国内网络环境
class OpenLibraryDataSource implements BookDataSource {
  OpenLibraryDataSource({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const String _searchUrl = 'https://openlibrary.org/search.json';
  static const String _coverBase = 'https://covers.openlibrary.org/b/id';
  static const String _workBase = 'https://openlibrary.org/works';

  @override
  DataSourceType get type => DataSourceType.openLibrary;

  @override
  List<ConfigField> get configFields => const [];

  /// 拉取 JSON（网络失败 / 非 200 / 解析失败统一抛 [DataSourceException]）
  Future<Map<String, dynamic>> _getJson(
    String url,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse(url).replace(queryParameters: query);
    late final http.Response resp;
    try {
      resp = await _client.get(uri);
    } on Exception catch (_) {
      throw const DataSourceException('网络请求失败，请检查网络连接');
    }
    if (resp.statusCode != 200) {
      throw DataSourceException('OpenLibrary 接口异常（HTTP ${resp.statusCode}）');
    }
    try {
      final root = jsonDecode(resp.body);
      if (root is! Map<String, dynamic>) {
        throw const DataSourceException('OpenLibrary 返回格式异常');
      }
      return root;
    } on FormatException {
      throw const DataSourceException('OpenLibrary 返回内容解析失败');
    }
  }

  @override
  Future<bool> testConnection({
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async {
    final json = await _getJson(_searchUrl, {'q': 'flutter', 'limit': '1'});
    return json.containsKey('docs');
  }

  @override
  Future<List<BookSearchResult>> searchBooks(
    String query, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
    int limit = 10,
  }) async {
    final json = await _getJson(_searchUrl, {
      'q': query,
      'limit': '$limit',
    });

    final docs = json['docs'] as List? ?? const [];
    return docs
        .whereType<Map<String, dynamic>>()
        .take(limit)
        .map(_parseDoc)
        .toList();
  }

  /// 搜索结果条目解析（OpenLibrary docs 结构）
  BookSearchResult _parseDoc(Map<String, dynamic> doc) {
    final title = (doc['title'] ?? '') as String;
    final authors =
        (doc['author_name'] as List? ?? const []).cast<String>().toList();
    final publisher =
        (doc['publisher'] as List? ?? const []).cast<String>().firstOrNull;
    final year = (doc['first_publish_year'] as int?) ??
        (doc['publish_year'] as List? ?? const []).cast<int>().firstOrNull;
    final isbns =
        (doc['isbn'] as List? ?? const []).cast<String>().toList();
    final isbn13 = isbns.firstWhere(
      (isbn) => isbn.length == 13,
      orElse: () => isbns.isNotEmpty ? isbns.first : '',
    );
    final coverId = doc['cover_i'] as int?;
    final coverUrl = coverId != null
        ? '$_coverBase/$coverId-M.jpg'
        : null;

    return BookSearchResult(
      externalId: (doc['key'] ?? doc['work_key'] ?? '') as String,
      title: title,
      authors: authors,
      publisher: publisher,
      year: year,
      isbn: isbn13.isNotEmpty ? isbn13 : (isbns.isNotEmpty ? isbns.first : null),
      pageCount: (doc['number_of_pages_median'] as num?)?.toInt(),
      coverUrl: coverUrl,
      rating: null, // OpenLibrary 搜索不返回评分
      description: null, // 搜索不返回描述，需详情接口补全
    );
  }

  /// 取作品详情（作者 / 出版社 / 描述补全；非作品 ID 返回 null）。
  /// 注意：BookDataSource 接口未声明此方法（书籍回填只消费搜索结果），
  /// 保留为 OpenLibrary 额外能力，供后续「详情补全」迭代调用。
  Future<BookSearchResult?> getBookDetail(
    String externalId, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async {
    // externalId 形如 /works/OL123W 或 /books/OL456M
    final workKey = externalId.split('/').last;
    if (!workKey.startsWith('OL') || !workKey.endsWith('W')) {
      return null; // 非作品 ID，无法取详情
    }
    final json = await _getJson('$_workBase/$workKey.json', {});

    final title = (json['title'] ?? '') as String;
    final authors = (json['authors'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((a) => (a['author']?['key'] as String?))
        .whereType<String>()
        .map((k) => k.split('/').last)
        .toList();
    final publisher = (json['subjects'] as List? ?? const [])
        .cast<String>()
        .firstOrNull;
    final yearStr = (json['first_publish_date'] as String?);
    final coverId = json['covers'] as List<dynamic>?;

    return BookSearchResult(
      externalId: externalId,
      title: title,
      authors: authors,
      publisher: publisher,
      year: yearStr != null && yearStr.length >= 4 ? int.tryParse(yearStr.substring(0, 4)) : null,
      isbn: null,
      pageCount: null,
      coverUrl: coverId != null && coverId.isNotEmpty
          ? '$_coverBase/${coverId.first}-M.jpg'
          : null,
      rating: null,
      description: _nonEmpty(json['description'] as String? ??
          (json['description'] as Map<String, dynamic>?)?['value'] as String?),
    );
  }

  String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 释放底层 HTTP 客户端连接池
  void close() => _client.close();
}