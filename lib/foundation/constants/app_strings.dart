/// 跨页复用文案常量（M-7 建议 2）。
///
/// **为什么放 foundation**：这些文案被 business 层多个模块（library / data_source /
/// profile / sync）共用，四个内置数据源更是共用同一句网络异常。报告原建议放
/// `lib/config/app_strings.dart`——但 `config` 属 app 层，business 引用它就成了
/// 反向依赖（违反 `app → business → component → foundation` 单向约定），故收在
/// foundation。
///
/// **收录范围**（只收「跨文件复用 + 措辞漂移有实际后果」的）：
/// - 失败提示：`保存失败：xxx` 在编辑页与数据源页各写一份；
/// - 网络异常：三个内置数据源的超时 / 网络文案逐字重复；
/// - 字段标签：详情页与编辑页必须逐字一致（如「我的评分」「阅读感悟 & 划线」）。
///
/// **不收录**：单页专属文案（表单 hint、卡片标题、弹窗按钮…）。把 886 处文案
/// 全搬进来只会把「就近可读」换成「886 次跳转」，收益为负；完整 i18n 同样不在
/// 计划内（纯中文单语应用，见审查报告 M-7 的判断）。
library;

abstract final class AppStrings {
  // ---------- 失败提示 ----------

  /// 通用保存失败（书籍 / 影视编辑页、数据源管理页共用）
  static String saveFailed(Object error) => '保存失败：$error';

  /// 备份 / 日志导出失败
  static String exportFailed(Object error) => '导出失败：$error';

  // ---------- 网络异常（四个内置数据源共用同一句）----------

  /// 请求发不出去 / 响应读不到
  static const String networkError = '网络请求失败，请检查网络连接';

  /// 连上了但超过超时阈值
  static const String requestTimeout = '请求超时，请检查网络连接后重试';

  // ---------- 书籍：编辑页与详情页共用 ----------

  static const String myRating = '我的评分';
  static const String unrated = '未评分';
  static const String synopsis = '内容简介';
  static const String publishYear = '出版年份';
  static const String isbnLabel = 'ISBN / 标识';
  static const String readingStart = '开始阅读';
  static const String readingFinished = '阅读完成';
  static const String bookNotes = '阅读感悟 & 划线';

  // ---------- 影视：编辑页与详情页共用 ----------

  static const String releaseDate = '上映时间';
  static const String myReview = '我的影评';
  static const String noStills = '暂无剧照';

  // ---------- 入口 / 列表通用 ----------

  static const String addBook = '添加图书';
  static const String addMovie = '添加电影';
  static const String editProfile = '编辑资料';
  static const String clearFilters = '清除筛选条件';
  static const String networkImageUrl = '网络图片链接';
  static const String networkAvatarUrl = '网络头像链接';

  /// 未配置书籍数据源时点「联网找封面」的兜底提示
  static const String noBookSourceForCover = '未配置书籍数据源，无法联网查找封面';
}
