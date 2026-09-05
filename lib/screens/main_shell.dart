import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import 'books_screen.dart';
import 'dashboard_screen.dart';
import 'library_screens.dart';
import 'profile_screen.dart';

/// 主框架：底部导航（仪表盘 / 书籍 / 电影 / 个人）
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  // 仪表盘「查看全部」等入口跳 Tab 的回调（非 const，其余三页保持 const）
  late final _pages = <Widget>[
    DashboardScreen(
      onOpenBooks: () => setState(() => _index = 1),
      onOpenMovies: () => setState(() => _index = 2),
    ),
    const BooksScreen(),
    const MoviesScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack 保持各 Tab 状态（滚动位置等）
      body: IndexedStack(index: _index, children: _pages),
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
