// 图书模块交互流程测试：列表渲染 / 详情导航 / 编辑保存 / 删除确认
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:moying/data/mock_data.dart';
import 'package:moying/main.dart';
import 'package:moying/models/book.dart';
import 'package:moying/providers/library_provider.dart';
import 'package:moying/screens/book_detail_screen.dart';
import 'package:moying/screens/book_edit_screen.dart';
import 'package:moying/screens/books_screen.dart';
import 'package:moying/widgets/book_list_card.dart';
import 'package:moying/widgets/search_bar_widget.dart';

void main() {
  group('图书列表页', () {
    testWidgets('切换到书籍 Tab：渲染搜索栏 / 筛选下拉 / 双排网格', (tester) async {
      await tester.pumpWidget(const MoYingApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('书籍'));
      await tester.pumpAndSettle();

      // 顶部搜索栏与结果计数
      expect(find.byType(SearchBarWidget), findsOneWidget);
      expect(find.text('共 12 本'), findsOneWidget);
      // 网格卡片已渲染（懒加载，首行即可见）
      expect(find.byType(BookListCard), findsWidgets);
    });

    testWidgets('单击卡片进入详情页，返回后回到列表', (tester) async {
      await tester.pumpWidget(const MoYingApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('书籍'));
      await tester.pumpAndSettle();

      final firstCard = find.byType(BookListCard).first;
      await tester.ensureVisible(firstCard);
      await tester.pumpAndSettle();
      await tester.tap(firstCard);
      await tester.pumpAndSettle();

      // 详情页出现：大进度卡「阅读进度」+ 编辑入口
      expect(find.byType(BookDetailScreen), findsOneWidget);
      expect(find.text('阅读进度'), findsOneWidget);

      // 返回列表
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(BooksScreen), findsOneWidget);
    });

    testWidgets('搜索可实时过滤列表', (tester) async {
      await tester.pumpWidget(const MoYingApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('书籍'));
      await tester.pumpAndSettle();

      // 用第一本书的书名关键字搜索
      final target = kAllBooks.first.title;
      await tester.enterText(find.byType(TextField).first, target);
      await tester.pumpAndSettle();

      expect(find.text('共 1 本'), findsOneWidget);
      expect(find.byType(BookListCard), findsOneWidget);
    });
  });

  group('编辑页交互', () {
    // 宿主：可直接 push 编辑页并持有同一 Provider 实例做断言
    Future<LibraryProvider> pumpEditor(WidgetTester tester) async {
      final provider = LibraryProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            BookEditScreen(bookId: kAllBooks.first.id),
                      ),
                    ),
                    child: const Text('打开编辑页'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开编辑页'));
      await tester.pumpAndSettle();
      expect(find.byType(BookEditScreen), findsOneWidget);
      return provider;
    }

    testWidgets('修改书名并保存：Provider 同步更新', (tester) async {
      final provider = await pumpEditor(tester);
      final oldTitle = provider.books.first.title;

      await tester.enterText(find.byType(TextField).first, '重命名后的书');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存修改'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存修改'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // 已返回宿主页
      expect(find.byType(BookEditScreen), findsNothing);
      expect(find.text('打开编辑页'), findsOneWidget);
      // Provider 中该书标题已更新
      final updated =
          provider.books.firstWhere((b) => b.id == kAllBooks.first.id);
      expect(updated.title, '重命名后的书');
      expect(oldTitle, isNot('重命名后的书'));
    });

    testWidgets('书名留空时保存被拦截并提示', (tester) async {
      final provider = await pumpEditor(tester);
      // 只清空书名，作者保留
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存修改'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存修改'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('书名与作者不能为空'), findsOneWidget);
      // 仍在编辑页，未保存
      expect(find.byType(BookEditScreen), findsOneWidget);
      expect(provider.books.first.title, isNot(''));
    });

    testWidgets('删除图书需二次确认：确认后移除并返回', (tester) async {
      final provider = await pumpEditor(tester);
      final id = kAllBooks.first.id;

      await tester.ensureVisible(find.text('删除图书'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除图书'));
      await tester.pumpAndSettle();

      // 确认对话框
      expect(find.text('删除这本书？'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      // 已删除并返回宿主
      expect(find.byType(BookEditScreen), findsNothing);
      expect(provider.books.map((b) => b.id), isNot(contains(id)));
      expect(provider.books.length, 11);
    });

    testWidgets('删除对话框点取消：不删书不退出', (tester) async {
      final provider = await pumpEditor(tester);

      await tester.ensureVisible(find.text('删除图书'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除图书'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(find.byType(BookEditScreen), findsOneWidget);
      expect(provider.books.length, 12);
    });
  });

  group('新增图书', () {
    // 宿主：push 新增模式编辑页（不传 bookId），持有同一 Provider 实例做断言
    Future<LibraryProvider> pumpCreator(WidgetTester tester) async {
      final provider = LibraryProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BookEditScreen(),
                      ),
                    ),
                    child: const Text('打开新增页'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开新增页'));
      await tester.pumpAndSettle();
      expect(find.byType(BookEditScreen), findsOneWidget);
      return provider;
    }

    testWidgets('新增模式：AppBar「添加图书」，无删除按钮', (tester) async {
      await pumpCreator(tester);

      // AppBar 与保存按钮共用「添加图书」文案 → 恰好 2 处
      expect(find.text('添加图书'), findsNWidgets(2));
      // 新增模式不显示删除入口
      expect(find.text('删除图书'), findsNothing);
    });

    testWidgets('列表页 FAB 点击进入新增模式', (tester) async {
      await tester.pumpWidget(const MoYingApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('书籍'));
      await tester.pumpAndSettle();

      // 列表页 AppBar 标题是「书籍」，FAB「添加图书」唯一
      expect(find.text('添加图书'), findsOneWidget);
      await tester.tap(find.text('添加图书'));
      await tester.pumpAndSettle();

      expect(find.byType(BookEditScreen), findsOneWidget);
      // 新增模式特征：无删除按钮
      expect(find.text('删除图书'), findsNothing);
    });

    testWidgets('填表保存：Provider 新增一条且字段正确', (tester) async {
      final provider = await pumpCreator(tester);
      final before = provider.books.length;

      await tester.enterText(find.byType(TextField).first, '测试新书');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(1), '测试作者');
      await tester.pumpAndSettle();
      // 联网检索上线后字段顺序：书名/作者/ISBN/总页数/分类
      await tester.enterText(find.byType(TextField).at(3), '500');
      await tester.pumpAndSettle();

      // 保存按钮：AppBar 标题与按钮文案重名，且 Scaffold 遍历顺序 body 在 appBar 前，
      // 不能用 .last 区分 —— 用 InkWell 祖先唯一定位真实按钮
      final saveBtn =
          find.ancestor(of: find.text('添加图书'), matching: find.byType(InkWell));
      expect(saveBtn, findsOneWidget);
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn, warnIfMissed: false);
      await tester.pumpAndSettle();

      // 已返回宿主页
      expect(find.byType(BookEditScreen), findsNothing);
      // 数量 +1，新书插入列表头部
      expect(provider.books.length, before + 1);
      final added = provider.books.first;
      expect(added.title, '测试新书');
      expect(added.author, '测试作者');
      expect(added.totalPages, 500);
      expect(added.currentPage, 0);
      // 进度 0 → 想读
      expect(added.status, BookStatus.planToRead);
      expect(added.id, startsWith('b_'));
    });

    testWidgets('书名留空保存被拦截：不退出不新增', (tester) async {
      final provider = await pumpCreator(tester);
      final before = provider.books.length;

      // 只填作者
      await tester.enterText(find.byType(TextField).at(1), '只有作者');
      await tester.pumpAndSettle();
      final saveBtn =
          find.ancestor(of: find.text('添加图书'), matching: find.byType(InkWell));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('书名与作者不能为空'), findsOneWidget);
      expect(find.byType(BookEditScreen), findsOneWidget);
      expect(provider.books.length, before);
    });

    testWidgets('分类输入联想已有分类：包含匹配 + 点选回填保存', (tester) async {
      // 放大测试视口：分类字段与联想浮层（OverlayPortal 根 overlay + follower 变换）
      // 天然位于屏内，避免滚动联动下浮层点选的几何换算问题
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final provider = await pumpCreator(tester);

      // 分类字段是第 5 个 TextField（书名/作者/ISBN/总页数之后）
      final categoryField = find.byType(TextField).at(4);
      await tester.enterText(categoryField, '幻');
      await tester.pumpAndSettle();

      // 包含匹配：联想出含「幻」的预设分类；不含的不出现
      expect(find.text('奇幻'), findsWidgets);
      expect(find.text('魔幻现实主义'), findsWidgets);
      expect(find.text('历史'), findsNothing);

      // 点选建议项回填输入框（浮层跟随字段，先滚动到可见）
      final suggestion = find.text('奇幻');
      await tester.ensureVisible(suggestion);
      await tester.pumpAndSettle();
      await tester.tap(suggestion, warnIfMissed: false);
      await tester.pumpAndSettle();

      // 补齐必填项后保存，category 应为点选的联想值
      await tester.enterText(find.byType(TextField).first, '联想选书');
      await tester.enterText(find.byType(TextField).at(1), '作者甲');
      final saveBtn =
          find.ancestor(of: find.text('添加图书'), matching: find.byType(InkWell));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(BookEditScreen), findsNothing);
      expect(provider.books.first.category, '奇幻');
    });

    testWidgets('自定义分类直接保存：写入自定义值并进入联想候选', (tester) async {
      final provider = await pumpCreator(tester);

      await tester.enterText(find.byType(TextField).first, '自定义分类的书');
      await tester.enterText(find.byType(TextField).at(1), '作者乙');
      await tester.enterText(find.byType(TextField).at(4), '科幻硬核');
      await tester.pumpAndSettle();

      final saveBtn =
          find.ancestor(of: find.text('添加图书'), matching: find.byType(InkWell));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.byType(BookEditScreen), findsNothing);
      expect(provider.books.first.category, '科幻硬核');
      // 自定义分类经 usedCategories 自动进入联想候选与筛选下拉
      expect(provider.usedCategories, contains('科幻硬核'));
    });
  });

  group('列表长按入口', () {
    testWidgets('长按卡片唤起编辑页', (tester) async {
      await tester.pumpWidget(const MoYingApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('书籍'));
      await tester.pumpAndSettle();

      final firstCard = find.byType(BookListCard).first;
      await tester.ensureVisible(firstCard);
      await tester.pumpAndSettle();
      await tester.longPress(firstCard);
      await tester.pumpAndSettle();

      expect(find.byType(BookEditScreen), findsOneWidget);
      expect(find.text('编辑图书'), findsOneWidget);
    });
  });

  group('阅读时间', () {
    // 宿主：push 指定书的编辑页并持有同一 Provider 实例做断言
    Future<LibraryProvider> pumpEditOf(
      WidgetTester tester,
      String bookId,
    ) async {
      final provider = LibraryProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BookEditScreen(bookId: bookId),
                      ),
                    ),
                    child: const Text('打开编辑页'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开编辑页'));
      await tester.pumpAndSettle();
      expect(find.byType(BookEditScreen), findsOneWidget);
      return provider;
    }

    // 宿主：新增模式编辑页
    Future<LibraryProvider> pumpAdd(WidgetTester tester) async {
      final provider = LibraryProvider();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const BookEditScreen()),
                    ),
                    child: const Text('打开新增页'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开新增页'));
      await tester.pumpAndSettle();
      expect(find.byType(BookEditScreen), findsOneWidget);
      return provider;
    }

    String ymd(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    // 沙丘 b1：在读，startedAt 2026-02-15，无 finishedAt
    testWidgets('在读书显示开始时间与区块，无完成时间行', (tester) async {
      await pumpEditOf(tester, kAllBooks.first.id);

      expect(find.text('阅读时间'), findsOneWidget);
      expect(find.text('2026-02-15'), findsOneWidget); // 开始时间原值
      expect(find.text('阅读完成'), findsNothing); // 未完成不显示
      expect(find.text('保存修改'), findsOneWidget);
    });

    // b12 嫌疑人X：想读，仅 createdAt
    testWidgets('想读书隐藏整个阅读时间区块', (tester) async {
      await pumpEditOf(tester, kAllBooks.last.id);

      expect(find.text('阅读时间'), findsNothing);
      expect(find.text('2026-08-30'), findsNothing); // createdAt 不作为开始时间展示
    });

    // 已读完的 1984 b4：finishedAt 2025-10-18
    testWidgets('已读书显示完成时间行', (tester) async {
      final provider = await pumpEditOf(tester, kAllBooks[3].id);

      expect(find.text('阅读时间'), findsOneWidget);
      expect(find.text('2025-10-18'), findsOneWidget);
      await tester.ensureVisible(find.text('保存修改'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存修改'), warnIfMissed: false);
      await tester.pumpAndSettle();
      final saved = provider.books.firstWhere((b) => b.id == kAllBooks[3].id);
      expect(saved.finishedAt, DateTime(2025, 10, 18));
    });

    testWidgets('新增拉满进度：完成时间自动填今天、开始时间=添加时间', (tester) async {
      final provider = await pumpAdd(tester);

      await tester.enterText(find.byType(TextField).at(0), '时间测试书');
      await tester.enterText(find.byType(TextField).at(1), '作者');
      await tester.pumpAndSettle();

      final slider = find.byType(Slider);
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      // 新增书 thumb 在轨道最左：从端点起拖，越过右边界钳制到 100%
      final rect = tester.getRect(slider);
      await tester.dragFrom(
        Offset(rect.left + 4, rect.center.dy),
        Offset(rect.width + 80, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget); // 拖动确实钳制到满进度

      final today = ymd(DateTime.now());
      expect(find.text('阅读完成'), findsOneWidget);
      expect(find.text(today), findsWidgets); // 完成时间 = 今天

      // 保存：直接定位底部保存按钮（AppBar 标题同名文案不可点）
      final saveBtn =
          find.ancestor(of: find.text('添加图书'), matching: find.byType(InkWell));
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn, warnIfMissed: false);
      await tester.pumpAndSettle();

      final added = provider.books.first;
      expect(added.finishedAt, isNotNull);
      expect(ymd(added.finishedAt!), today);
      // 进度拉满开始时间自动补为添加时间（同一天）
      expect(ymd(added.startedAt!), today);
    });

    testWidgets('已读书拖回进度：确认后清除完成记录', (tester) async {
      final provider = await pumpEditOf(tester, kAllBooks[3].id); // 1984

      final slider = find.byType(Slider);
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      // 已读书 thumb 在轨道最右（100%）：从端点向左拖约半轨 → 进度降到在读区间
      final rect = tester.getRect(slider);
      await tester.dragFrom(
        Offset(rect.right - 4, rect.center.dy),
        Offset(-rect.width * 0.55, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('回退阅读进度？'), findsOneWidget);
      await tester.tap(find.text('确认回退'));
      await tester.pumpAndSettle();

      expect(find.text('阅读完成'), findsNothing); // 完成行随进度隐藏

      await tester.ensureVisible(find.text('保存修改'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存修改'), warnIfMissed: false);
      await tester.pumpAndSettle();
      final saved = provider.books.firstWhere((b) => b.id == kAllBooks[3].id);
      expect(saved.status, BookStatus.reading);
      expect(saved.finishedAt, isNull);
      expect(saved.currentPage, lessThan(saved.totalPages));
    });

    testWidgets('已读书拖回进度：取消则进度保持完成态', (tester) async {
      await pumpEditOf(tester, kAllBooks[3].id); // 1984

      final slider = find.byType(Slider);
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final rect = tester.getRect(slider);
      await tester.dragFrom(
        Offset(rect.right - 4, rect.center.dy),
        Offset(-rect.width * 0.55, 0),
      );
      await tester.pumpAndSettle();

      expect(find.text('回退阅读进度？'), findsOneWidget);
      // dialog 内「取消」（与底部按钮区分作用域）
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('取消'),
      ));
      await tester.pumpAndSettle();

      // 进度回弹 100%，完成记录保留
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('阅读完成'), findsOneWidget);
      expect(find.text('2025-10-18'), findsOneWidget);
    });
  });
}
