import 'package:flutter/material.dart';

import '../business/data_source/page/data_source_page.dart';
import '../business/library/page/book_detail_page.dart';
import '../business/library/page/book_edit_page.dart';
import '../business/library/page/movie_detail_page.dart';
import '../business/library/page/movie_edit_page.dart';
import '../business/stats/page/personal_stats_page.dart';
import '../business/sync/page/data_sync_page.dart';
import '../foundation/constants/app_routes.dart';

/// 全局路由表（P3 路由去耦）
///
/// 业务模块之间跳页只引用 [AppRoutes] 的路由名，**不再 import 兄弟模块的
/// Page 类**；页面构建集中在本文件（app 层），依赖方向 app → business 天然合法。
///
/// 参数（`RouteSettings.arguments`）：
/// - [AppRoutes.bookEdit] / [AppRoutes.movieEdit]：`String?`（null = 新增）
/// - [AppRoutes.bookDetail] / [AppRoutes.movieDetail]：`String`（必传 id）
/// - 其余无参
///
/// 返回 null 时由 Flutter 兜底（与未注册路由一致）。
Route<dynamic>? appOnGenerateRoute(RouteSettings settings) {
  switch (settings.name) {
    case AppRoutes.bookDetail:
      return MaterialPageRoute<String>(
        settings: settings,
        builder: (_) => BookDetailPage(bookId: settings.arguments as String),
      );
    case AppRoutes.bookEdit:
      return MaterialPageRoute<String>(
        settings: settings,
        builder: (_) => BookEditPage(bookId: settings.arguments as String?),
      );
    case AppRoutes.movieDetail:
      return MaterialPageRoute<String>(
        settings: settings,
        builder: (_) => MovieDetailPage(movieId: settings.arguments as String),
      );
    case AppRoutes.movieEdit:
      return MaterialPageRoute<String>(
        settings: settings,
        builder: (_) => MovieEditPage(movieId: settings.arguments as String?),
      );
    case AppRoutes.personalStats:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const PersonalStatsPage(),
      );
    case AppRoutes.dataSourceManage:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const DataSourcePage(),
      );
    case AppRoutes.dataSync:
      return MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => const DataSyncPage(),
      );
  }
  return null;
}
