import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/data_source.dart';
import '../data_source_interface.dart';
import '../http_retry.dart';

/// OpenLibrary 书籍数据源（免 API Key，开箱即用，无 429 限制）
///
/// - 搜索：`{api}/search.json?q={query}&limit={limit}`
/// - 封面：`{coverBase}/{cover_id}-M.jpg`（支持 L/M/S）
/// - 作品：`{api}/works/{olid}.json`（作者/主题/描述等）
/// - 版本：`{api}/works/{olid}/editions.json`（出版社/ISBN/页数）
///
/// **两级数据的分工**（对应 OpenLibrary 的数据模型，也是本类串联两个接口的原因）：
/// - *work（作品）*只有跨版本共享的信息：主题、简介、封面；
/// - *edition（版本）*才有出版社、ISBN、页数、出版日期。
///
/// 搜索接口返回作品级字段（含 `subject` 主题词），
/// 所以 [getBookDetail] = 作品详情（主题 / 简介）+ 版本详情（出版社 / ISBN / 页数）。
///
/// **接口地址可替换**（`baseUrl` / `coverBaseUrl`，均选填）：国内直连
/// openlibrary.org 常需数秒甚至超时，用户可自建反代（Cloudflare Worker /
/// 轻量 VPS）后把地址填进来；不填即走官方地址，行为与加配置前完全一致。
class OpenLibraryDataSource implements BookDataSource {
  OpenLibraryDataSource({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// 版本列表取前 N 条挑选（只解析最完整的那条，不逐条深挖）
  static const int _editionScanLimit = 10;

  /// 搜索接口对 `q` 的最小长度要求（新版后端，实测 <3 直接 400）。
  /// 中文两字书名（《三体》《活着》《围城》…）因此会被整条拒绝。
  static const int _minQueryLength = 3;

  /// 搜索接口显式声明返回字段：避免 `subject` 等大字段被默认响应省略
  static const String _searchFields =
      'key,title,author_name,publisher,first_publish_year,publish_year,'
      'isbn,number_of_pages_median,cover_i,subject';

  @override
  DataSourceType get type => DataSourceType.openLibrary;

  /// 全部选填——不填即官方地址，所以 OpenLibrary 仍是「开箱即用」的源
  /// （`isConfigured` 只校验 required 项，这里没有任何 required）。
  @override
  List<ConfigField> get configFields => const [
        ConfigField(
          key: 'baseUrl',
          label: 'API 地址',
          hint: '选填，默认 https://openlibrary.org；国内可填自建反代',
        ),
        ConfigField(
          key: 'coverBaseUrl',
          label: '封面地址',
          hint: '选填，默认 https://covers.openlibrary.org/b/id',
        ),
      ];

  /// 拉取 JSON（网络失败 / 非 200 / 解析失败统一抛 [DataSourceException]）
  Future<Map<String, dynamic>> _getJson(
    String url,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse(url).replace(queryParameters: query);
    late final http.Response resp;
    try {
      // 分层超时 + 一次重试：冷连接首跳 6s 快速失败，重试跳 9s 命中复用连接
      // （见 http_retry.dart）。最坏耗时与原来的单次 15s 基本持平。
      resp = await getWithRetry(_client, uri);
    } on TimeoutException {
      throw const DataSourceException('请求超时，请检查网络连接后重试');
    } on Exception catch (_) {
      throw const DataSourceException('网络请求失败，请检查网络连接');
    }
    if (resp.statusCode != 200) {
      throw DataSourceException(_httpError(resp));
    }
    try {
      // 显式按 UTF-8 解码：`resp.body` 在响应头缺 charset 时按 latin1 解，
      // 会把中文书名解成乱码（latin1 对任意字节都有映射，不会抛异常）。
      final root =
          jsonDecode(utf8.decode(resp.bodyBytes, allowMalformed: true));
      if (root is! Map<String, dynamic>) {
        throw const DataSourceException('OpenLibrary 返回格式异常');
      }
      return root;
    } on FormatException {
      throw const DataSourceException('OpenLibrary 返回内容解析失败');
    }
  }

  /// 非 200 响应的用户可见文案。
  ///
  /// OpenLibrary 新版后端用 FastAPI 风格报错
  /// （`{"detail":[{"msg":"Query too short, …, must be at least 3 characters"}]}`），
  /// 直接把「HTTP 400」抛给用户完全看不出原因，这里取出原文并做中文归一。
  static String _httpError(http.Response resp) {
    final msg = _detailMessage(resp.bodyBytes);
    if (msg == null) return 'OpenLibrary 接口异常（HTTP ${resp.statusCode}）';
    if (msg.toLowerCase().contains('too short')) {
      return '搜索词太短：OpenLibrary 要求至少 $_minQueryLength 个字符，'
          '请补充作者名或改用 ISBN 检索';
    }
    return 'OpenLibrary 接口异常：$msg';
  }

  /// 从错误响应体提取可读信息
  /// （`detail[].msg` / `detail` 字符串 / `message` / `error`）；
  /// 非 JSON 错误页（如网关 HTML）返回 null，调用方回退通用文案。
  static String? _detailMessage(List<int> bodyBytes) {
    Object? root;
    try {
      root = jsonDecode(utf8.decode(bodyBytes, allowMalformed: true));
    } on FormatException {
      return null;
    }
    if (root is! Map<String, dynamic>) return null;
    final detail = root['detail'];
    if (detail is List) {
      for (final entry in detail) {
        final msg = switch (entry) {
          String s => s.trim(),
          Map m when m['msg'] is String => (m['msg'] as String).trim(),
          _ => '',
        };
        if (msg.isNotEmpty) return msg;
      }
    } else if (detail is String && detail.trim().isNotEmpty) {
      return detail.trim();
    }
    for (final key in const ['message', 'error']) {
      final value = root[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  @override
  Future<bool> testConnection({
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async {
    final json = await _getJson(
      _Endpoints.of(config).searchUrl,
      {'q': 'flutter', 'limit': '1'},
    );
    return json.containsKey('docs');
  }

  @override
  Future<List<BookSearchResult>> searchBooks(
    String query, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
    int limit = 10,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final ep = _Endpoints.of(config);

    // 短查询兜底：新版搜索后端要求 `q` ≥ [_minQueryLength] 个字符，
    // 两字中文书名 / 作者名会被整条拒绝（HTTP 400）。
    // 改用字段查询绕过长度校验：先按书名（用户多数在搜书名），
    // 书名无命中再按作者（莫言 / 余华 / 韩寒 这类两字作者名）。
    if (q.length < _minQueryLength) {
      final byTitle = await _query(ep, {'title': q}, limit: limit);
      if (byTitle.isNotEmpty) return byTitle;
      return _query(ep, {'author': q}, limit: limit);
    }
    return _query(ep, {'q': q}, limit: limit);
  }

  /// 单次搜索请求（统一补 `limit` 与 `fields`，解析 `docs`）
  Future<List<BookSearchResult>> _query(
    _Endpoints ep,
    Map<String, String> params, {
    required int limit,
  }) async {
    final json = await _getJson(ep.searchUrl, {
      ...params,
      'limit': '$limit',
      'fields': _searchFields,
    });
    final docs = json['docs'] as List? ?? const [];
    return docs
        .whereType<Map<String, dynamic>>()
        .take(limit)
        .map((doc) => _parseDoc(doc, ep))
        .toList();
  }

  /// 搜索结果条目解析（OpenLibrary docs 结构）
  BookSearchResult _parseDoc(Map<String, dynamic> doc, _Endpoints ep) {
    final title = _cleanTitle((doc['title'] ?? '') as String);
    final authors = _expandAuthors(
      (doc['author_name'] as List? ?? const []).whereType<String>(),
    );
    final publisher = _pickPublisher(
      (doc['publisher'] as List? ?? const []).whereType<String>(),
    );
    final year = (doc['first_publish_year'] as int?) ??
        (doc['publish_year'] as List? ?? const []).cast<int>().firstOrNull;
    final isbns =
        (doc['isbn'] as List? ?? const []).whereType<String>().toList();
    final isbn13 = isbns.firstWhere(
      (isbn) => isbn.length == 13,
      orElse: () => isbns.isNotEmpty ? isbns.first : '',
    );
    final coverId = doc['cover_i'] as int?;
    final coverUrl = coverId != null ? ep.coverUrl(coverId) : null;
    // 主题词（作品级）：搜索接口直接返回，无需等详情即可回填分类
    final subjects = _cleanSubjects(
      (doc['subject'] as List? ?? const []).whereType<String>(),
    );

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
    final ep = _Endpoints.of(config);
    final json = await _getJson(ep.workUrl(workKey), {});
    final work = _parseWork(json, externalId, ep);

    // 版本级补全：work 详情不含出版社 / ISBN / 页数，只有 edition 才有。
    // 失败不影响作品级字段（主题 / 简介）→ 静默降级。
    final edition =
        await _fetchBestEdition(ep, workKey, fallbackTitle: work.title);
    return edition == null ? work : work.mergeWith(edition);
  }

  /// 解析作品详情（`works/{id}.json`）
  BookSearchResult _parseWork(
    Map<String, dynamic> json,
    String externalId,
    _Endpoints ep,
  ) {
    final title = _cleanTitle((json['title'] ?? '') as String);
    // OpenLibrary work 详情 authors 结构：{"author": {"key": "/authors/OL...W", "name": "..."}}
    // 取 name（不是 key！）—— 否则会回填出 "OL12111758A" 这种 id
    final authors = _expandAuthors(
      (json['authors'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((a) => a['author']?['name'] as String?)
          .whereType<String>(),
    );
    final subjects = _cleanSubjects(
      (json['subjects'] as List? ?? const []).whereType<String>(),
    );
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
          ? ep.coverUrl((coverId.first as num).toInt())
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
    _Endpoints ep,
    String workKey, {
    required String fallbackTitle,
  }) async {
    final Map<String, dynamic> json;
    try {
      json = await _getJson(ep.editionsUrl(workKey), {
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
        (e['publishers'] as List? ?? const []).whereType<String>();
    final isbn13 =
        (e['isbn_13'] as List? ?? const []).whereType<String>().toList();
    final isbn10 =
        (e['isbn_10'] as List? ?? const []).whereType<String>().toList();
    return BookSearchResult(
      externalId: '', // mergeWith 取 base 的 externalId，此处不消费
      title: fallbackTitle,
      authors: const [],
      publisher: _pickPublisher(publishers),
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

  // ---------- 字段清洗（P2 数据质量）----------

  /// 书名清洗：剥掉尾部「（精）/ (平装)」这类装帧后缀。
  ///
  /// 电商与版权页常把装帧写进书名（`百年孤独(精)`）。留着既冗余，又会破坏
  /// 多源聚合的书名去重键——`百年孤独` 与 `百年孤独(精)` 会被当成两本。
  static String _cleanTitle(String raw) {
    var s = raw.trim();
    // 最多剥 3 层，兼容 `百年孤独(精)[精装]` 这类叠加写法
    for (var i = 0; i < 3; i++) {
      final stripped = s.replaceFirst(_titleSuffixRe, '').trim();
      if (stripped == s) break;
      s = stripped;
    }
    return s;
  }

  /// 作者字段展开 + 清洗：一个字段里可能塞了多个作者或机构。
  ///
  /// 中文条目常见三类脏数据：
  /// - `加西亚·马尔克斯 著` → 去掉后缀词；
  /// - `新华书店北美网 加西亚·马尔克斯 著` → 再剥掉以「网 / 书店 / 出版社」
  ///   结尾的**前导片段**（电商抓取把店铺名一起塞进了作者字段）；
  /// - `刘慈欣、某某工作室出品` → 按「，、；」拆成多段，整段是机构的丢弃。
  ///
  /// 只按中文标点切分：英文作者是 `Last, First`，按半角逗号切会把名字切碎。
  static List<String> _expandAuthors(Iterable<String> raw) {
    final out = <String>[];
    for (final value in raw) {
      for (final segment in value.split(_authorSeparatorRe)) {
        final cleaned = _cleanAuthor(segment);
        if (cleaned.isEmpty) continue;
        if (_orgSuffixRe.hasMatch(cleaned)) continue; // 出品 / 公司 / 书店 = 机构
        out.add(cleaned);
      }
    }
    return out;
  }

  /// 单个作者片段清洗：去后缀词 + 剥前导店铺名
  static String _cleanAuthor(String raw) {
    var s = raw.trim();
    s = s.replaceAll(_authorSuffixRe, '').trim();
    final parts = s.split(_spaceRe);
    while (parts.length > 1 && _shopTokenRe.hasMatch(parts.first)) {
      parts.removeAt(0);
    }
    return parts.join(' ').trim();
  }

  /// 主题词清洗：过滤 subject 里的非分类噪音并去重。
  ///
  /// 实测噪音形态：控制号 `(OCoLC)123456`、层级词 `Fiction: general`、
  /// 数字化平台占位词 `Protected DAISY` / `Large type books`。这些直接回填
  /// 会把「分类」字段冲成一行读不懂的串，也让中文分类映射更容易被带偏。
  static List<String> _cleanSubjects(Iterable<String> raw) {
    final out = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      final s = value.trim();
      if (!_isUsefulSubject(s)) continue;
      if (!seen.add(s.toLowerCase())) continue;
      out.add(s);
    }
    return out;
  }

  static bool _isUsefulSubject(String s) {
    if (s.length < 2) return false;
    if (_subjectNoiseRe.hasMatch(s)) return false;
    return !_subjectStopWords.contains(s.toLowerCase());
  }

  /// 出版社挑选：优先含中日韩文字的条目。
  ///
  /// 同一本书的 `publisher(s)` 数组常中英混排（`南海出版公司` +
  /// `Nanhai Publishing`）。中文书优先取中文条目，回填后可读性更好，
  /// 也让「出版社」筛选收敛到同一套字符串上。
  static String? _pickPublisher(Iterable<String> raw) {
    final cleaned =
        raw.map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (cleaned.isEmpty) return null;
    for (final p in cleaned) {
      if (_cjkRe.hasMatch(p)) return p;
    }
    return cleaned.first;
  }

  /// 装帧后缀：`(精)` / `（平装）` / `[精装]`（长词优先，避免 `平装` 被 `平` 抢）
  static final RegExp _titleSuffixRe = RegExp(
    r'\s*[（(\[][^）)\]]{0,6}(?:精装|平装|简装|软精装|精|平)[）)\]]\s*$',
  );

  static final RegExp _authorSuffixRe =
      RegExp(r'\s*(?:著|编著|主编|编译|译|校注|校订|校)\s*$');
  static final RegExp _spaceRe = RegExp(r'\s+');
  static final RegExp _shopTokenRe = RegExp(r'(网|书店|出版社|图书|商城|专营店)$');

  /// 作者分隔符：只认中文标点（半角逗号是英文 `Last, First` 的一部分）
  static final RegExp _authorSeparatorRe = RegExp(r'[，、；;]');

  /// 机构后缀：整段命中即丢弃（`XX出品` / `XX文化公司` / `XX书店`）
  static final RegExp _orgSuffixRe =
      RegExp(r'(出品|公司|书店|出版社|传媒|文化|影视|集团|工作室|网)$');

  /// 主题词噪音：层级词（含 `:` `=`）、OCLC 控制号
  static final RegExp _subjectNoiseRe =
      RegExp(r'[:=]|\(OCoLC', caseSensitive: false);

  /// 主题词泛词黑名单（低频信息、但在 subject 数组里高频出现）
  static const Set<String> _subjectStopWords = {
    'general',
    'accessible book',
    'protected daisy',
    'in library',
    'large type books',
    'overdrive',
    'internet archive',
    'openlibrary',
    'electronic books',
    'juvenile literature',
    'miscellanea',
  };

  /// 中日韩文字（判断出版社条目是否为中文本）
  static final RegExp _cjkRe =
      RegExp(r'[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]');

  /// 释放底层 HTTP 客户端连接池
  void close() => _client.close();
}

/// OpenLibrary 接口地址解析（官方地址 / 用户自建镜像）
///
/// 每次请求前从 `config` 现算而不是缓存进字段——数据源实现有
/// 「不持有可变状态」的契约，同一个实例会被不同配置的数据源复用
/// （测试里尤其明显），字段缓存会把 A 源的镜像地址泄漏给 B 源。
class _Endpoints {
  const _Endpoints({required this.apiBase, required this.coverBase});

  static const String defaultApiBase = 'https://openlibrary.org';
  static const String defaultCoverBase = 'https://covers.openlibrary.org/b/id';

  /// 去尾斜杠后的 API 前缀
  final String apiBase;

  /// 去尾斜杠后的封面前缀
  final String coverBase;

  factory _Endpoints.of(Map<String, dynamic> config) => _Endpoints(
        apiBase: _resolve(config['baseUrl'], defaultApiBase),
        coverBase: _resolve(config['coverBaseUrl'], defaultCoverBase),
      );

  /// 空 / 全空白 → 回落默认地址；否则去尾斜杠
  /// （用户从浏览器复制地址时常带尾斜杠，拼出来会变成 `//search.json`）
  static String _resolve(Object? raw, String fallback) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return fallback;
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  String get searchUrl => '$apiBase/search.json';

  String workUrl(String workKey) => '$apiBase/works/$workKey.json';

  String editionsUrl(String workKey) => '$apiBase/works/$workKey/editions.json';

  String coverUrl(int coverId) => '$coverBase/$coverId-M.jpg';
}
