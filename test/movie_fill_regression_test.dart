// 电影数据源回填回归测试
//
// 背景（2026-09-07 用户报告）：
// 电影模块添加电影时，快速检索回填后下拉结果列表不会收起。
//
// 根因：movie_edit_screen 的 onPick → _applyMovieResult 全程没有调用
// ds.clearResults()，导致 ds.movieResults 一直非 null，QuickSearchPanel._body
// 的 `results == null` 分支进不去 → 一直渲染结果列表。
// 附带：QuickSearchPanel 只传了 filledExternalId 没传 filledTitle，
//       即使收起也会退化成「搜索结果将显示在这里」而非「已填充《片名》」。
//
// 本测试覆盖：
// - MovieSearchResult.mergeWith 合并语义（详情缺失字段保留搜索结果）
// - QuickSearchPanel 收起/展开分支（results null + filledTitle → 已填充态）

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moying/models/data_source.dart';
import 'package:moying/widgets/quick_search_panel.dart';

void main() {
  group('MovieSearchResult.mergeWith', () {
    const base = MovieSearchResult(
      externalId: 'tmdb-1',
      title: '肖申克的救赎',
      originalTitle: 'The Shawshank Redemption',
      year: 1994,
      director: '弗兰克·德拉邦特',
      genres: ['剧情'],
      posterUrl: 'https://example.com/poster.jpg',
      rating: 4.8,
      overview: '简短简介',
      runtimeMinutes: 142,
    );

    test('全空详情不覆盖任何字段', () {
      const detail = MovieSearchResult(
        externalId: 'tmdb-1',
        title: '',
        genres: [],
        cast: [],
      );
      final merged = base.mergeWith(detail);
      expect(merged.title, base.title);
      expect(merged.originalTitle, base.originalTitle);
      expect(merged.year, base.year);
      expect(merged.director, base.director);
      expect(merged.genres, base.genres);
      expect(merged.posterUrl, base.posterUrl);
      expect(merged.rating, base.rating);
      expect(merged.overview, base.overview);
      expect(merged.runtimeMinutes, base.runtimeMinutes);
    });

    test('详情非空字段覆盖 base（cast / genres / overview）', () {
      const detail = MovieSearchResult(
        externalId: 'tmdb-1',
        title: '肖申克的救赎',
        genres: ['剧情', '犯罪'],
        overview: '完整的剧情简介……',
        cast: [CastMember(name: '蒂姆·罗宾斯', character: 'Andy')],
      );
      final merged = base.mergeWith(detail);
      // 详情有 → 覆盖
      expect(merged.genres, ['剧情', '犯罪']);
      expect(merged.overview, '完整的剧情简介……');
      expect(merged.cast.length, 1);
      expect(merged.cast.first.name, '蒂姆·罗宾斯');
      // 详情缺失 → 保留 base
      expect(merged.posterUrl, base.posterUrl);
      expect(merged.year, base.year);
      expect(merged.director, base.director);
      expect(merged.runtimeMinutes, base.runtimeMinutes);
      expect(merged.rating, base.rating);
    });

    test('详情缺失海报/年份时保留 base（与书籍侧同款 bug 防护）', () {
      const detail = MovieSearchResult(
        externalId: 'tmdb-1',
        title: '肖申克的救赎',
        director: '弗兰克·德拉邦特',
        // posterUrl / year / rating 全为 null
        genres: ['剧情'],
        cast: [CastMember(name: '摩根·弗里曼')],
      );
      final merged = base.mergeWith(detail);
      expect(merged.director, '弗兰克·德拉邦特');
      expect(merged.genres, ['剧情']);
      expect(merged.cast.first.name, '摩根·弗里曼');
      // 关键断言：详情缺失字段不被 null 覆盖
      expect(merged.posterUrl, 'https://example.com/poster.jpg',
          reason: 'posterUrl 详情缺失时必须保留搜索结果');
      expect(merged.year, 1994, reason: 'year 详情缺失时必须保留搜索结果');
      expect(merged.rating, 4.8, reason: 'rating 详情缺失时必须保留搜索结果');
    });

    test('详情空字符串按缺失处理', () {
      const detail = MovieSearchResult(
        externalId: 'tmdb-1',
        title: '',
        originalTitle: '',
        director: '',
        posterUrl: '',
        overview: '',
      );
      final merged = base.mergeWith(detail);
      expect(merged.title, base.title);
      expect(merged.originalTitle, base.originalTitle);
      expect(merged.director, base.director);
      expect(merged.posterUrl, base.posterUrl);
      expect(merged.overview, base.overview);
    });

    test('title 缺失/相同时保留 base', () {
      const sameTitle = MovieSearchResult(
        externalId: 'tmdb-1',
        title: '肖申克的救赎',
      );
      expect(base.mergeWith(sameTitle).title, base.title);

      const emptyTitle = MovieSearchResult(
        externalId: 'tmdb-1',
        title: '',
      );
      expect(base.mergeWith(emptyTitle).title, base.title);

      const differentTitle = MovieSearchResult(
        externalId: 'tmdb-1',
        title: 'Different Title',
      );
      expect(base.mergeWith(differentTitle).title, 'Different Title');
    });
  });

  group('QuickSearchPanel 结果列表收起', () {
    Widget buildPanel({
      required List<QuickSearchItem>? results,
      String? filledExternalId,
      String? filledTitle,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: QuickSearchPanel(
              controller: TextEditingController(text: '肖申克'),
              hint: '输入片名，联网搜索并回填',
              sourceName: 'TMDB',
              isSearching: false,
              error: null,
              results: results,
              filledExternalId: filledExternalId,
              filledTitle: filledTitle,
              tagColor: const Color(0xFF6C5CE7),
              fallbackIcon: Icons.movie_outlined,
              onClear: () {},
              onPick: (_) {},
            ),
          ),
        ),
      );
    }

    final results = [
      const QuickSearchItem(
        title: '肖申克的救赎',
        subtitle: 'The Shawshank Redemption · 1994',
        coverUrl: null,
        externalId: 'tmdb-1',
      ),
    ];

    testWidgets(
      'results 非 null 时展开结果列表（回填前的状态）',
      (WidgetTester tester) async {
        await tester.pumpWidget(buildPanel(results: results));
        await tester.pumpAndSettle();

        // 结果条目可见
        expect(find.text('肖申克的救赎'), findsWidgets);
        // 未进入收起态
        expect(find.textContaining('已填充《'), findsNothing);
      },
    );

    testWidgets(
      'results 为 null + filledTitle 时收起并显示「已填充《片名》」',
      (WidgetTester tester) async {
        // 这是用户报告场景的期望终态：回填 + clearResults 之后
        await tester.pumpWidget(buildPanel(
          results: null,
          filledExternalId: 'tmdb-1',
          filledTitle: '肖申克的救赎',
        ));
        await tester.pumpAndSettle();

        // 收起态：显示已填充提示
        expect(find.textContaining('已填充《肖申克的救赎》'), findsOneWidget);
        // 结果列表不再渲染
        expect(find.text('搜索结果将显示在这里，点击条目自动回填表单'), findsNothing);
      },
    );

    testWidgets(
      'results 为 null 但无 filledTitle 时退化为空态提示（不显示已填充）',
      (WidgetTester tester) async {
        // 这正是「只补 clearResults 不补 filledTitle」的后果——
        // 列表能收起，但用户看不到「已填充」反馈
        await tester.pumpWidget(buildPanel(
          results: null,
          filledExternalId: 'tmdb-1',
          filledTitle: null,
        ));
        await tester.pumpAndSettle();

        expect(find.text('搜索结果将显示在这里，点击条目自动回填表单'), findsOneWidget);
        expect(find.textContaining('已填充《'), findsNothing);
      },
    );

    testWidgets('搜索中时显示 loading，不显示结果列表', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: QuickSearchPanel(
            controller: TextEditingController(text: '肖申克'),
            hint: '输入片名',
            sourceName: 'TMDB',
            isSearching: true,
            error: null,
            results: results,
            filledExternalId: null,
            filledTitle: null,
            tagColor: const Color(0xFF6C5CE7),
            fallbackIcon: Icons.movie_outlined,
            onClear: () {},
            onPick: (_) {},
          ),
        ),
      ));
      // loading 是持续动画，pumpAndSettle 永不收敛 → 只渲染一帧
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('肖申克的救赎'), findsNothing);
    });
  });
}
