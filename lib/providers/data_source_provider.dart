import 'package:flutter/foundation.dart';

import '../models/data_source.dart';
import '../services/book_result_merger.dart';
import '../services/data_source_interface.dart';
import '../services/data_source_manager.dart';
import '../services/ttl_cache.dart';

/// 聚合适配：一次书籍检索的完整产物（结果 + 实际出力源名）
typedef _BookSearchOutcome = ({
  List<BookSearchResult> results,
  List<String> sourceNames,
});

/// 数据源状态与搜索动作（ChangeNotifier）
///
/// - 配置管理（加载 / 增删改 / 设默认 / 测试连接）走 [DataSourceManager]；
/// - 快速检索：按类别取默认源搜索，状态（进行中 / 结果 / 错误）驱动编辑页 UI；
/// - debounce 由 UI 层负责（Timer 500ms），Provider 只收最终查询词。
/// - 全局请求节流：同类型数据源（按 DataSourceType）最小间隔 3s，防止触发 API 速率限制。
/// - **缓存层**：搜索与详情各有一层 TTL 缓存（见 [TtlCache]），命中即不发网络请求。
class DataSourceProvider extends ChangeNotifier {
  /// 请求节流：每类数据源（DataSourceType）上次请求时间。
  /// 实例级即可——应用内 DataSourceProvider 为单例；static 会让测试间状态泄漏
  /// （前一个用例的记录拦截后一个用例的真实请求）。
  final Map<DataSourceType, DateTime> _lastRequestTime = {};

  /// 同类型数据源最小请求间隔（3s），防止 Google Books 等免 Key API 触发 429
  static const _minRequestInterval = Duration(seconds: 3);
  DataSourceProvider({required DataSourceManager manager}) : _manager = manager;

  final DataSourceManager _manager;
  bool _disposed = false;

  void _notifyIfAlive() {
    if (!_disposed) notifyListeners();
  }

  // ---------- 缓存 ----------

  /// 搜索结果缓存 TTL。10 分钟：用户反复调同一个词（撤销输入、来回改词）
  /// 是最高频的重复劳动，而这个窗口内书目数据几乎不会变。
  static const Duration _searchCacheTtl = Duration(minutes: 10);

  /// 详情缓存 TTL。比搜索长——单本书的元数据更稳定，而详情往往要多打
  /// 1–3 次请求（OpenLibrary 的 work + editions 就是两跳）。
  static const Duration _detailCacheTtl = Duration(minutes: 30);

  final _bookSearchCache = TtlCache<String, _BookSearchOutcome>(
    ttl: _searchCacheTtl,
    maxEntries: 60,
  );
  final _movieSearchCache = TtlCache<String, List<MovieSearchResult>>(
    ttl: _searchCacheTtl,
    maxEntries: 60,
  );
  final _bookDetailCache = TtlCache<String, BookSearchResult>(
    ttl: _detailCacheTtl,
    maxEntries: 120,
  );
  final _movieDetailCache = TtlCache<String, MovieSearchResult>(
    ttl: _detailCacheTtl,
    maxEntries: 120,
  );

  /// 缓存键拼接：源 id + 查询词 / 条目 id。
  /// 用 `\u0000` 做分隔符——它不可能出现在用户输入或数据源 id 里，
  /// 避免 `('ab','c')` 与 `('a','bc')` 撞成同一个键。
  static String _searchKey(String sourceId, String query) =>
      '$sourceId\u0000$query';

  static String _detailKey(String sourceId, String externalId) =>
      '$sourceId\u0000$externalId';

  /// 配置变动后清空缓存与节流记录。
  ///
  /// - **缓存**：换默认源、改镜像地址、增删数据源都会让已缓存的结果失去意义
  ///   （新配置下同一个词可能该有不同结果）；
  /// - **节流**：节流是为了防「打字过程中连发请求」，而改配置是用户的显式动作——
  ///   不该因为 3 秒内刚搜过一次就被判「请求过于频繁」，否则改完配置点了保存
  ///   却立刻报错，看起来像配置没生效。
  void _invalidateCaches() {
    _bookSearchCache.clear();
    _movieSearchCache.clear();
    _bookDetailCache.clear();
    _movieDetailCache.clear();
    _lastRequestTime.clear();
  }

  // ---------- 配置状态 ----------

  List<DataSourceConfig> get configs => _manager.configs;

  /// 书籍默认源（null = 未配置，编辑页隐藏快速检索）
  DataSourceConfig? get defaultBookSource =>
      _manager.defaultSourceOf(DataSourceCategory.book);

  /// 影视默认源
  DataSourceConfig? get defaultMovieSource =>
      _manager.defaultSourceOf(DataSourceCategory.movie);

  /// 是否存在至少一个该类别数据源（管理页展示用）
  List<DataSourceConfig> sourcesOf(DataSourceCategory category) =>
      _manager.configs.where((c) => c.category == category).toList();

  /// 正在测试连接的源 id（管理页行内 loading）
  String? _testingId;
  String? get testingId => _testingId;

  /// 最近一次全局错误（配置操作失败提示；搜索错误单独走 searchError）
  String? _actionError;
  String? get actionError => _actionError;

  /// 初始化：加载配置（首次启动写内置预设）
  Future<void> init() async {
    await _manager.loadConfigs();
    _notifyIfAlive();
  }

  /// 重载配置（云备份/本地导入恢复 data_sources.json 后调用）
  Future<void> reload() async {
    await _manager.loadConfigs();
    _invalidateCaches();
    _notifyIfAlive();
  }

  /// 恢复备份后检查：返回必填凭据缺失的数据源名（提示用户重填）。
  /// 同设备恢复时凭据仍在安全存储中不会命中；跨设备恢复时逐个列出。
  Future<List<String>> sourcesMissingCredentials() async {
    final missing = <String>[];
    for (final c in _manager.configs) {
      final movie = _manager.movieImplOf(c.type);
      final book = _manager.bookImplOf(c.type);
      if (movie == null && book == null) continue;

      bool ok;
      if (movie != null) {
        if (!movie.configFields.any((f) => f.required)) continue;
        final credentials = await _manager.credentialsOf(c);
        ok = movie.configFields
            .isConfigured(config: c.config, credentials: credentials);
      } else {
        if (!book!.configFields.any((f) => f.required)) continue;
        final credentials = await _manager.credentialsOf(c);
        ok = book.configFields
            .isConfigured(config: c.config, credentials: credentials);
      }
      if (!ok) missing.add(c.name);
    }
    return missing;
  }

  // ---------- 搜索状态 ----------

  bool _isSearching = false;
  bool get isSearching => _isSearching;

  /// 书籍搜索结果（null = 尚未搜索；空列表 = 无结果）
  List<BookSearchResult>? _bookResults;
  List<BookSearchResult>? get bookResults => _bookResults;

  /// 电影搜索结果
  List<MovieSearchResult>? _movieResults;
  List<MovieSearchResult>? get movieResults => _movieResults;

  /// 最近一次搜索错误（null = 无错误；空串 = 无结果不视为错误）
  String? _searchError;
  String? get searchError => _searchError;

  /// 最近一次搜索的关键词（结果区标题与去重判断用）
  String _lastQuery = '';
  String get lastQuery => _lastQuery;

  /// 单次书籍检索的结果上限（多源聚合按此截断）
  static const int _bookResultLimit = 10;

  /// 最近一次书籍搜索**实际取到结果**的源名（聚合时可能多个；空 = 未搜索）。
  /// 检索区标题据此如实标注来源，不让用户以为结果只来自默认源。
  List<String> _bookSearchSourceNames = const [];
  List<String> get bookSearchSourceNames => _bookSearchSourceNames;

  /// 聚合适配：结果与源名在同一次 execute 里产出，但源名要等 `_search`
  /// 校验过请求序号（丢弃过期响应）后才能真正落库，故经此中转。
  List<String> _pendingBookSourceNames = const [];

  /// 每个类别独立的请求序号，避免书籍与影视搜索互相丢弃结果。
  final Map<DataSourceCategory, int> _searchRequestIds = {};
  final Set<DataSourceCategory> _activeSearches = {};

  /// 统一搜索内核（M3: 抽泛型避免重复）
  ///
  /// [probeCache] 在**节流与网络之前**被调用：返回非 null 即命中缓存，
  /// 直接把结果落库并返回。缓存命中没有产生任何网络流量，不该消耗节流额度——
  /// 否则「删掉一个字再打回来」会被 3s 节流误判成刷接口而报错。
  Future<void> _search<T>({
    required String query,
    required DataSourceCategory category,
    required Future<List<T>> Function(DataSourceConfig source, String query)
        execute,
    required void Function(List<T>? results) setResults,
    List<T>? Function(String query)? probeCache,
  }) async {
    final requestId = (_searchRequestIds[category] ?? 0) + 1;
    _searchRequestIds[category] = requestId;
    _activeSearches.remove(category);
    _isSearching = _activeSearches.isNotEmpty;

    final q = query.trim();
    _lastQuery = q;
    if (q.isEmpty) {
      setResults(null);
      _searchError = null;
      _notifyIfAlive();
      return;
    }
    final source = category == DataSourceCategory.book
        ? defaultBookSource
        : defaultMovieSource;
    final catName = category == DataSourceCategory.book ? '书籍' : '影视';
    if (source == null) {
      setResults(null);
      _searchError = '尚未配置$catName数据源';
      _notifyIfAlive();
      return;
    }
    final impl = category == DataSourceCategory.book
        ? _manager.bookImplOf(source.type)
        : _manager.movieImplOf(source.type);
    if (impl == null) {
      setResults(null);
      _searchError = '暂不支持的数据源类型：${source.type.displayName}';
      _notifyIfAlive();
      return;
    }

    // 缓存探测：必须早于节流判定（见方法文档）
    if (probeCache != null) {
      final cached = probeCache(q);
      if (cached != null) {
        setResults(cached);
        _searchError = cached.isEmpty ? '' : null;
        _notifyIfAlive();
        return;
      }
    }

    // 全局节流：同类型数据源最小间隔 3s，防止触发 429
    final now = DateTime.now();
    final last = _lastRequestTime[source.type];
    if (last != null && now.difference(last) < _minRequestInterval) {
      setResults(null);
      _searchError = '请求过于频繁，请稍后再试';
      _notifyIfAlive();
      return;
    }

    _activeSearches.add(category);
    _isSearching = true;
    _searchError = null;
    _notifyIfAlive();
    try {
      final results = await execute(source, q);
      _lastRequestTime[source.type] = DateTime.now();
      if (_searchRequestIds[category] != requestId) return;
      setResults(results);
      if (results.isEmpty) _searchError = '';
    } on DataSourceException catch (e) {
      if (_searchRequestIds[category] != requestId) return;
      setResults(null);
      _searchError = e.message;
    } finally {
      if (_searchRequestIds[category] == requestId) {
        _activeSearches.remove(category);
        _isSearching = _activeSearches.isNotEmpty;
        _notifyIfAlive();
      }
    }
  }

  /// 按关键词搜索书籍（多源聚合：默认源优先，结果不足时补备用源）
  ///
  /// **结果缓存**（TTL [_searchCacheTtl]）：同一关键词在窗口内重复检索直接命中
  /// 缓存，省掉整次网络往返。缓存键含默认源 id，换默认源即自然失效；
  /// 改配置时显式清空（见 [_invalidateCaches]）。
  Future<void> searchBooks(String query) => _search<BookSearchResult>(
        query: query,
        category: DataSourceCategory.book,
        probeCache: (q) {
          final source = defaultBookSource;
          if (source == null) return null;
          final hit = _bookSearchCache.get(_searchKey(source.id, q));
          if (hit == null) return null;
          // 源名与结果一起回放，标题栏的「A 等 N 个源」才不会失真
          _pendingBookSourceNames = hit.sourceNames;
          return hit.results;
        },
        execute: (source, q) async {
          final outcome = await _searchBooksAggregated(source, q);
          _bookSearchCache.put(_searchKey(source.id, q), outcome);
          _pendingBookSourceNames = outcome.sourceNames;
          return outcome.results;
        },
        // setResults 只在请求序号未过期时被调用，源名跟着结果一起落库
        setResults: (r) {
          _bookResults = r;
          if (r != null) _bookSearchSourceNames = _pendingBookSourceNames;
        },
      );

  /// 多源聚合搜索：默认源优先，累计结果不足 [_bookResultLimit] 时按优先级
  /// 补备用源，合并后按 ISBN / 书名+作者去重，再截断到上限。
  ///
  /// 为什么是「不足才补」而不是「每次并发所有源」：国内访问 OpenLibrary /
  /// Google Books 都不快，无脑双打会让每次检索耗时翻倍；而中文书恰恰是
  /// 单源命中少的场景——按需补量既拿到覆盖率，又不动绝大多数查询的耗时。
  ///
  /// 单源失败不打断整体（只记首个异常，全无结果才抛）：一个坏源不该把
  /// 整条检索拖垮。
  Future<_BookSearchOutcome> _searchBooksAggregated(
    DataSourceConfig primary,
    String q,
  ) async {
    final batches = <List<BookSearchResult>>[];
    final sourceNames = <String>[];
    var merged = const <BookSearchResult>[];
    DataSourceException? failure;

    for (final source in _manager.bookSourcesPrimaryFirst(primary)) {
      final impl = _manager.bookImplOf(source.type);
      if (impl == null) continue;
      // 同类型源 3s 节流：被节流则跳过该源（备用源缺席好过整条检索失败）。
      // 主源的节流门在 _search 里已拦过，此处对主源必然放行。
      final last = _lastRequestTime[source.type];
      if (last != null &&
          DateTime.now().difference(last) < _minRequestInterval) {
        continue;
      }
      try {
        final credentials = await _manager.credentialsOf(source);
        // 必填配置没填全的源直接跳过（省一次注定失败的往返）
        if (!impl.configFields
            .isConfigured(config: source.config, credentials: credentials)) {
          continue;
        }
        final results = await impl.searchBooks(
          q,
          config: source.config,
          credentials: credentials,
        );
        _lastRequestTime[source.type] = DateTime.now();
        if (results.isEmpty) continue;
        batches.add(results);
        sourceNames.add(source.name);
        merged = BookResultMerger.mergeAll(batches);
        if (merged.length >= _bookResultLimit) break;
      } on DataSourceException catch (e) {
        failure ??= e;
      }
    }

    if (merged.isEmpty && failure != null) throw failure;
    return (
      results: merged.take(_bookResultLimit).toList(),
      sourceNames: sourceNames,
    );
  }

  /// 按关键词搜索电影（用当前影视默认源；结果走缓存）
  Future<void> searchMovies(String query) => _search<MovieSearchResult>(
        query: query,
        category: DataSourceCategory.movie,
        probeCache: (q) {
          final source = defaultMovieSource;
          if (source == null) return null;
          return _movieSearchCache.get(_searchKey(source.id, q));
        },
        execute: (source, q) async {
          final credentials = await _manager.credentialsOf(source);
          final impl = _manager.movieImplOf(source.type)!;
          final results = await impl.searchMovies(q,
              config: source.config, credentials: credentials);
          _movieSearchCache.put(_searchKey(source.id, q), results);
          return results;
        },
        setResults: (r) => _movieResults = r,
      );

  /// 取电影详情（导演 / 主演 / 片长补全；失败返回 null——调用方回退搜索结果）；
  /// 同一部片在 TTL 内重复取详情命中缓存。
  Future<MovieSearchResult?> fetchMovieDetail(
    MovieSearchResult result,
  ) async {
    final source = defaultMovieSource;
    final impl = source == null ? null : _manager.movieImplOf(source.type);
    if (source == null || impl == null) return null;
    // externalId 为空时不进缓存：键会退化成「源 id + 空串」，
    // 不同片子会互相污染
    final key = result.externalId.isEmpty
        ? null
        : _detailKey(source.id, result.externalId);
    if (key != null) {
      final cached = _movieDetailCache.get(key);
      if (cached != null) return cached;
    }
    try {
      final credentials = await _manager.credentialsOf(source);
      final detail = await impl.getMovieDetail(
        result.externalId,
        config: source.config,
        credentials: credentials,
      );
      if (key != null) _movieDetailCache.put(key, detail);
      return detail;
    } on DataSourceException {
      return null;
    }
  }

  /// 最近一次详情补全的失败原因（null = 成功 / 未发起 / 仅能力缺失）。
  ///
  /// [fetchBookDetail] 本身仍返回 null 以保持「失败回退搜索结果」的契约；
  /// 调用方读本字段提示用户「补全失败」——但能力缺失（源不支持详情 /
  /// 未配置详情接口）不算失败，不会写入本字段（见 [DataSourceException.silent]）。
  String? _lastDetailError;
  String? get lastDetailError => _lastDetailError;

  /// 取书籍详情（分类 / 简介 / 页数补全；失败返回 null——调用方回退搜索结果）
  ///
  /// 两道省流量的闸，都在真正发请求之前：
  /// 1. **两跳压一跳**（[bookDetailIsRedundant]）：搜索响应已经把详情能补的
  ///    字段全带回来了 → 直接返回 null，省掉这次注定冗余的往返；
  /// 2. **详情缓存**：同一本书在 TTL 内重复取详情命中缓存。
  Future<BookSearchResult?> fetchBookDetail(
    BookSearchResult result,
  ) async {
    final source = defaultBookSource;
    final impl = source == null ? null : _manager.bookImplOf(source.type);
    if (source == null || impl == null) return null;
    _lastDetailError = null;

    // 第 1 道闸：搜索已含全部可补字段，详情只会拿回一份一样的对象
    if (bookDetailIsRedundant(result)) return null;

    final key = result.externalId.isEmpty
        ? null
        : _detailKey(source.id, result.externalId);
    if (key != null) {
      final cached = _bookDetailCache.get(key);
      if (cached != null) return cached;
    }
    try {
      final credentials = await _manager.credentialsOf(source);
      final detail = await impl.getBookDetail(
        result.externalId,
        config: source.config,
        credentials: credentials,
      );
      if (key != null) _bookDetailCache.put(key, detail);
      return detail;
    } on DataSourceException catch (e) {
      // 能力缺失（源不支持详情 / 未配置详情接口）不是失败：搜索结果已经够用，
      // 报「补全失败」是误报。只有真实失败（网络、格式）才写入原因供调用方提示。
      if (!e.silent) _lastDetailError = e.message;
      return null;
    }
  }

  void clearResults() {
    // 递增请求序号，使已发出的网络响应在清空后失效。
    for (final category in DataSourceCategory.values) {
      _searchRequestIds[category] = (_searchRequestIds[category] ?? 0) + 1;
    }
    _activeSearches.clear();
    _lastQuery = '';
    _bookResults = null;
    _movieResults = null;
    _bookSearchSourceNames = const [];
    _searchError = null;
    _isSearching = false;
    // 刻意**不动**缓存：clearResults 在「选中一本结果」后被调用，
    // 此时清缓存等于让用户下一次搜同一个词重新吃一遍网络延迟。
    _notifyIfAlive();
  }

  // ---------- 配置动作 ----------

  /// 测试连接（按 id；行内 loading 由 [testingId] 驱动）
  Future<bool> testSource(String id) async {
    final source = _manager.configs
        .where((c) => c.id == id)
        .toList(growable: false)
        .firstOrNull;
    if (source == null) return false;
    _testingId = id;
    _actionError = null;
    _notifyIfAlive();
    try {
      await _manager.testConnection(source);
      return true;
    } on DataSourceException catch (e) {
      _actionError = e.message;
      return false;
    } finally {
      _testingId = null;
      _notifyIfAlive();
    }
  }

  /// 测试未落盘的草稿配置（新增数据源弹窗内「测试连接」用）。
  /// [testingId] 沿用草稿 id——编辑弹窗行内 loading 可正常驱动。
  Future<bool> testDraft(DataSourceConfig config) async {
    _testingId = config.id;
    _actionError = null;
    _notifyIfAlive();
    try {
      await _manager.testDraft(config);
      return true;
    } on DataSourceException catch (e) {
      _actionError = e.message;
      return false;
    } finally {
      _testingId = null;
      _notifyIfAlive();
    }
  }

  /// 设为默认源（会清空缓存：主源变了，同一个词该有的结果也变了）
  Future<void> setDefault(String id) async {
    await _manager.setDefault(id);
    _invalidateCaches();
    _notifyIfAlive();
  }

  /// 添加数据源（内置类型实例由调用方经 Manager 注册表确定）
  Future<void> addSource(DataSourceConfig config) async {
    await _manager.addConfig(config);
    _invalidateCaches();
    _notifyIfAlive();
  }

  /// 更新数据源（改镜像地址 / 换 key 后旧结果立即失效）
  Future<void> updateSource(DataSourceConfig config) async {
    await _manager.updateConfig(config);
    _invalidateCaches();
    _notifyIfAlive();
  }

  /// 移除数据源（连同凭据清理）
  Future<void> removeSource(String id) async {
    await _manager.removeConfig(id);
    _invalidateCaches();
    _notifyIfAlive();
  }

  /// 保存凭据（secret 配置项；空串 = 删除）
  Future<void> saveCredential(
    DataSourceConfig config,
    String key,
    String value,
  ) =>
      _manager.saveCredential(config, key, value);

  /// 读取凭据（编辑弹窗回显掩码用；未存过返回 null）
  Future<String?> readCredential(DataSourceConfig config, String key) =>
      _manager.credentialsOf(config).then((m) => m[key]);

  /// 类型对应的配置项描述（编辑弹窗动态渲染输入框用）
  List<ConfigField> configFieldsOf(DataSourceType type) {
    final movie = managerMovieFields(type);
    if (movie != null) return movie;
    return managerBookFields(type) ?? const [];
  }

  // Manager 注册表转发（不直接暴露 manager，收窄 UI 可见面）
  List<ConfigField>? managerMovieFields(DataSourceType type) =>
      _manager.movieImplOf(type)?.configFields;

  List<ConfigField>? managerBookFields(DataSourceType type) =>
      _manager.bookImplOf(type)?.configFields;

  @override
  void dispose() {
    _disposed = true;
    _manager.close();
    super.dispose();
  }
}

/// 详情补全是否已成冗余——「两跳压一跳」的判定（公开以便单测）
///
/// 搜索结果已经把 [BookDataSource.getBookDetail] 能补的字段**全部**带回来了。
/// 典型场景是豆瓣系自建代理（simple-boot-douban-api 这类）：它的服务端对每条
/// 搜索结果又抓了一次豆瓣详情页，所以书名 / 作者 / 出版社 / 年份 / ISBN /
/// 页数 / 简介 / 分类 / 评分全在**搜索响应**里。此时再打一次详情接口只会
/// 拿回一份一模一样的对象，白等 1–3 秒，还多给豆瓣送去一次抓取。
///
/// 判定覆盖详情接口的全部补全目标（出版社 / ISBN / 页数 / 简介 / 分类 / 评分）：
/// **任何一项缺失都仍然值得发那次请求**——不能为了省一次往返反而少回填字段。
/// 所以取反过来看：这条判定只在该源"什么都不缺"时才为真。
bool bookDetailIsRedundant(BookSearchResult result) =>
    _hasText(result.publisher) &&
    _hasText(result.isbn) &&
    result.pageCount != null &&
    _hasText(result.description) &&
    result.categories.isNotEmpty &&
    result.rating != null;

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;
