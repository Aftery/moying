// 用户反馈 4 项修复的回归测试：
// 1) 片长输入：文本通道 + onChanged 净化（搜狗组合输入兼容的钉子）
// 2) 导演自动挂演员第 0 位（失焦/回车同步、清空移除、删除不弹回）
// 3) 仪表盘卡片：单击进详情、长按进编辑
// 4) 个人页只读弹窗：签名非空必须渲染
// 5) 仪表盘空态点击直达新增页（书库/影库为空时）
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:moying/data/library_store.dart';
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
  group('片长输入过滤（onChanged 净化）', () {
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

    testWidgets('超过 4 位被截断', (tester) async {
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
      await tester
          .pumpWidget(_wrap(p, const Scaffold(body: DashboardScreen())));
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
      expect(find.text('修改书籍记录'), findsOneWidget);
    });

    testWidgets('长按电影卡片进入电影编辑页', (tester) async {
      final p = LibraryProvider();
      await tester
          .pumpWidget(_wrap(p, const Scaffold(body: DashboardScreen())));
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

  group('片长净化函数 sanitizeDurationInput', () {
    test('纯数字原样保留', () {
      expect(sanitizeDurationInput('169'), '169');
    });

    test('混入字母/符号/中文被过滤', () {
      expect(sanitizeDurationInput('a1b6c9!分'), '169');
    });

    test('超过 4 位截断', () {
      expect(sanitizeDurationInput('123456'), '1234');
    });

    test('全非数字结果为空串', () {
      expect(sanitizeDurationInput('分钟 minutes'), '');
    });
  });

  group('仪表盘空态点击直达新增页', () {
    /// 建一个空书影库（空集合 seed，保证四集合文件齐全）
    ///
    /// 真实 dart:io 的 await 在 testWidgets 默认 FakeAsync zone 下永不完成，
    /// 必须包在 [tester.runAsync]（真实异步 zone）里执行（同 media_pipeline_test）。
    Future<LibraryProvider> emptyLibrary(
      WidgetTester tester,
      Directory dir,
    ) async {
      final p = await tester.runAsync(() async {
        final store = LibraryStore(
          dir,
          seed: const LibrarySnapshot(books: [], movies: [], actors: []),
        );
        await store.load();
        await store.loadProfile();
        final p = LibraryProvider(store: store);
        await p.init();
        return p;
      });
      return p!;
    }

    testWidgets('书库为空：点击空态卡进入添加图书页', (tester) async {
      // 大视口让全部区块免滚动直接可见（规避 scrollUntilVisible 多滚动容器歧义）
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('moying_empty_book'),
      ))!;
      addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
      final p = await emptyLibrary(tester, dir);
      await tester
          .pumpWidget(_wrap(p, const Scaffold(body: DashboardScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.ensureVisible(find.text('书库空空'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('书库空空'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(BookEditScreen), findsOneWidget);
      // AppBar 标题 + 页内标题各渲染一份
      expect(find.text('添加图书'), findsWidgets);
    });

    testWidgets('影库为空：点击空态卡进入添加电影页', (tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('moying_empty_movie'),
      ))!;
      addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));
      final p = await emptyLibrary(tester, dir);
      await tester
          .pumpWidget(_wrap(p, const Scaffold(body: DashboardScreen())));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.ensureVisible(find.text('还没有电影记录'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('还没有电影记录'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(MovieEditScreen), findsOneWidget);
      expect(find.text('添加电影'), findsOneWidget);
    });
  });
}
