import 'package:flutter/foundation.dart';

import 'model/data_source.dart';

/// 跨模块数据源门面契约 —— library（编辑页快速检索/联网找封面）与
/// sync（恢复后刷新配置）对数据源模块的唯一依赖点。
///
/// 只暴露消费方实际用到的成员；配置管理页（数据源模块内部）仍直接用
/// [DataSourceProvider]（见 `data_source/view_model/`），不经过本接口。
///
/// 装配：app 层以 `ListenableProvider<DataSourceFacade>` 注册**同一实例**，
/// `implements Listenable` 满足泛型约束，select 反应性与实现一致。
abstract class DataSourceFacade implements Listenable {
  // ==================== 配置（读） ====================

  /// 书籍默认源（null = 未配置，编辑页隐藏快速检索）
  DataSourceConfig? get defaultBookSource;

  /// 影视默认源
  DataSourceConfig? get defaultMovieSource;

  // ==================== 检索状态（select 订阅） ====================

  /// 是否检索中
  bool get isSearching;

  /// 最近一次检索错误（null = 无；空串 = 无结果不算错误）
  String? get searchError;

  /// 最近一次详情补全错误（null = 无）
  String? get lastDetailError;

  /// 书籍检索结果（null = 尚未检索）
  List<BookSearchResult>? get bookResults;

  /// 电影检索结果（null = 尚未检索）
  List<MovieSearchResult>? get movieResults;

  /// 书籍检索命中的源名（结果区标题溯源用）
  List<String> get bookSearchSourceNames;

  // ==================== 检索动作 ====================

  /// 按关键词搜索书籍（当前书籍默认源）
  Future<void> searchBooks(String query);

  /// 按关键词搜索电影（当前影视默认源）
  Future<void> searchMovies(String query);

  /// 清空检索状态
  void clearResults();

  /// 书籍详情补全（失败返回 null，调用方回退搜索结果）
  Future<BookSearchResult?> fetchBookDetail(BookSearchResult result);

  /// 电影详情补全（失败返回 null，调用方回退搜索结果）
  Future<MovieSearchResult?> fetchMovieDetail(MovieSearchResult result);

  /// 联网找一本书的封面 URL（ISBN 优先；失败返回 null）
  Future<String?> lookupBookCover({required String title, String? isbn});

  // ==================== 配置生命周期（sync 模块用） ====================

  /// 重载配置（云备份/本地导入恢复 data_sources.json 后调用）
  Future<void> reload();

  /// 恢复备份后检查：返回必填凭据缺失的数据源名
  Future<List<String>> sourcesMissingCredentials();
}
