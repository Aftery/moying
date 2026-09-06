import 'package:flutter/foundation.dart';

import '../models/data_source.dart';
import '../services/data_source_interface.dart';
import '../services/data_source_manager.dart';

/// 数据源状态与搜索动作（ChangeNotifier）
///
/// - 配置管理（加载 / 增删改 / 设默认 / 测试连接）走 [DataSourceManager]；
/// - 快速检索：按类别取默认源搜索，状态（进行中 / 结果 / 错误）驱动编辑页 UI；
/// - debounce 由 UI 层负责（Timer 500ms），Provider 只收最终查询词。
class DataSourceProvider extends ChangeNotifier {
  DataSourceProvider({required DataSourceManager manager})
      : _manager = manager;

  final DataSourceManager _manager;

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
  String? testingId;

  /// 最近一次全局错误（配置操作失败提示；搜索错误单独走 searchError）
  String? actionError;

  /// 初始化：加载配置（首次启动写内置预设）
  Future<void> init() async {
    await _manager.loadConfigs();
    notifyListeners();
  }

  /// 重载配置（云备份/本地导入恢复 data_sources.json 后调用）
  Future<void> reload() async {
    await _manager.loadConfigs();
    notifyListeners();
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
  List<BookSearchResult>? bookResults;

  /// 电影搜索结果
  List<MovieSearchResult>? movieResults;

  /// 最近一次搜索错误（null = 无错误；空串 = 无结果不视为错误）
  String? searchError;

  /// 最近一次搜索的关键词（结果区标题与去重判断用）
  String lastQuery = '';

  /// 按关键词搜索书籍（用当前书籍默认源）
  Future<void> searchBooks(String query) async {
    final q = query.trim();
    lastQuery = q;
    if (q.isEmpty) {
      bookResults = null;
      searchError = null;
      _isSearching = false;
      notifyListeners();
      return;
    }
    final source = defaultBookSource;
    if (source == null) {
      bookResults = null;
      searchError = '尚未配置书籍数据源';
      notifyListeners();
      return;
    }
    final impl = _manager.bookImplOf(source.type);
    if (impl == null) {
      bookResults = null;
      searchError = '暂不支持的数据源类型：${source.type.displayName}';
      notifyListeners();
      return;
    }

    _isSearching = true;
    searchError = null;
    notifyListeners();
    try {
      final credentials = await _manager.credentialsOf(source);
      final results = await impl.searchBooks(
        q,
        config: source.config,
        credentials: credentials,
      );
      // 期间用户可能改了查询词（竞态：仅当仍是本次查询时采纳结果）
      if (lastQuery != q) return;
      bookResults = results;
      if (results.isEmpty) searchError = '';
    } on DataSourceException catch (e) {
      if (lastQuery != q) return;
      bookResults = null;
      searchError = e.message;
    } finally {
      if (lastQuery == q) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  /// 按关键词搜索电影（用当前影视默认源）
  Future<void> searchMovies(String query) async {
    final q = query.trim();
    lastQuery = q;
    if (q.isEmpty) {
      movieResults = null;
      searchError = null;
      _isSearching = false;
      notifyListeners();
      return;
    }
    final source = defaultMovieSource;
    if (source == null) {
      movieResults = null;
      searchError = '尚未配置影视数据源';
      notifyListeners();
      return;
    }
    final impl = _manager.movieImplOf(source.type);
    if (impl == null) {
      movieResults = null;
      searchError = '暂不支持的数据源类型：${source.type.displayName}';
      notifyListeners();
      return;
    }

    _isSearching = true;
    searchError = null;
    notifyListeners();
    try {
      final credentials = await _manager.credentialsOf(source);
      final results = await impl.searchMovies(
        q,
        config: source.config,
        credentials: credentials,
      );
      if (lastQuery != q) return;
      movieResults = results;
      if (results.isEmpty) searchError = '';
    } on DataSourceException catch (e) {
      if (lastQuery != q) return;
      movieResults = null;
      searchError = e.message;
    } finally {
      if (lastQuery == q) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  /// 取电影详情（导演 / 主演 / 片长补全；失败返回 null——调用方回退搜索结果）
  Future<MovieSearchResult?> fetchMovieDetail(
    MovieSearchResult result,
  ) async {
    final source = defaultMovieSource;
    final impl =
        source == null ? null : _manager.movieImplOf(source.type);
    if (source == null || impl == null) return null;
    try {
      final credentials = await _manager.credentialsOf(source);
      return await impl.getMovieDetail(
        result.externalId,
        config: source.config,
        credentials: credentials,
      );
    } on DataSourceException {
      return null;
    }
  }

  void clearResults() {
    lastQuery = '';
    bookResults = null;
    movieResults = null;
    searchError = null;
    _isSearching = false;
    notifyListeners();
  }

  // ---------- 配置动作 ----------

  /// 测试连接（按 id；行内 loading 由 [testingId] 驱动）
  Future<bool> testSource(String id) async {
    final source = _manager.configs
        .where((c) => c.id == id)
        .toList(growable: false)
        .firstOrNull;
    if (source == null) return false;
    testingId = id;
    actionError = null;
    notifyListeners();
    try {
      await _manager.testConnection(source);
      return true;
    } on DataSourceException catch (e) {
      actionError = e.message;
      return false;
    } finally {
      testingId = null;
      notifyListeners();
    }
  }

  /// 设为默认源
  Future<void> setDefault(String id) async {
    await _manager.setDefault(id);
    notifyListeners();
  }

  /// 添加数据源（内置类型实例由调用方经 Manager 注册表确定）
  Future<void> addSource(DataSourceConfig config) async {
    await _manager.addConfig(config);
    notifyListeners();
  }

  /// 更新数据源
  Future<void> updateSource(DataSourceConfig config) async {
    await _manager.updateConfig(config);
    notifyListeners();
  }

  /// 移除数据源（连同凭据清理）
  Future<void> removeSource(String id) async {
    await _manager.removeConfig(id);
    notifyListeners();
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
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
