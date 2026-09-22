/// 全局路由名常量（P3 路由去耦）
///
/// 业务模块间跳页不得 import 兄弟模块的 Page 类（规范：同级业务不互相
/// import）。模块侧只引用本文件的路由名 + `Navigator.pushNamed`；
/// **页面构建**统一在 app 层注册（`main.dart` 的 `onGenerateRoute`），
/// app → business 的依赖方向天然合法。
///
/// 参数约定（经 `arguments` 传入，onGenerateRoute 内做类型归一）：
/// - bookEdit / movieEdit：`String?`（null = 新增模式，id = 编辑模式）
/// - bookDetail / movieDetail：`String`（条目 id，必传）
abstract final class AppRoutes {
  static const String bookDetail = '/book/detail';
  static const String bookEdit = '/book/edit';
  static const String movieDetail = '/movie/detail';
  static const String movieEdit = '/movie/edit';
  static const String personalStats = '/stats/personal';
  static const String dataSourceManage = '/data-source';
  static const String dataSync = '/data-sync';
}
