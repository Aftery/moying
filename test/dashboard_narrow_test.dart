// 回归测试：仪表盘在窄屏（常见小屏安卓机）不产生溢出异常
// 背景：观影统计卡旧布局在双卡并排时，右侧 RatingStars（约 109px）超出
// 剩余空间（约 48-75px）导致 RenderFlex overflow；已改为与阅读卡同构的
// 文字明细行。此测试锁定 360×640 视口下不回归。
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moying/main.dart';

void main() {
  testWidgets('仪表盘在 360×640 窄屏不产生溢出异常', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MoYingApp());
    await tester.pumpAndSettle();

    // 无 RenderFlex overflow 等未捕获异常
    expect(tester.takeException(), isNull);

    // 观影统计卡渲染出新布局：均分徽章 + 与阅读卡同构的明细行
    // （数字由真实列表聚合：T3 seed 迁移使 kMovieList 含 3 部 watchlist、5 部 rated）
    expect(find.text('WATCHING'), findsOneWidget);
    expect(find.text('想看'), findsOneWidget);
    expect(find.text('3 部'), findsOneWidget);
    expect(find.text('已评'), findsOneWidget);
    expect(find.text('5 部'), findsOneWidget);
  });

  testWidgets('图书列表页在窄屏渲染不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MoYingApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('书籍'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 书库以可滚动网格呈现
    expect(find.byType(Scrollable), findsWidgets);
  });
}
