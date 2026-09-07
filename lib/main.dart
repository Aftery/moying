import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'package:provider/provider.dart';

import 'config/app_palette.dart';
import 'config/app_theme.dart';
import 'data/persistence.dart';
import 'providers/data_source_provider.dart';
import 'providers/library_provider.dart';
import 'providers/sync_provider.dart';
import 'screens/main_shell.dart';
import 'services/data_source_manager.dart';

/// 「墨影」入口 —— 书籍与电影记录应用
///
/// 手机/桌面：启动即接入本地持久化（await init 完成再渲染，避免闪现 seed）；
/// Web：回退内存模式（见 data/persistence.dart 的按平台接线）。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局兜底：捕获所有未处理异常，保证 App 永不完全崩溃
  FlutterError.onError = (d) => debugPrint('[FlutterError] ${d.exception}');
  PlatformDispatcher.instance.onError = (e, st) {
    debugPrint('[AsyncError] $e\n$st');
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

  @override
  void initState() {
    super.initState();
    _library = widget.library ?? LibraryProvider();
    _sync = widget.sync ?? SyncProvider(store: null, library: _library);
    _dataSource = widget.dataSource ?? _buildFallbackDataSource();
    // App 挂起/隐藏/退出前冲刷合并写，尽量缩小「改了但还没落盘」的窗口
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) {
          _library.flush();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 注意：本层 context 在 Provider 之上，不能 watch；
    // 主题偏好读取与系统栏同步都下沉到 Provider 之下的 _AppShell。
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _library),
        ChangeNotifierProvider.value(value: _sync),
        ChangeNotifierProvider.value(value: _dataSource),
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ponytail: SystemChrome 副作用从 didChangeDependencies 下沉到 postFrame
    if (!_autoSyncFired) {
      _autoSyncFired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncSystemChrome(context.read<LibraryProvider>().themeMode);
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
    final rawTheme = context.select<LibraryProvider, String>((p) => p.themeMode);
    final themeMode = resolveThemeMode(rawTheme);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncSystemChrome(rawTheme);
    });
    return MaterialApp(
      title: '墨影',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(AppPalette.light),
      darkTheme: buildAppTheme(AppPalette.dark),
      themeMode: themeMode,
      home: const MainShell(),
    );
  }
}
