import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

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
  // 系统状态栏使用浅色内容（适配暗色 UI）
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF1A1A2E),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  final provider = await createAppProvider();
  runApp(MoYingApp(provider: provider));
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
    return ChangeNotifierProvider(
      create: (_) => widget.provider ?? LibraryProvider(),
      child: MaterialApp(
        title: '墨影',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        darkTheme: buildAppTheme(),
        themeMode: ThemeMode.dark,
        home: const MainShell(),
      ),
    );
  }
}
