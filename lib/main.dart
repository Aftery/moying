import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    provider.init();
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
    // 系统状态栏/导航栏随主题偏好联动（依赖变化时自动重调）
    _syncSystemChrome(context.watch<LibraryProvider>().themeMode);
    // 首帧后触发一次「启动时自动同步」（节流与条件判断在 SyncProvider 内）
    if (!_autoSyncFired) {
      _autoSyncFired = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<SyncProvider>().tryAutoSyncOnResume();
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
    final themeMode =
        resolveThemeMode(context.watch<LibraryProvider>().themeMode);
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
