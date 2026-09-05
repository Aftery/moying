// 仪表盘跳转 + 筛选「全部」项回归测试
//
// 覆盖 2026-09-05 修复的两个问题：
// 1. 仪表盘「查看全部」接通底部 Tab 跳转（此前 trailing 无点击处理）
// 2. 书籍「全部状态」/电影「全部类型」失效——_FilterDropdown 的非空 guard
//    把 value=null 的「全部」项吞掉（回归钉死：选中具体项后必须能选回全部）
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moying/main.dart';
import 'package:moying/widgets/section_header.dart';

void main() {
  group('仪表盘「查看全部」跳转', () {
    testWidgets('阅读列表「查看全部」→ 切到书籍 Tab', (tester) async {
      await tester.pumpWidget(const MoYingApp());
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('阅读列表'),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      // 只点「阅读列表」区块头里的入口，避免命中下方电影区块的同名文案
      final booksHeader = find.ancestor(
        of: find.text('阅读列表'),
        matching: find.byType(SectionHeader),
      );
      await tester.tap(
        find.descendant(of: booksHeader, matching: find.text('查看全部')),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(navBar.selectedIndex, 1);
    });

    testWidgets('我的电影「查看全部」→ 切到电影 Tab', (tester) async {
      await tester.pumpWidget(const MoYingApp());
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('我的电影'),
        200,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      final moviesHeader = find.ancestor(
        of: find.text('我的电影'),
        matching: find.byType(SectionHeader),
      );
      await tester.tap(
        find.descendant(of: moviesHeader, matching: find.text('查看全部')),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(navBar.selectedIndex, 2);
    });
  });

  group('筛选「全部」项可恢复全量', () {
    testWidgets('书籍：选「在读」过滤后再选「全部状态」恢复 12 本', (tester) async {
      await tester.pumpWidget(const MoYingApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('书籍'));
      await tester.pumpAndSettle();
      expect(find.text('共 12 本'), findsOneWidget);

      // 打开状态下拉（关闭态按钮文案即「全部状态」），选「在读」
      await tester.tap(find.text('全部状态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('在读').last); // .last = 菜单项（.first 是按钮）
      await tester.pumpAndSettle();
      expect(find.text('共 12 本'), findsNothing);

      // 从「在读」选回「全部状态」——修复前这里被非空 guard 吞掉，永远回不去
      await tester.tap(find.text('在读').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部状态').last);
      await tester.pumpAndSettle();
      expect(find.text('共 12 本'), findsOneWidget);
    });

    testWidgets('电影：选「科幻」过滤后再选「全部类型」恢复 8 部', (tester) async {
      await tester.pumpWidget(const MoYingApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('电影'));
      await tester.pumpAndSettle();
      expect(find.text('共 8 部'), findsOneWidget);

      await tester.tap(find.text('全部类型'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('科幻').last);
      await tester.pumpAndSettle();
      expect(find.text('共 8 部'), findsNothing);

      await tester.tap(find.text('科幻').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部类型').last);
      await tester.pumpAndSettle();
      expect(find.text('共 8 部'), findsOneWidget);
    });
  });
}
