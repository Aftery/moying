// P3 书籍作者内链：详情页点作者 → 书库新实例按作者预填过滤
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:moying/providers/library_provider.dart';
import 'package:moying/screens/book_detail_screen.dart';
import 'package:moying/screens/books_screen.dart';

void main() {
  testWidgets('详情页点作者 → 书库按作者过滤出全部同作者书目', (tester) async {
    final p = LibraryProvider();
    // 打开《三体》（b6，作者刘慈欣；mock 里另有一本《三体Ⅱ：黑暗森林》b3）
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: p,
      child: const MaterialApp(home: BookDetailScreen(bookId: 'b6')),
    ));
    await tester.pumpAndSettle();

    // 点作者行（manage_search 图标仅作者行使用）
    expect(find.text('刘慈欣'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.manage_search_rounded));
    await tester.pumpAndSettle();

    // 新 BooksScreen 实例按作者预填过滤：刘慈欣共 2 本
    expect(find.byType(BooksScreen), findsOneWidget);
    expect(find.text('共 2 本'), findsOneWidget);
    expect(find.text('三体'), findsOneWidget);
    expect(find.text('三体Ⅱ：黑暗森林'), findsOneWidget);
  });

  testWidgets('搜索框预填作者名，且不污染书库数据', (tester) async {
    final p = LibraryProvider();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: p,
      child: const MaterialApp(home: BookDetailScreen(bookId: 'b6')),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.manage_search_rounded));
    await tester.pumpAndSettle();

    // 过滤的是展示层 query，底层书库全量不变
    expect(p.books.length, 12);
    // 返回后详情页仍在
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailScreen), findsOneWidget);
  });
}
