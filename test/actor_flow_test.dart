// P3 电影×演员内链闭环测试
//
// 覆盖四条被讨论钉死的用例骨架：
// 1) 详情页渲染：actorIds 必须经 actorsByIds 解析成名字（id≠name 实体不乱码）
// 2) 编辑页回填：打开含 id≠name 演员的电影，输入框显示名字
// 3) 端到端闭环：联想新建演员 → 保存 → 详情/编辑重开均显示名字且落盘的是 id
// 4) 演员页：作品反查可点回电影；编辑资料改名全链生效；删除受引用保护
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:moying/models/actor.dart';
import 'package:moying/providers/library_provider.dart';
import 'package:moying/screens/actor_detail_screen.dart';
import 'package:moying/screens/movie_detail_screen.dart';
import 'package:moying/screens/movie_edit_screen.dart';

/// 单屏包裹：注入内存模式 provider，home 作为可 pop 的根路由
Widget _wrap(LibraryProvider provider, Widget home) {
  return ChangeNotifierProvider.value(
    value: provider,
    child: MaterialApp(home: home),
  );
}

/// 造一个 id≠name 的演员实体（真实新演员形态：a_ 前缀 id）
Actor _newActor(String name) =>
    Actor(id: 'a_test_$name', name: name, createdAt: DateTime(2026, 1, 1));

/// 编辑页演员输入框（hintText 定位，避免与标题等 TextField 混淆）
Finder _actorField() => find.byWidgetPredicate(
      (w) =>
          w is TextField &&
          w.decoration?.hintText == '输入姓名联想选择或新建',
    );

void main() {
  group('详情页演员区（解析渲染）', () {
    testWidgets('id≠name 实体显示名字而非乱码 id', (tester) async {
      final p = LibraryProvider();
      final actor = _newActor('甄探');
      p.addActor(actor);
      final base = p.movieList.first;
      p.updateMovie(base.copyWith(actorIds: [actor.id]));

      await tester.pumpWidget(_wrap(p, MovieDetailScreen(movieId: base.id)));
      await tester.pumpAndSettle();

      expect(find.text('甄探'), findsOneWidget);
      expect(find.text(actor.id), findsNothing);
    });

    testWidgets('点击演员实体条进入演员详情页', (tester) async {
      final p = LibraryProvider();
      final actor = _newActor('甄探');
      p.addActor(actor);
      final base = p.movieList.first;
      p.updateMovie(base.copyWith(actorIds: [actor.id]));

      await tester.pumpWidget(_wrap(p, MovieDetailScreen(movieId: base.id)));
      await tester.pumpAndSettle();

      final actorChip = find.text('甄探');
      await tester.ensureVisible(actorChip);
      await tester.tap(actorChip);
      await tester.pumpAndSettle();

      expect(find.byType(ActorDetailScreen), findsOneWidget);
      // 演员页内链：参演作品反查到这部电影
      expect(find.text('参演作品'), findsOneWidget);
      expect(find.text(base.title), findsOneWidget);

      // 点作品回到电影详情
      await tester.tap(find.text(base.title).last);
      await tester.pumpAndSettle();
      expect(find.byType(MovieDetailScreen), findsOneWidget);
    });
  });

  group('编辑页演员回填（解析渲染点二）', () {
    testWidgets('打开含 id≠name 演员的电影，输入框显示名字而非 id', (tester) async {
      final p = LibraryProvider();
      final actor = _newActor('甄探');
      p.addActor(actor);
      final base = p.movieList.first;
      p.updateMovie(base.copyWith(actorIds: [actor.id]));

      await tester.pumpWidget(_wrap(p, MovieEditScreen(movieId: base.id)));
      await tester.pumpAndSettle();

      expect(find.text('甄探'), findsWidgets);
      expect(find.text(actor.id), findsNothing);
    });
  });

  group('端到端闭环（联想新建 → 保存 → 重开仍显名字且存 id）', () {
    testWidgets('新建演员落 a_ 前缀 id，详情/编辑重开均显示名字', (tester) async {
      final p = LibraryProvider();

      // 根 Scaffold + go 按钮，让编辑页保存后可正常 pop 返回
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: p,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MovieEditScreen()),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      // 添加演员槽位并输入全新名字（库中无匹配 → 候选出现「新建」行）
      final addBtn = find.text('添加演员');
      await tester.ensureVisible(addBtn);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();
      await tester.enterText(_actorField(), '新星小颖');
      await tester.pumpAndSettle();

      expect(find.textContaining('新建演员'), findsOneWidget);
      await tester.tap(find.textContaining('新建演员'));
      await tester.pumpAndSettle();

      // 填标题并保存
      await tester.enterText(find.byType(TextField).first, '内链测试片');
      final saveBtn = find.text('保存');
      await tester.ensureVisible(saveBtn);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // 落盘契约：actorIds 存的是 a_ 前缀 id（而非名字文本）
      final movie = p.movieList.last;
      expect(movie.title, '内链测试片');
      expect(movie.actorIds, isNotNull);
      expect(movie.actorIds!.single, startsWith('a_'));
      expect(movie.actorIds!.single, isNot('新星小颖'));
      expect(p.actors.any((a) => a.name == '新星小颖'), isTrue);

      // 详情页显示名字
      await tester.pumpWidget(_wrap(p, MovieDetailScreen(movieId: movie.id)));
      await tester.pumpAndSettle();
      expect(find.text('新星小颖'), findsOneWidget);
      expect(find.text(movie.actorIds!.single), findsNothing);

      // 编辑回填显示名字
      await tester.pumpWidget(_wrap(p, MovieEditScreen(movieId: movie.id)));
      await tester.pumpAndSettle();
      expect(find.text('新星小颖'), findsWidgets);
      expect(find.text(movie.actorIds!.single), findsNothing);
    });
  });

  group('演员详情页：资料编辑与引用保护', () {
    testWidgets('编辑资料改名后页面与详情页同步更新', (tester) async {
      final p = LibraryProvider();
      final actor = _newActor('旧艺名');
      p.addActor(actor);
      final base = p.movieList.first;
      p.updateMovie(base.copyWith(actorIds: [actor.id]));

      await tester.pumpWidget(_wrap(p, MovieDetailScreen(movieId: base.id)));
      await tester.pumpAndSettle();
      final chip = find.text('旧艺名');
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      // 编辑资料：改名 + 写简介
      await tester.tap(find.byTooltip('编辑资料'));
      await tester.pumpAndSettle();
      final nameField = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '姓名');
      await tester.enterText(nameField, '新艺名');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(p.actors.any((a) => a.id == actor.id && a.name == '新艺名'), isTrue);
      // 演员页标题与正文同步
      expect(find.text('新艺名'), findsWidgets);
      expect(find.text('旧艺名'), findsNothing);

      // 返回电影详情：演员条名字已同步
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('新艺名'), findsOneWidget);
    });

    testWidgets('被电影引用时拒绝删除并提示；清空引用后删除成功', (tester) async {
      final p = LibraryProvider();
      final actor = _newActor('甄探');
      p.addActor(actor);
      final base = p.movieList.first;
      p.updateMovie(base.copyWith(actorIds: [actor.id]));

      await tester.pumpWidget(_wrap(p, MovieDetailScreen(movieId: base.id)));
      await tester.pumpAndSettle();
      final chip = find.text('甄探');
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      // 仍被引用：删除被拒
      await tester.tap(find.byTooltip('删除演员'));
      await tester.pumpAndSettle();
      expect(find.text('暂不能删除'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(p.actors.any((a) => a.id == actor.id), isTrue);

      // 移除电影里的引用后再删：确认弹窗 → 删除成功并返回上一页
      p.updateMovie(base.copyWith(actorIds: <String>[]));
      await tester.tap(find.byTooltip('删除演员'));
      await tester.pumpAndSettle();
      expect(find.text('删除这位演员？'), findsOneWidget);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(p.actors.any((a) => a.id == actor.id), isFalse);
      expect(find.byType(ActorDetailScreen), findsNothing);
      // 回到电影详情：演员区因引用清空而整块隐藏
      expect(find.byType(MovieDetailScreen), findsOneWidget);
      expect(find.text('甄探'), findsNothing);
    });
  });
}
