import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/data_source.dart';
import '../data_source_interface.dart';
import '../http_retry.dart';

/// Google Books 书籍数据源（免 API Key，开箱即用）
///
/// Books API v1 公开端点：搜索 `/volumes?q=`、详情 `/volumes/{id}`、
/// 连通性 `/volumes?q=flutter&maxResults=1`。无必填配置。
///
/// 两个**选填**项：
/// - `country`：部分网络环境缺失时接口返回 403，填 US / CN 可解；
/// - `baseUrl`：国内直连 `googleapis.com` 常不可达，可填自建反代地址。
class GoogleBooksDataSource implements BookDataSource {
  GoogleBooksDataSource({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const String _defaultBaseUrl = 'https://www.googleapis.com/books/v1';

  @override
  DataSourceType get type => DataSourceType.googleBooks;

  @override
  List<ConfigField> get configFields => const [
        ConfigField(
          key: 'country',
          label: '国家代码',
          hint: '接口 403 时填写，如 US / CN',
        ),
        ConfigField(
          key: 'baseUrl',
          label: 'API 地址',
          hint: '选填，默认 https://www.googleapis.com/books/v1（国内可填自建反代）',
        ),
      ];

  /// 接口前缀（去尾斜杠）。空 / 未配置 → 官方地址。
  ///
  /// 浏览器地址栏复制来的地址常带尾斜杠，不去掉会拼成 `/volumes//volumes`。
  static String _baseUrlOf(Map<String, dynamic> config) {
    final raw = config['baseUrl']?.toString().trim() ?? '';
    if (raw.isEmpty) return _defaultBaseUrl;
    return raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  }

  /// 拉取 JSON（网络失败 / 非 200 / 解析失败统一抛 [DataSourceException]）
  Future<Map<String, dynamic>> _getJson(
    String base,
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse('$base$path').replace(queryParameters: query);
    late final http.Response resp;
    try {
      // 分层超时 + 一次重试（见 http_retry.dart）：首跳 6s，重试跳 9s，
      // 最坏耗时与原来的单次 15s 基本持平
      resp = await getWithRetry(_client, uri);
    } on TimeoutException {
      throw const DataSourceException('请求超时，请检查网络连接后重试');
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
      final root = jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
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
    final json = await _getJson(_baseUrlOf(config), '/volumes', {
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
    final json = await _getJson(_baseUrlOf(config), '/volumes', {
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
    final json = await _getJson(_baseUrlOf(config), '/volumes/$externalId', {
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
