// 数据源自建部署指南（❓ 入口）测试：
// 1) 文案常量 kDataSourceDeployGuide 关键内容与用词（Base URL / 链接 / 路径）
// 2) showDataSourceGuideSheet 能弹出并渲染 Markdown，关闭按钮可收起
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moying/config/app_palette.dart';
import 'package:moying/config/app_theme.dart';
import 'package:moying/data/deploy_guide.dart';
import 'package:moying/widgets/data_source_guide_sheet.dart';

void main() {
  group('部署指南文案', () {
    test('包含关键步骤与链接', () {
      expect(kDataSourceDeployGuide, contains('simple-boot-douban-api'));
      expect(kDataSourceDeployGuide, contains('https://render.com'));
      expect(kDataSourceDeployGuide, contains('https://uptimerobot.com'));
      expect(kDataSourceDeployGuide, contains('Singapore'));
      expect(kDataSourceDeployGuide, contains('Dockerfile'));
      expect(kDataSourceDeployGuide, contains('COOKIE'));
    });

    test('绑定步骤用「Base URL」而非「自定义 API 服务地址」', () {
      expect(kDataSourceDeployGuide, contains('Base URL'));
      // 需求 #3：旧文案不得残留，避免与 App 实际字段名不一致
      expect(kDataSourceDeployGuide, isNot(contains('自定义 API 服务地址')));
    });

    test('引导路径与实际 UI 一致（个人 → 数据源管理）', () {
      expect(kDataSourceDeployGuide, contains('个人'));
      expect(kDataSourceDeployGuide, contains('数据源管理'));
      expect(kDataSourceDeployGuide, contains('添加书籍数据源'));
    });

    test('代码块围栏成对闭合（避免 Markdown 渲染成普通文本）', () {
      final fences =
          RegExp('```').allMatches(kDataSourceDeployGuide).length;
      expect(fences, greaterThan(0));
      expect(fences.isEven, isTrue, reason: '``` 围栏必须成对');
    });
  });

  group('部署指南弹层', () {
    Future<void> pumpAndOpen(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(AppPalette.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDataSourceGuideSheet(context),
                child: const Text('打开指南'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('打开指南'));
      await tester.pumpAndSettle();
    }

    testWidgets('弹出后渲染 Markdown 与标题', (tester) async {
      await pumpAndOpen(tester);

      expect(find.text('数据源配置教程'), findsOneWidget);
      expect(find.byType(Markdown), findsOneWidget);
      // 文首 H1 在可视区，应已构建（selectable 下走 RichText）
      expect(
        find.textContaining('自建部署指南', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('点关闭按钮可收起弹层', (tester) async {
      await pumpAndOpen(tester);
      expect(find.text('数据源配置教程'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('数据源配置教程'), findsNothing);
    });
  });
}
