import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'config/app_palette.dart';
import 'config/app_theme.dart';
import 'data/persistence.dart';
import 'providers/library_provider.dart';
import 'screens/main_shell.dart';

/// 「墨影」入口 —— 书籍与电影记录应用
///
/// 手机/桌面：启动即接入本地持久化（await init 完成再渲染，避免闪现 seed）；
/// Web：回退内存模式（见 data/persistence.dart 的按平台接线）。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final provider = await createAppProvider();
  runApp(MoYingApp(provider: provider));
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
  const MoYingApp({super.key, this.provider});

  /// 全局 Provider；不传则用内存模式自建（测试 / 预览快速起应用）
  final LibraryProvider? provider;

  @override
  State<MoYingApp> createState() => _MoYingAppState();
}

class _MoYingAppState extends State<MoYingApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // App 挂起/隐藏/退出前冲刷合并写，尽量缩小「改了但还没落盘」的窗口
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.detached) {
          widget.provider?.flush();
        }
      },
    );
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
    return ChangeNotifierProvider(
      create: (_) => widget.provider ?? LibraryProvider(),
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
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 系统状态栏/导航栏随主题偏好联动（依赖变化时自动重调）
    _syncSystemChrome(context.watch<LibraryProvider>().themeMode);
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
