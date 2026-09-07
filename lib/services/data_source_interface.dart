import '../models/data_source.dart';

/// 数据源操作配置项描述（管理页配置弹窗动态生成输入框）
class ConfigField {
  const ConfigField({
    required this.key,
    required this.label,
    this.hint = '',
    this.isSecret = false,
    this.required = false,
  });

  /// 配置键（写入 [DataSourceConfig.config]，secret 类另写安全存储）
  final String key;

  /// 输入框标签
  final String label;

  /// 输入提示
  final String hint;

  /// 是否敏感凭据（true → 存 SecureStorage，UI 密文显示）
  final bool isSecret;

  /// 是否必填（决定「未配置」状态判定）
  final bool required;
}

/// 数据源通用配置校验（基于 [ConfigField] 描述推导，实现类无需重复实现）
extension SourceConfigCheck on List<ConfigField> {
  /// 该源是否可开箱即用（无需任何必填配置，如 Google Books）
  bool get worksWithoutConfig => isEmpty;

  /// 校验配置是否完整（required 项在 config 或凭据中都有值）
  bool isConfigured({
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) =>
      where((f) => f.required).every((f) =>
          (credentials[f.key]?.trim().isNotEmpty ?? false) ||
          (config[f.key]?.toString().trim().isNotEmpty ?? false));
}

/// 书籍数据源契约（Google Books / 豆瓣等实现）
///
/// 实现要求：
/// - 全部方法可抛 [DataSourceException]（message 面向用户，中文）；
/// - 实现类不持有可变状态（按调用传入 config，实例可复用）；
/// - 网络实现通过构造注入 http 客户端（测试替换 fake）。
abstract class BookDataSource {
  /// 类型标识
  DataSourceType get type;

  /// 配置项描述（管理页动态渲染；配置校验用 [SourceConfigCheck] 扩展）
  List<ConfigField> get configFields;

  /// 测试连接：请求一次轻量接口，成功返回 true；
  /// 失败抛 [DataSourceException]（Provider 归一化为 timeout / error 状态）
  Future<bool> testConnection({
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  });

  /// 按关键词搜索书籍（返回 ≤ [limit] 条；无结果返回空列表）
  Future<List<BookSearchResult>> searchBooks(
    String query, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
    int limit = 10,
  });

  /// 书籍详情（分类 / 简介 / 页数补全——搜索接口常缺失这些字段）；
  /// 不支持详情的源抛 [DataSourceException]，调用方回退用搜索结果回填
  Future<BookSearchResult> getBookDetail(
    String externalId, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  });
}

/// 影视数据源契约（TMDB 等）
abstract class MovieDataSource {
  DataSourceType get type;

  List<ConfigField> get configFields;

  Future<bool> testConnection({
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  });

  /// 按关键词搜索电影
  Future<List<MovieSearchResult>> searchMovies(
    String query, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
    int limit = 10,
  });

  /// 电影详情（导演 / 主演 / 片长 / 类型补全——搜索接口常缺失这些字段）；
  /// 不支持详情的源抛 [DataSourceException]，调用方回退用搜索结果回填
  Future<MovieSearchResult> getMovieDetail(
    String externalId, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  });
}

/// 凭据存取抽象（安全存储切片；测试注入内存实现）
abstract class DataSourceCredentialStore {
  Future<String?> read(String sourceId, String key);
  Future<void> write(String sourceId, String key, String value);
  Future<void> delete(String sourceId, String key);
}
