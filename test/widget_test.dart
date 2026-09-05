// 墨影 冒烟测试：验证应用可构建、导航切换与仪表盘核心元素渲染
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moying/main.dart';

void main() {
  testWidgets('应用启动并渲染仪表盘核心元素', (WidgetTester tester) async {
    await tester.pumpWidget(const MoYingApp());
    // 等待首帧与进度环动画完成
    await tester.pumpAndSettle();

    // 底部四个中文导航标签存在
    expect(find.text('仪表盘'), findsOneWidget);
    expect(find.text('书籍'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('个人'), findsOneWidget);

    // 统计卡片标题（kAllBooks.length=12, kMovieList.length=8；T5 起数据由真实列表聚合）
    expect(find.text('12 Books'), findsOneWidget);
    expect(find.text('8 Movies'), findsOneWidget);

    // 向下滚动到区块标题后断言（ListView 懒加载，视口外不渲染）
    final mainScrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('阅读列表'),
      200,
      scrollable: mainScrollable,
    );
    expect(find.text('阅读列表'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('我的电影'),
      200,
      scrollable: mainScrollable,
    );
    expect(find.text('我的电影'), findsOneWidget);
  });

  testWidgets('点击底部标签可切换页面', (WidgetTester tester) async {
    await tester.pumpWidget(const MoYingApp());
    await tester.pumpAndSettle();

    // 切到“个人”页
    await tester.tap(find.text('个人'));
    await tester.pumpAndSettle();
    expect(find.text('我的年度记录'), findsOneWidget);

    // 切回“仪表盘”
    await tester.tap(find.text('仪表盘'));
    await tester.pumpAndSettle();
    expect(find.text('12 Books'), findsOneWidget);
  });
}
