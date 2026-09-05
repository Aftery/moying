// P4.5 电影剧情类型「联想输入 + 多选标签」测试
//
// 覆盖三条核心用例：
// 1) 点选候选成标签 → 保存落 genres（预设 ∪ 已用类型为候选源）
// 2) 自定义类型回车成标签（哨兵/直接提交两条路都收口于 _commitGenreText）
// 3) 删除已选标签 → 保存后 genres 同步移除；自定义类型进入 usedMovieGenres 可筛
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:moying/providers/library_provider.dart';
import 'package:moying/screens/movie_edit_screen.dart';

/// 单屏包裹：注入内存模式 provider，home 作为可 pop 的根路由
Widget _wrap(LibraryProvider provider, Widget home) {
  return ChangeNotifierProvider.value(
    value: provider,
    child: MaterialApp(home: home),
  );
}

/// 剧情类型输入框（hintText 定位，避免与标题等 TextField 混淆）
Finder _genreField() => find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.hintText == '输入或选择类型，回车添加（可多选）',
    );

/// 编辑页保存按钮：新增「保存」/ 编辑「保存修改」，substring 双兼容
Finder _saveButton() => find.ancestor(
      of: find.textContaining('保存'),
      matching: find.byType(InkWell),
    );

void main() {
  group('剧情类型联想输入 + 多选标签', () {
    testWidgets('点选候选「科幻」成标签，保存后落入 genres', (tester) async {
      // 放大视口，保证联想浮层天然在屏内（浮层点选几何换算在小视口不可靠）
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final p = LibraryProvider();
      await tester.pumpWidget(_wrap(p, const MovieEditScreen()));
      await tester.pumpAndSettle();

      // 上滑把类型输入框抬离视口底边，给下方联想浮层留展开空间
      await tester.ensureVisible(_genreField());
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '类型测试片');
      await tester.enterText(_genreField(), '科');
      await tester.pumpAndSettle();

      // 浮层出现包含匹配候选，点选「科幻」
      await tester.tap(find.text('科幻').last);
      await tester.pumpAndSettle();

      // 标签已选：输入框被清空，已选 chip 出现
      expect(find.byType(InputChip), findsOneWidget);
      expect(find.text('科幻'), findsWidgets);

      await tester.ensureVisible(_saveButton());
      await tester.tap(_saveButton());
      await tester.pumpAndSettle();

      final saved = p.movieList.last;
      expect(saved.title, '类型测试片');
      expect(saved.genres, contains('科幻'));
      // 自定义来源会进入 usedMovieGenres，供列表筛选与后续联想
      expect(p.usedMovieGenres, contains('科幻'));
    });

    testWidgets('自定义类型回车直接成标签，无需候选命中', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final p = LibraryProvider();
      await tester.pumpWidget(_wrap(p, const MovieEditScreen()));
      await tester.pumpAndSettle();

      // 上滑给浮层留空间
      await tester.ensureVisible(_genreField());
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -260));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '自定义类型片');
      await tester.enterText(_genreField(), '武侠');
      await tester.pumpAndSettle();

      // 无候选命中 → 「添加」哨兵行出现（浮层非空入口）
      expect(find.textContaining('添加「武侠」'), findsOneWidget);

      // 回车提交（TextInputAction.done）
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(InputChip), findsOneWidget);
      expect(find.widgetWithText(InputChip, '武侠'), findsOneWidget);

      await tester.ensureVisible(_saveButton());
      await tester.tap(_saveButton());
      await tester.pumpAndSettle();

      final saved = p.movieList.last;
      expect(saved.genres, contains('武侠'));
      expect(p.usedMovieGenres, contains('武侠'));
    });

    testWidgets('编辑模式删除已选标签，保存后 genres 同步移除', (tester) async {
      final p = LibraryProvider();
      // m3 星际穿越：genres = [科幻, 冒险, 悬疑]
      await tester.pumpWidget(_wrap(p, const MovieEditScreen(movieId: 'm3')));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, '科幻'), findsOneWidget);
      expect(find.widgetWithText(InputChip, '冒险'), findsOneWidget);

      // 删掉「科幻」标签（RawChip 删除按钮走稳定 API：默认 tooltip「Delete」，
      // 不用 byIcon —— 内部图标常量是私有 IconData，公开 Icons.cancel 不保证相等）
      final chip = find.widgetWithText(InputChip, '科幻');
      final deleteIcon = find.descendant(
        of: chip,
        matching: find.byTooltip('Delete'),
      );
      await tester.ensureVisible(deleteIcon);
      await tester.tap(deleteIcon);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InputChip, '科幻'), findsNothing);

      await tester.ensureVisible(_saveButton());
      await tester.tap(_saveButton());
      await tester.pumpAndSettle();

      final saved = p.movieList.firstWhere((m) => m.id == 'm3');
      expect(saved.genres, isNot(contains('科幻')));
      expect(saved.genres, containsAll(['冒险', '悬疑']));
    });
  });
}
