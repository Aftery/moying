// 用户反馈 4 项修复的回归测试：
// 1) 片长输入：digitsOnly 过滤（搜狗数字键盘兼容修复的钉子）
// 2) 导演自动挂演员第 0 位（失焦/回车同步、清空移除、删除不弹回）
// 3) 仪表盘卡片：单击进详情、长按进编辑
// 4) 个人页只读弹窗：签名非空必须渲染
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:moying/models/user_profile.dart';
import 'package:moying/providers/library_provider.dart';
import 'package:moying/screens/book_edit_screen.dart';
import 'package:moying/screens/dashboard_screen.dart';
import 'package:moying/screens/movie_edit_screen.dart';
import 'package:moying/screens/profile_screen.dart';
import 'package:moying/widgets/grid_item_card.dart';

/// 单屏包裹：注入内存模式 provider，home 作为可 pop 的根路由
Widget _wrap(LibraryProvider provider, Widget home) {
  return ChangeNotifierProvider.value(
    value: provider,
    child: MaterialApp(home: home),
  );
}

/// 片长输入框（hintText 定位，避免与标题/导演等 TextField 混淆）
Finder _durationField() => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == '如 169',
    );

/// 编辑页导演输入框（labelText 定位）
Finder _directorField() => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == '导演',
    );

/// 演员槽位中文本为 [name] 的输入框（hint 区分，避免命中导演框本身）
Finder _actorSlotWith(String name) => find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.hintText == '输入姓名联想选择或新建' &&
          w.controller?.text == name,
    );

/// 新增模式保存按钮（与 AppBar「添加电影」不重名的 InkWell）
Finder _saveButton() => find.ancestor(
      of: find.text('保存'),
      matching: find.byType(InkWell),
    );

void main() {
  group('片长输入过滤（digitsOnly）', () {
    testWidgets('输入纯数字正常进入', (tester) async {
      final p = LibraryProvider();
      await tester.pumpWidget(_wrap(p, const MovieEditScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(_durationField(), '169');
      await tester.pump();
      expect(
        tester.widget<TextField>(_durationField()).controller!.text,
        '169',
      );
    });

    testWidgets('混入字母/符号被过滤，只剩数字', (tester) async {
      final p = LibraryProvider();
      await tester.pumpWidget(_wrap(p, const MovieEditScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(_durationField(), 'a1b6c9!');
      await tester.pump();
      expect(
        tester.widget<TextField>(_durationField()).controller!.text,
        '169',
      );
    });

    testWidgets('超过 4 位被截断（LengthLimiting）', (tester) async {
      final p = LibraryProvider();
      await tester.pumpWidget(_wrap(p, const MovieEditScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(_durationField(), '123456');
      await tester.pump();
      expect(
        tester.widget<TextField>(_durationField()).controller!.text,
        '1234',
      );
    });
  });

  group('导演自动挂演员第 0 位', () {
    testWidgets('导演失焦后自动槽插入演员区首位，保存兜底新建演员', (tester) async {
      final p = LibraryProvider();
      await tester.pumpWidget(_wrap(p, const MovieEditScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '同步测试片');
      await tester.enterText(_directorField(), '诺兰');
      // 失焦触发同步（焦点移到标题框外 → receiveAction 收键盘即失焦）
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 演员区出现"诺兰"槽位（自动挂载）
      expect(_actorSlotWith('诺兰'), findsOneWidget);

      // 保存 → 兜底新建同名演员并关联
      await tester.ensureVisible(_saveButton());
      await tester.tap(_saveButton());
      await tester.pumpAndSettle();

      final movie = p.movieList.firstWhere((m) => m.title == '同步测试片');
      expect(movie.actorIds, isNotEmpty);
      expect(p.actors.any((a) => a.name == '诺兰'), isTrue);
    });

    testWidgets('清空导演后失焦，自动槽被移除', (tester) async {
      final p = LibraryProvider();
      await tester.pumpWidget(_wrap(p, const MovieEditScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(_directorField(), '诺兰');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_actorSlotWith('诺兰'), findsOneWidget);

      // 清空导演 → 失焦 → 自动槽移除
      await tester.enterText(_directorField(), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_actorSlotWith('诺兰'), findsNothing);
    });

    testWidgets('手动删除自动槽后，同导演不再弹回', (tester) async {
      final p = LibraryProvider();
      await tester.pumpWidget(_wrap(p, const MovieEditScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(_directorField(), '诺兰');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // 删除自动槽（tooltip「移除」；先滚进视口）
      await tester.ensureVisible(find.byTooltip('移除'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('移除'));
      await tester.pumpAndSettle();
      expect(_actorSlotWith('诺兰'), findsNothing);

      // 导演框再失焦 → 不弹回
      await tester.enterText(_directorField(), '诺兰编辑后');
      await tester.enterText(_directorField(), '诺兰');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(_actorSlotWith('诺兰'), findsNothing);
    });

    testWidgets('编辑模式回填：导演与演员不同名时自动补挂', (tester) async {
      final p = LibraryProvider();
      final base = p.movieList.firstWhere((m) => m.director != null);
      // 导演与现有演员无同名
      await tester.pumpWidget(_wrap(p, MovieEditScreen(movieId: base.id)));
      await tester.pumpAndSettle();

      expect(
        _actorSlotWith(base.director!),
        findsOneWidget,
      );
    });
  });

  group('仪表盘卡片交互', () {
    testWidgets('长按阅读列表卡片进入图书编辑页', (tester) async {
      final p = LibraryProvider();
      // 仪表盘依赖外层 Scaffold 的 Material（MainShell 提供），测试里补齐
      await tester.pumpWidget(_wrap(p, const Scaffold(body: DashboardScreen())));
      await tester.pumpAndSettle();

      final book = p.readingList.first;
      // 限定网格卡片内的标题（排除「当前任务」横滑区的同名项）；
      // 滚动阶段不能带 .first（懒列表未 build 时 .first 会抛 No element）
      final cardInGrid = find.descendant(
        of: find.byType(GridItemCard),
        matching: find.text(book.title),
      );
      await tester.scrollUntilVisible(
        cardInGrid,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // 滚到 build 后再 ensureVisible：cacheExtent 里 build≠可见，需真正滚进视口
      await tester.ensureVisible(cardInGrid.first);
      await tester.pumpAndSettle();
      await tester.longPress(cardInGrid.first);
      await tester.pumpAndSettle();

      expect(find.byType(BookEditScreen), findsOneWidget);
      expect(find.text('编辑图书'), findsOneWidget);
    });

    testWidgets('长按电影卡片进入电影编辑页', (tester) async {
      final p = LibraryProvider();
      await tester.pumpWidget(_wrap(p, const Scaffold(body: DashboardScreen())));
      await tester.pumpAndSettle();

      final movie = p.movieList.first;
      final cardInGrid = find.descendant(
        of: find.byType(GridItemCard),
        matching: find.text(movie.title),
      );
      await tester.scrollUntilVisible(
        cardInGrid,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      // 滚到 build 后再 ensureVisible：cacheExtent 里 build≠可见，需真正滚进视口
      await tester.ensureVisible(cardInGrid.first);
      await tester.pumpAndSettle();
      await tester.longPress(cardInGrid.first);
      await tester.pumpAndSettle();

      expect(find.byType(MovieEditScreen), findsOneWidget);
      expect(find.text('修改电影'), findsOneWidget);
    });
  });

  group('个人页只读弹窗', () {
    testWidgets('签名非空时弹窗内必须渲染', (tester) async {
      final p = LibraryProvider();
      await p.updateProfile(const UserProfile(
        nickname: '书友',
        signature: '读万卷书·行万里路',
      ));
      await tester.pumpWidget(_wrap(p, const ProfileScreen()));
      await tester.pumpAndSettle();

      // 点头像卡弹只读面板
      await tester.tap(find.text('书友').first);
      await tester.pumpAndSettle();

      // 卡片上 + 弹窗内各渲染一份
      expect(find.text('读万卷书·行万里路'), findsNWidgets(2));
    });
  });
}
