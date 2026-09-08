import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/data_source.dart';
import '../data_source_interface.dart';

/// OpenLibrary 书籍数据源（免 API Key，开箱即用，无 429 限制）
///
/// - 搜索：`https://openlibrary.org/search.json?q={query}&limit={limit}`
/// - 封面：`https://covers.openlibrary.org/b/id/{cover_id}-M.jpg`（支持 L/M/S）
/// - 作品：`https://openlibrary.org/works/{olid}.json`（作者/主题/描述等）
/// - 版本：`https://openlibrary.org/works/{olid}/editions.json`（出版社/ISBN/页数）
/// - 无需 API Key，无严格速率限制，适合国内网络环境
///
/// **两级数据的分工**（对应 OpenLibrary 的数据模型，也是本类串联两个接口的原因）：
/// - *work（作品）*只有跨版本共享的信息：主题、简介、封面；
/// - *edition（版本）*才有出版社、ISBN、页数、出版日期。
///
/// 搜索接口返回作品级字段（含 `subject` 主题词），
/// 所以 [getBookDetail] = 作品详情（主题 / 简介）+ 版本详情（出版社 / ISBN / 页数）。
class OpenLibraryDataSource implements BookDataSource {
  OpenLibraryDataSource({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const String _searchUrl = 'https://openlibrary.org/search.json';
  static const String _coverBase = 'https://covers.openlibrary.org/b/id';
  static const String _workBase = 'https://openlibrary.org/works';

  /// 请求超时（H3：弱网下不设超时会让 UI 永久转圈，无任何恢复路径）
  static const Duration _kTimeout = Duration(seconds: 15);
  static Never _onTimeout() =>
      throw const DataSourceException('请求超时，请检查网络连接后重试');

  /// 搜索接口显式声明返回字段：避免 `subject` 等大字段被默认响应省略
  static const String _searchFields =
      'key,title,author_name,publisher,first_publish_year,publish_year,'
      'isbn,number_of_pages_median,cover_i,subject';

  /// 版本列表取前 N 条挑选（只解析最完整的那条，不逐条深挖）
  static const int _editionScanLimit = 10;

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
      resp = await _client.get(uri).timeout(_kTimeout, onTimeout: _onTimeout);
    } on DataSourceException {
      rethrow;
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
      'fields': _searchFields,
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
    final authors = (doc['author_name'] as List? ?? const [])
        .whereType<String>()
        .map(_cleanAuthor)
        .where((a) => a.isNotEmpty)
        .toList();
    final publisher =
        (doc['publisher'] as List? ?? const []).whereType<String>().firstOrNull;
    final year = (doc['first_publish_year'] as int?) ??
        (doc['publish_year'] as List? ?? const []).cast<int>().firstOrNull;
    final isbns =
        (doc['isbn'] as List? ?? const []).whereType<String>().toList();
    final isbn13 = isbns.firstWhere(
      (isbn) => isbn.length == 13,
      orElse: () => isbns.isNotEmpty ? isbns.first : '',
    );
    final coverId = doc['cover_i'] as int?;
    final coverUrl = coverId != null ? '$_coverBase/$coverId-M.jpg' : null;
    // 主题词（作品级）：搜索接口直接返回，无需等详情即可回填分类
    final subjects =
        (doc['subject'] as List? ?? const []).whereType<String>().toList();

    return BookSearchResult(
      externalId: (doc['key'] ?? doc['work_key'] ?? '') as String,
      title: title,
      authors: authors,
      publisher: _nonEmpty(publisher),
      year: year,
      isbn:
          isbn13.isNotEmpty ? isbn13 : (isbns.isNotEmpty ? isbns.first : null),
      pageCount: (doc['number_of_pages_median'] as num?)?.toInt(),
      coverUrl: coverUrl,
      rating: null, // OpenLibrary 搜索不返回评分
      description: null, // 搜索不返回描述，需详情接口补全
      categories: subjects,
    );
  }

  /// 取作品详情（主题 / 简介补全）+ 版本详情（出版社 / ISBN / 页数补全）；
  /// 仅 OL 开头的作品 ID 可取详情，其余格式抛 [DataSourceException]
  @override
  Future<BookSearchResult> getBookDetail(
    String externalId, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async {
    // externalId 形如 /works/OL123W 或 /books/OL456M
    final workKey = externalId.split('/').last;
    if (!workKey.startsWith('OL') || !workKey.endsWith('W')) {
      throw const DataSourceException('OpenLibrary 仅支持 OL…W 格式作品 ID 查询详情');
    }
    final json = await _getJson('$_workBase/$workKey.json', {});
    final work = _parseWork(json, externalId);

    // 版本级补全：work 详情不含出版社 / ISBN / 页数，只有 edition 才有。
    // 失败不影响作品级字段（主题 / 简介）→ 静默降级。
    final edition = await _fetchBestEdition(workKey, fallbackTitle: work.title);
    return edition == null ? work : work.mergeWith(edition);
  }

  /// 解析作品详情（`works/{id}.json`）
  BookSearchResult _parseWork(Map<String, dynamic> json, String externalId) {
    final title = (json['title'] ?? '') as String;
    // OpenLibrary work 详情 authors 结构：{"author": {"key": "/authors/OL...W", "name": "..."}}
    // 取 name（不是 key！）—— 否则会回填出 "OL12111758A" 这种 id
    final authors = (json['authors'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((a) => (a['author']?['name'] as String?))
        .whereType<String>()
        .map(_cleanAuthor)
        .where((a) => a.isNotEmpty)
        .toList();
    final subjects =
        (json['subjects'] as List? ?? const []).whereType<String>().toList();
    final yearStr = (json['first_publish_date'] as String?);
    final coverId = json['covers'] as List<dynamic>?;

    return BookSearchResult(
      externalId: externalId,
      title: title,
      authors: authors,
      categories: subjects,
      year: _yearOf(yearStr),
      isbn: null,
      pageCount: null,
      coverUrl: coverId != null && coverId.isNotEmpty
          ? '$_coverBase/${coverId.first}-M.jpg'
          : null,
      rating: null,
      description: _description(json['description']),
    );
  }

  /// 取该作品「字段最完整」的一个版本。
  ///
  /// OpenLibrary 的 editions 没有「首选版本」概念，这里按
  /// （有页数 + 有 ISBN + 有出版社）计分挑最高的一条。
  /// 列表请求失败返回 null——作品级字段不该被版本接口拖累。
  Future<BookSearchResult?> _fetchBestEdition(
    String workKey, {
    required String fallbackTitle,
  }) async {
    final Map<String, dynamic> json;
    try {
      json = await _getJson('$_workBase/$workKey/editions.json', {
        'limit': '$_editionScanLimit',
      });
    } on DataSourceException {
      return null;
    }
    final entries = (json['entries'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    if (entries.isEmpty) return null;

    Map<String, dynamic>? best;
    var bestScore = -1;
    for (final e in entries) {
      final score = _editionScore(e);
      if (score > bestScore) {
        bestScore = score;
        best = e;
      }
      if (bestScore == 3) break; // 三项齐全，无需再扫
    }
    if (best == null) return null;
    return _parseEdition(best, fallbackTitle: fallbackTitle);
  }

  /// 版本完整度评分：页数 / ISBN / 出版社各 1 分
  int _editionScore(Map<String, dynamic> e) =>
      (e['number_of_pages'] is num ? 1 : 0) +
      (((e['isbn_13'] as List?)?.isNotEmpty ?? false) ? 1 : 0) +
      (((e['publishers'] as List?)?.isNotEmpty ?? false) ? 1 : 0);

  /// 解析版本详情（`editions` 单条）。
  ///
  /// 只填出版社 / ISBN / 页数三项——其余留空，
  /// 由 [BookSearchResult.mergeWith] 保留作品级的值（主题 / 简介 / 封面 / 年份）。
  /// [fallbackTitle] 用于避免版本标题（常带副标题）覆盖作品标题。
  BookSearchResult _parseEdition(
    Map<String, dynamic> e, {
    required String fallbackTitle,
  }) {
    final publishers =
        (e['publishers'] as List? ?? const []).whereType<String>().toList();
    final isbn13 =
        (e['isbn_13'] as List? ?? const []).whereType<String>().toList();
    final isbn10 =
        (e['isbn_10'] as List? ?? const []).whereType<String>().toList();
    return BookSearchResult(
      externalId: '', // mergeWith 取 base 的 externalId，此处不消费
      title: fallbackTitle,
      authors: const [],
      publisher: _nonEmpty(publishers.isEmpty ? null : publishers.first),
      isbn: isbn13.isNotEmpty
          ? isbn13.first
          : (isbn10.isNotEmpty ? isbn10.first : null),
      pageCount: (e['number_of_pages'] as num?)?.toInt(),
    );
  }

  /// 从 "2017" / "March 2017" / "2017-05-01" 取年份
  int? _yearOf(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'\d{4}').firstMatch(raw);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  String? _description(Object? raw) {
    final value = switch (raw) {
      String text => text,
      Map<String, dynamic> map =>
        map['value'] is String ? map['value'] as String : null,
      _ => null,
    };
    return _nonEmpty(value);
  }

  String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// 作者名清洗：去掉「著 / 编著 / 译」等后缀，并剥掉开头的店铺名。
  ///
  /// 中文条目常见两种脏数据：
  /// - `加西亚·马尔克斯 著` → 去掉后缀词；
  /// - `新华书店北美网 加西亚·马尔克斯 著` → 再剥掉以「网 / 书店 / 出版社」
  ///   结尾的前导片段（电商抓取把店铺名一起塞进了作者字段）。
  ///
  /// 英文作者名不含这类店铺片段，不会被误伤：只有命中店铺后缀才剥离。
  static String _cleanAuthor(String raw) {
    var s = raw.trim();
    s = s.replaceAll(_authorSuffixRe, '').trim();
    final parts = s.split(_spaceRe);
    while (parts.length > 1 && _shopTokenRe.hasMatch(parts.first)) {
      parts.removeAt(0);
    }
    return parts.join(' ').trim();
  }

  static final RegExp _authorSuffixRe =
      RegExp(r'\s*(?:著|编著|主编|编译|译|校注|校订|校)\s*$');
  static final RegExp _spaceRe = RegExp(r'\s+');
  static final RegExp _shopTokenRe = RegExp(r'(网|书店|出版社|图书|商城|专营店)$');

  /// 释放底层 HTTP 客户端连接池
  void close() => _client.close();
}
