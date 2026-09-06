import 'dart:collection';

import '../data/library_store.dart';
import '../models/data_source.dart';
import 'data_source_interface.dart';
import 'data_sources/google_books_data_source.dart';
import 'data_sources/tmdb_data_source.dart';
import 'secure_storage_service.dart';

/// 数据源注册与管理（服务层，无 UI 状态）
///
/// 职责：
/// - 类型 → 实现实例的注册表（测试可注入 fake 覆盖）；
/// - 配置加载 / 保存：`data_sources.json`（凭据走 [DataSourceCredentialStore]）；
/// - 首次启动（配置文件不存在）写入内置默认预设：TMDB（影视默认，未配置）+
///   Google Books（书籍默认，开箱即用）；
/// - 测试连接并把结果（状态 / 摘要 / 时间）落盘。
class DataSourceManager {
  DataSourceManager({
    LibraryStore? store,
    DataSourceCredentialStore? credentials,
    MovieDataSource? tmdb,
    BookDataSource? googleBooks,
  })  : _store = store,
        _credentials = credentials ?? DataSourceSecureCredentials() {
    registerMovie(tmdb ?? TmdbDataSource());
    registerBook(googleBooks ?? GoogleBooksDataSource());
  }

  /// null = 无本地存储环境（Web / 测试内存模式）：配置仅内存预设、不落盘
  final LibraryStore? _store;
  final DataSourceCredentialStore _credentials;

  final Map<DataSourceType, MovieDataSource> _movieImpls = {};
  final Map<DataSourceType, BookDataSource> _bookImpls = {};

  /// 当前生效的配置列表（内存镜像；改动即落盘；M2: 对外只读，防绕过 notifyListeners 改状态）
  List<DataSourceConfig> _configs = [];

  UnmodifiableListView<DataSourceConfig> get configs => UnmodifiableListView(_configs);

  void registerMovie(MovieDataSource impl) => _movieImpls[impl.type] = impl;

  void registerBook(BookDataSource impl) => _bookImpls[impl.type] = impl;

  // ---------- 查询 ----------

  /// 类别下的默认源（无则 null——编辑页据此决定是否显示快速检索）
  DataSourceConfig? defaultSourceOf(DataSourceCategory category) {
    for (final c in configs) {
      if (c.category == category && c.isDefault) return c;
    }
    return null;
  }

  MovieDataSource? movieImplOf(DataSourceType type) => _movieImpls[type];

  BookDataSource? bookImplOf(DataSourceType type) => _bookImpls[type];

  /// 读取某源的凭据键值对（secret 配置项）
  Future<Map<String, String>> credentialsOf(DataSourceConfig config) async {
    final impl = _implFields(config.type);
    final out = <String, String>{};
    for (final field in impl) {
      if (!field.isSecret) continue;
      final value = await _credentials.read(config.id, field.key);
      if (value != null && value.isNotEmpty) out[field.key] = value;
    }
    return out;
  }

  /// 写 / 删凭据（value 为空串视为删除）
  Future<void> saveCredential(
    DataSourceConfig config,
    String key,
    String value,
  ) =>
      _credentials.write(config.id, key, value);

  /// 删除该源全部凭据（移除数据源时调用）
  Future<void> deleteAllCredentials(DataSourceConfig config) async {
    for (final field in _implFields(config.type)) {
      if (field.isSecret) await _credentials.delete(config.id, field.key);
    }
  }

  List<ConfigField> _implFields(DataSourceType type) {
    final fields = <ConfigField>[];
    final movie = _movieImpls[type];
    if (movie != null) fields.addAll(movie.configFields);
    final book = _bookImpls[type];
    if (book != null) fields.addAll(book.configFields);
    return fields;
  }

  // ---------- 加载 / 保存 ----------

  /// 加载配置；文件不存在（首次启动）写入内置预设。
  /// 返回生效的配置列表（同时写入 [configs]）。
  Future<List<DataSourceConfig>> loadConfigs() async {
    final store = _store;
    final loaded = store == null ? null : await store.loadDataSourceConfigs();
    if (loaded == null) {
      _configs = _builtinPresets();
      await saveConfigs();
      return configs;
    }
    _configs = loaded;
    return configs;
  }

  /// 保存当前配置列表（无存储环境静默跳过）
  Future<void> saveConfigs() async {
    final store = _store;
    if (store == null) return;
    await store.saveDataSourceConfigs(_configs);
  }

  /// 内置默认预设：TMDB（影视默认）+ Google Books（书籍默认，免配置）
  static List<DataSourceConfig> _builtinPresets() => [
        const DataSourceConfig(
          id: 'builtin_tmdb',
          type: DataSourceType.tmdb,
          name: 'TMDB (The Movie Database)',
          isDefault: true,
          status: DataSourceStatus.notConfigured,
        ),
        const DataSourceConfig(
          id: 'builtin_googlebooks',
          type: DataSourceType.googleBooks,
          name: 'Google Books',
          isDefault: true,
          status: DataSourceStatus.connected,
          summary: '免 API Key 免配置',
        ),
      ];

  // ---------- CRUD ----------

  /// 添加一个内置类型的数据源实例（豆瓣等后续迭代类型由 UI 拦截）
  Future<DataSourceConfig> addConfig(DataSourceConfig config) async {
    _configs = [..._configs, config];
    await saveConfigs();
    return config;
  }

  /// 更新配置（按 id 替换；M12: id 缺失抛异常防静默丢失）
  Future<void> updateConfig(DataSourceConfig config) async {
    final idx = _configs.indexWhere((c) => c.id == config.id);
    if (idx < 0) {
      throw const DataSourceException('要更新的数据源不存在');
    }
    _configs = [
      for (final c in _configs) if (c.id == config.id) config else c,
    ];
    await saveConfigs();
  }

  /// 移除数据源（同时清理凭据；若它是默认源，把同类剩余第一个顶上）
  Future<void> removeConfig(String id) async {
    final targets = _configs.where((c) => c.id == id).toList(growable: false);
    for (final c in targets) {
      await deleteAllCredentials(c);
    }
    _configs.removeWhere((c) => c.id == id);
    for (final target in targets.where((c) => c.isDefault)) {
      final sameCategory =
          _configs.where((c) => c.category == target.category).toList();
      if (sameCategory.isNotEmpty) {
        final first = sameCategory.first;
        _configs = [
          for (final c in _configs)
            c.id == first.id ? c.copyWith(isDefault: true) : c,
        ];
      }
    }
    await saveConfigs();
  }

  /// 设为默认源（同类别互斥）
  Future<void> setDefault(String id) async {
    final index = _configs.indexWhere((c) => c.id == id);
    if (index < 0) {
      throw const DataSourceException('数据源不存在，可能已被删除');
    }
    final target = _configs[index];
    _configs = [
      for (final c in _configs)
        c.copyWith(
          isDefault: c.id == id
              ? true
              : (c.category == target.category ? false : c.isDefault),
        ),
    ];
    await saveConfigs();
  }

  // ---------- 测试连接 ----------

  /// 测试连接并更新状态落盘（成功 → connected；超时 → timeout；其他 → error）
  Future<DataSourceConfig> testConnection(DataSourceConfig config) async {
    final credentials = await credentialsOf(config);
    final implMovie = _movieImpls[config.type];
    final implBook = _bookImpls[config.type];
    if (implMovie == null && implBook == null) {
      throw DataSourceException('暂不支持的数据源类型：${config.type.displayName}');
    }

    DataSourceStatus status;
    String summary;
    try {
      final ok = implMovie != null
          ? await implMovie.testConnection(
              config: config.config, credentials: credentials)
          : await implBook!.testConnection(
              config: config.config, credentials: credentials);
      status = ok ? DataSourceStatus.connected : DataSourceStatus.error;
      summary = ok ? '连接成功' : '接口响应异常';
    } on DataSourceException catch (e) {
      final msg = e.message.toLowerCase();
      status = msg.contains('超时') || msg.contains('timeout')
          ? DataSourceStatus.timeout
          : DataSourceStatus.error;
      summary = e.message;
    }

    final updated = config.copyWith(
      status: status,
      lastTestedAt: DateTime.now(),
      summary: summary,
    );
    await updateConfig(updated);
    return updated;
  }

  /// 释放各数据源实现占用的底层网络连接与资源
  void close() {
    for (final impl in _movieImpls.values) {
      if (impl is TmdbDataSource) impl.close();
    }
    for (final impl in _bookImpls.values) {
      if (impl is GoogleBooksDataSource) impl.close();
    }
  }
}
