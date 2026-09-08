import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/data_source.dart';
import '../data_source_interface.dart';

/// Google Books 书籍数据源（免 API Key，开箱即用）
///
/// Books API v1 公开端点：搜索 `/volumes?q=`、详情 `/volumes/{id}`、
/// 连通性 `/volumes?q=flutter&maxResults=1`。无必填配置；
/// 可选 `country` 参数（部分网络环境缺失时接口返回 403）。
class GoogleBooksDataSource implements BookDataSource {
  GoogleBooksDataSource({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const String _baseUrl = 'https://www.googleapis.com/books/v1';

  /// 请求超时（H3：弱网下不设超时会让 UI 永久转圈，无任何恢复路径）
  static const Duration _kTimeout = Duration(seconds: 15);
  static Never _onTimeout() =>
      throw const DataSourceException('请求超时，请检查网络连接后重试');

  @override
  DataSourceType get type => DataSourceType.googleBooks;

  @override
  List<ConfigField> get configFields => const [
        ConfigField(
          key: 'country',
          label: '国家代码',
          hint: '接口 403 时填写，如 US / CN',
        ),
      ];

  /// 拉取 JSON（网络失败 / 非 200 / 解析失败统一抛 [DataSourceException]）
  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    late final http.Response resp;
    try {
      resp = await _client
          .get(uri)
          .timeout(_kTimeout, onTimeout: _onTimeout);
    } on DataSourceException {
      rethrow;
    } on Exception catch (_) {
      throw const DataSourceException('网络请求失败，请检查网络连接');
    }
    if (resp.statusCode == 403) {
      throw const DataSourceException(
        'Google Books 拒绝访问（403），可在数据源配置中填写国家代码重试',
      );
    }
    if (resp.statusCode == 429) {
      throw const DataSourceException(
        'Google Books 请求过于频繁（HTTP 429），请稍后再试',
      );
    }
    if (resp.statusCode != 200) {
      throw DataSourceException('Google Books 接口异常（HTTP ${resp.statusCode}）');
    }
    try {
      final root = jsonDecode(resp.body);
      if (root is! Map<String, dynamic>) {
        throw const DataSourceException('Google Books 返回格式异常');
      }
      return root;
    } on FormatException {
      throw const DataSourceException('Google Books 返回内容解析失败');
    }
  }

  @override
  Future<bool> testConnection({
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async {
    final json = await _getJson('/volumes', {
      'q': 'flutter',
      'maxResults': '1',
      ..._countryQuery(config),
    });
    return json.containsKey('items') || json.containsKey('totalItems');
  }

  @override
  Future<List<BookSearchResult>> searchBooks(
    String query, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
    int limit = 10,
  }) async {
    final json = await _getJson('/volumes', {
      'q': query,
      'maxResults': '$limit',
      'printType': 'books',
      ..._countryQuery(config),
    });
    return (json['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_parseVolume)
        .toList();
  }

  /// 单卷解析（搜索与详情共用；详情多 categories 字段同样走 volumeInfo）
  BookSearchResult _parseVolume(Map<String, dynamic> item) {
    final volume = item['volumeInfo'] as Map<String, dynamic>? ?? const {};
    final title = (volume['title'] ?? '') as String;
    final authors =
        (volume['authors'] as List? ?? const []).cast<String>().toList();
    final published = volume['publishedDate'] as String?;
    final isbns = (volume['industryIdentifiers'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    // 优先 ISBN_13，退化取第一个 identifier
    final isbn13 = isbns
        .where((e) => e['type'] == 'ISBN_13')
        .map((e) => e['identifier'] as String?)
        .firstWhere((e) => e != null, orElse: () => null);
    final anyIsbn = isbns.isEmpty
        ? null
        : (isbn13 ?? isbns.first['identifier'] as String?);
    final thumbnail =
        (volume['imageLinks'] as Map<String, dynamic>?)?['thumbnail'] as String?;
    final categories =
        (volume['categories'] as List? ?? const []).cast<String>().toList();

    return BookSearchResult(
      externalId: '${item['id']}',
      title: title,
      authors: authors,
      publisher: volume['publisher'] as String?,
      year: published != null && published.length >= 4
          ? int.tryParse(published.substring(0, 4))
          : null,
      isbn: anyIsbn,
      pageCount: (volume['pageCount'] as num?)?.toInt(),
      // Google 返回的 thumbnail 可能是 http，统一升级 https（iOS ATS 要求）
      coverUrl: thumbnail?.replaceFirst('http://', 'https://'),
      rating: (volume['averageRating'] as num?)?.toDouble(),
      description: _nonEmpty(volume['description'] as String?),
      categories: categories,
    );
  }

  @override
  Future<BookSearchResult> getBookDetail(
    String externalId, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async {
    final json = await _getJson('/volumes/$externalId', {
      ..._countryQuery(config),
    });
    return _parseVolume(json);
  }

  Map<String, String> _countryQuery(Map<String, dynamic> config) {
    final country = (config['country'] as String?)?.trim();
    return (country == null || country.isEmpty)
        ? const {}
        : {'country': country};
  }

  /// 空串归 null（简介为空时 UI 不展示占位）
  String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 释放底层 HTTP 客户端连接池
  void close() => _client.close();
}
