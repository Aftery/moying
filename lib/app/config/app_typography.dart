/// 排版层级 —— 全项目字号唯一来源（M-6）
///
/// 现状：327 处字面量字号里，11/12/13/14/15 五种占 75%，彼此只差 1px，
/// 层级几乎无法区分——说明字号是逐处手调而非按层级选取。本文件把「层级」
/// 显式命名，遏制继续发散。
///
/// **迁移策略（刻意保守）**：仅用于**新代码**，旧代码在后续触碰时顺手替换，
/// 不做一次性全仓替换（327 处手工替换风险高于收益，且污染 diff）。
/// 归并参照：`13 → label`、`12 → caption`、`11 → caption 或 micro`、
/// `15 → subhead`、`17 → heading`、`18 → title`、`24 → display`。
///
/// 注：本类是纯设计令牌（编译期常量），刻意不随主题变化，故为静态常量；
/// 若某处需要随主题缩放的排版，应走 `Theme.of(context).textTheme`，非本表。
abstract final class AppType {
  /// 页面主数值 / 年度报告大数字
  static const double display = 24;

  /// 页面标题（AppBar）
  static const double title = 18;

  /// 卡片标题 / 区块标题
  static const double heading = 17;

  /// 强调正文 / 表单分区标题
  static const double subhead = 15;

  /// 正文 / 输入框
  static const double body = 14;

  /// 列表项副标题 / 按钮标签
  static const double label = 13;

  /// 辅助说明 / 时间戳
  static const double caption = 12;

  /// 徽标 / 角标
  static const double micro = 10;
}
