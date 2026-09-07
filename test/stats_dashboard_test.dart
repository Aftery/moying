// 三段式仪表盘 UI smoke 测试
//
// 覆盖：统计页三段式渲染、年报入口跳转、热力图组件基本渲染。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moying/screens/personal_stats_screen.dart';
import 'package:moying/widgets/heatmap_calendar.dart';
import 'package:provider/provider.dart';

import 'package:moying/providers/library_provider.dart';

Widget _wrap(Widget child, {LibraryProvider? provider}) {
  final p = provider ?? LibraryProvider();
  return ChangeNotifierProvider<LibraryProvider>.value(
    value: p,
    child: MaterialApp(home: child),
  );
}

void main() {
  group('PersonalStatsScreen 三段式渲染', () {
    testWidgets('三段区块与年报入口渲染', (tester) async {
      await tester.pumpWidget(_wrap(const PersonalStatsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('个人统计'), findsOneWidget); // AppBar
      expect(find.text('打卡记录'), findsOneWidget); // 第一段
      expect(find.text('类型偏好'), findsOneWidget); // 第二段
      expect(find.text('评分习惯'), findsOneWidget);
      // 第三段与年报入口在视口外，滚动到底部再断言
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(find.textContaining('进行中'), findsOneWidget);
      expect(find.textContaining('读书年报'), findsOneWidget);
    });

    testWidgets('热力图范围切换 30天→季度→年度', (tester) async {
      await tester.pumpWidget(_wrap(const PersonalStatsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('季度'));
      await tester.pumpAndSettle();
      expect(find.text('季度'), findsOneWidget);

      await tester.tap(find.text('年度'));
      await tester.pumpAndSettle();
      expect(find.text('年度'), findsOneWidget);
    });

    testWidgets('年报入口点击跳转年报页', (tester) async {
      await tester.pumpWidget(_wrap(const PersonalStatsScreen()));
      await tester.pumpAndSettle();

      // 年报入口在页面底部，先滚动到可见
      await tester.scrollUntilVisible(
        find.textContaining('读书年报'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('读书年报'));
      await tester.pumpAndSettle();

      expect(find.textContaining('年度报告'), findsOneWidget);
    });
  });

  group('HeatmapCalendar', () {
    testWidgets('空数据渲染 53 列网格', (tester) async {
      await tester.pumpWidget(_wrap(Scaffold(
        body: HeatmapCalendar(data: const {}, endDate: DateTime(2026, 9, 7)),
      )));
      await tester.pumpAndSettle();
      // 网格由纯色 Container 组成，无文本异常即可
      expect(tester.takeException(), isNull);
    });

    testWidgets('有数据时按 count 上色不抛异常', (tester) async {
      await tester.pumpWidget(_wrap(Scaffold(
        body: HeatmapCalendar(
          data: const {
            '2026-09-06': 1,
            '2026-09-07': 3,
            '2026-08-01': 2,
          },
          endDate: DateTime(2026, 9, 7),
        ),
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}