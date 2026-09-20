import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../providers/library_provider.dart';
import 'books_page.dart';
import 'dashboard_page.dart';
import 'movies_page.dart';
import 'profile_page.dart';

/// 主框架：底部导航（仪表盘 / 书籍 / 电影 / 个人）
class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;

  // 仪表盘「查看全部」等入口跳 Tab 的回调（非 const，其余三页保持 const）
  late final _pages = <Widget>[
    DashboardPage(
      onOpenBooks: () => setState(() => _index = 1),
      onOpenMovies: () => setState(() => _index = 2),
    ),
    const BooksPage(),
    const MoviesPage(),
    const ProfilePage(),
  ];

  // M7：SnackBar 一次性调度锁——同一帧多次 rebuild 只弹一次，
  // 消费完错误才复位，避免排队多个重复 SnackBar
  bool _persistToastScheduled = false;

  void _schedulePersistToast(String message) {
    if (_persistToastScheduled || !mounted) return;
    _persistToastScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: context.colors.error,
          ),
        );
      } finally {
        _persistToastScheduled = false;
        context.read<LibraryProvider>().clearPersistError();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 监听写盘错误并及时提示
    final persistError = context.select<LibraryProvider, String>(
      (p) => p.lastPersistError,
    );
    if (persistError.isNotEmpty) {
      _schedulePersistToast(persistError);
    }

    return Scaffold(
      // IndexedStack 保持各 Tab 状态（滚动位置等），各 Tab 套 RepaintBoundary 隔离绘制边界
      body: IndexedStack(
        index: _index,
        children: [
          for (final page in _pages) RepaintBoundary(child: page),
        ],
      ),
      bottomNavigationBar: Container(
        decoration:  BoxDecoration(
          color: context.colors.surface,
          border: Border(
            top: BorderSide(color: context.colors.outline, width: 0.6),
          ),
        ),
        child: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard_rounded),
                label: '仪表盘',
              ),
              NavigationDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book_rounded),
                label: '书籍',
              ),
              NavigationDestination(
                icon: Icon(Icons.movie_outlined),
                selectedIcon: Icon(Icons.movie_rounded),
                label: '电影',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: '个人',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
