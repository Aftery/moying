import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'component/media/local_media_scope.dart';
import 'component/theme/app_palette.dart';
import 'app/config/app_theme.dart';
import 'business/library/repository/persistence.dart';
import 'business/data_source/view_model/data_source_provider.dart';
import 'business/library/view_model/library_provider.dart';
import 'business/shared/data_source_facade.dart';
import 'business/shared/library_facade.dart';
import 'business/sync/view_model/sync_provider.dart';
import 'app/pages/root_page.dart';
import 'app/router.dart';
import 'foundation/logger/app_logger.dart';
import 'business/data_source/service/data_source_manager.dart';

/// 「墨影」入口 —— 书籍与电影记录应用
///
/// 手机/桌面：启动即接入本地持久化（await init 完成再渲染，避免闪现 seed）；
/// Web：回退内存模式（见 data/persistence.dart 的按平台接线）。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 日志中枢尽早就位：启动期的问题也要能记下来（供「个人 → 错误日志」查看导出）
  await AppLogger.instance.init();
  AppLogger.instance.info('app', '应用启动');

  // 全局兜底：捕获所有未处理异常，保证 App 永不完全崩溃。
  // 除控制台外同步写入日志，用户可在导出后反馈给开发者。
  // L-6: presentError 会打印更完整的 widget 树诊断信息（含 informationCollector），
  // 并触发 debug 下红屏；只打 own line 的话，这些诊断信息就丢失了。
  FlutterError.onError = (details) {
    FlutterError.presentError(details); // 保留默认行为（完整诊断 + debug 红屏）
    AppLogger.instance.fatal(
      'flutter',
      'Flutter 框架错误',
      error: details.exception,
      stack: details.stack,
      meta: {
        if ((details.library ?? '').isNotEmpty) 'library': details.library!,
      },
    );
  };
  PlatformDispatcher.instance.onError = (e, st) {
    debugPrint('[AsyncError] $e\n$st');
    AppLogger.instance.fatal('async', '未捕获的异步异常', error: e, stack: st);
    return true; // 已处理，不继续向上传播
  };

  final boot = await bootstrapApp();
  final sync = SyncProvider(store: boot.store, library: boot.library);
  await sync.loadSettings();
  final dataSource = DataSourceProvider(
    manager: DataSourceManager(store: boot.store),
  );
  await dataSource.init();
  runApp(MoYingApp(
    library: boot.library,
    sync: sync,
    dataSource: dataSource,
  ));
}

/// 档案中的主题偏好字符串 → ThemeMode
ThemeMode resolveThemeMode(String mode) {
  switch (mode) {
    case 'light':
      return ThemeMode.light;
    case 'system':
      return ThemeMode.system;
    default:
      return ThemeMode.dark;
  }
}

class MoYingApp extends StatefulWidget {
  const MoYingApp({super.key, this.library, this.sync, this.dataSource});

  /// 书影库 Provider；不传则用内存模式自建（测试 / 预览快速起应用）
  final LibraryProvider? library;

  /// 数据同步 Provider；不传则自建（Web / 测试内存模式无存储）
  final SyncProvider? sync;

  /// 数据源 Provider；不传则自建（测试快速起应用）
  final DataSourceProvider? dataSource;

  @override
  State<MoYingApp> createState() => _MoYingAppState();
}

class _MoYingAppState extends State<MoYingApp> {
  late final AppLifecycleListener _lifecycleListener;
  late final LibraryProvider _library;
  late final SyncProvider _sync;
  late final DataSourceProvider _dataSource;
  late final bool _ownsLibrary;
  late final bool _ownsSync;
  late final bool _ownsDataSource;

  @override
  void initState() {
    super.initState();
    _ownsLibrary = widget.library == null;
    _ownsSync = widget.sync == null;
    _ownsDataSource = widget.dataSource == null;
    _library = widget.library ?? LibraryProvider();
    _sync = widget.sync ?? SyncProvider(store: null, library: _library);
    _dataSource = widget.dataSource ?? _buildFallbackDataSource();
    // App 挂起/隐藏/退出前冲刷合并写，尽量缩小「改了但还没落盘」的窗口
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) {
          unawaited(_library.flush());
        }
      },
    );
  }

  /// 兜底数据源（无注入时仅内存预设，配置不落盘；测试环境用）
  DataSourceProvider _buildFallbackDataSource() {
    final provider = DataSourceProvider(manager: DataSourceManager());
    provider.init().catchError((e, st) {
      debugPrint('[FallbackDataSource] init failed: $e');
    });
    return provider;
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    if (_ownsDataSource) _dataSource.dispose();
    if (_ownsSync) _sync.dispose();
    if (_ownsLibrary) _library.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 注意：本层 context 在 Provider 之上，不能 watch；
    // 主题偏好读取与系统栏同步都下沉到 Provider 之下的 _AppShell。
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _library),
        // 跨模块门面：同一实例再注册为 LibraryFacade，供 stats/profile/sync
        // 依赖接口而非 library 实现（同级引用清零）。用 ListenableProvider
        // 而非 Provider，才会订阅 ChangeNotifier 的通知、select 才会重建。
        ListenableProvider<LibraryFacade>.value(value: _library),
        ChangeNotifierProvider.value(value: _sync),
        ChangeNotifierProvider.value(value: _dataSource),
        // 数据源门面：library 编辑页（快速检索/找封面）与 sync 页依赖接口
        ListenableProvider<DataSourceFacade>.value(value: _dataSource),
      ],
      child: const _AppShell(),
    );
  }
}

/// Provider 之下的应用壳：读主题偏好 → 构建 MaterialApp + 同步系统栏
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  bool _autoSyncFired = false;
  String? _lastScheduledThemeMode;

  /// 本地图解析器：component 层只声明契约（[LocalMediaResolver]），
  /// 真实实现（读 LibraryProvider 解析 images/ 目录）在 app 层注入。
  /// 用方法 tear-off 而非闭包字段：实例方法 tear-off 身份稳定，
  /// 不会每次 rebuild 都通知下游重建，也无需在入口 import dart:io。
  String? _resolveLocalMedia(BuildContext ctx, String? localFile) =>
      ctx.read<LibraryProvider>().resolveLocalImage(localFile)?.path;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 自动同步只在首帧触发一次，系统栏同步由 build 按主题变化调度。
    if (!_autoSyncFired) {
      _autoSyncFired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<SyncProvider>().tryAutoSyncOnResume();
        }
      });
    }
  }

  void _syncSystemChrome(String mode) {
    final resolved = resolveThemeMode(mode);
    final darkUi = resolved == ThemeMode.dark ||
        (resolved == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: darkUi ? Brightness.light : Brightness.dark,
        statusBarBrightness: darkUi ? Brightness.dark : Brightness.light,
        systemNavigationBarColor:
            darkUi ? const Color(0xFF1A1A2E) : Colors.white,
        systemNavigationBarIconBrightness:
            darkUi ? Brightness.light : Brightness.dark,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // M6：select 只订阅主题模式，书库/档案变化不再触发整棵 MaterialApp 重建
    final rawTheme =
        context.select<LibraryProvider, String>((p) => p.themeMode);
    final themeMode = resolveThemeMode(rawTheme);
    if (_lastScheduledThemeMode != rawTheme) {
      _lastScheduledThemeMode = rawTheme;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncSystemChrome(rawTheme);
      });
    }
    // LocalMediaScope 必须位于 Navigator 之上，pushed 路由与弹层才能取到解析器
    return LocalMediaScope(
      resolver: _resolveLocalMedia,
      child: MaterialApp(
        title: '墨影',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(AppPalette.light),
        darkTheme: buildAppTheme(AppPalette.dark),
        themeMode: themeMode,
        home: const RootPage(),
        // P3：跨模块跳页走全局路由表（app 层构建页面，模块间不再 import 兄弟 Page）
        onGenerateRoute: appOnGenerateRoute,
      ),
    );
  }
}
