// 电影模块「演职员头像 + 剧照」回归测试
//
// 背景（2026-09-08 需求）：
// 1) 详情页主创 / 演员要显示 TMDB 真实头像（credits.cast[].profile_path），
//    无头像时用中性灰渐变 CircleAvatar，而非饱和度偏灰绿/棕的彩色块。
// 2) 演员区与剧照区要能横向滑动，并带「全部 N」入口：
//    演员 → 演职员表弹层（可搜索、导演/演员分组、点击跳作品页）；
//    剧照 → 剧照与海报全量页（Tab 分类 + 网格 + 点击放大）。
// 3) 剧照要落盘缓存（Movie.stills），不能每次进详情页都重新联网。
//
// 为什么单独建文件：这三个能力横跨「数据源解析 → 模型序列化 → 详情页 UI」，
// 拆进既有文件会模糊各自的主题（data_source_test 关注数据源管理，
// actor_flow_test 关注演员实体内链）。
//
// 覆盖点：
// A. TMDB getMovieDetail 解析（profile_path / backdrops / posters / 请求参数）
// B. Movie.cast + Movie.stills 序列化往返与旧数据兼容
// C. 详情页 UI：角色名渲染、全部入口 → 弹层 / 全量页、剧照空态

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'package:moying/models/actor.dart';
import 'package:moying/models/data_source.dart';
import 'package:moying/models/media_ref.dart';
import 'package:moying/models/movie.dart';
import 'package:moying/providers/library_provider.dart';
import 'package:moying/screens/movie_detail_screen.dart';
import 'package:moying/screens/movie_stills_screen.dart';
import 'package:moying/services/data_sources/tmdb_data_source.dart';

/// 记录请求 + 返回固定 JSON 的假 HTTP 客户端
///
/// 直接继承 BaseClient：TmdbDataSource 只用到 `get()`，
/// 实现 send 即可全局拦截，无需 mockito / http_mock_adapter。
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._body) : assert(_body != null);

  final String? _body;

  /// 捕获实际请求的 URI（用于断言 append_to_response 等参数）
  final List<Uri> requested = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requested.add(request.url);
    final body = _body;
    if (body == null) {
      return http.StreamedResponse(
        const Stream<List<int>>.empty(),
        500,
        request: request,
      );
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      request: request,
      headers: {'content-type': 'application/json'},
    );
  }
}

/// TMDB /movie/{id} 详情响应：1 位导演 + 2 位演员（一人无头像）+ 2 张剧照 + 1 张海报
const String _kDetailJson = '''
{
  "id": 278,
  "title": "肖申克的救赎",
  "original_title": "The Shawshank Redemption",
  "release_date": "1994-09-23",
  "runtime": 142,
  "vote_average": 8.7,
  "poster_path": "/q6y0Go1tsGEsmtFryDOJo3dEmqu.jpg",
  "overview": "一场杀妻冤案",
  "genres": [{"id": 18, "name": "剧情"}, {"id": 80, "name": "犯罪"}],
  "credits": {
    "crew": [
      {"job": "Producer", "name": "尼基·马文"},
      {"job": "Director", "name": "弗兰克·德拉邦特"}
    ],
    "cast": [
      {
        "name": "蒂姆·罗宾斯",
        "character": "Andy Dufresne",
        "profile_path": "/tR0BtsWw9uh8AU1VXT2l2NYnFhj.jpg"
      },
      {
        "name": "摩根·弗里曼",
        "character": "Ellis Boyd 'Red' Redding",
        "profile_path": null
      }
    ]
  },
  "images": {
    "backdrops": [
      {"file_path": "/kXfqcdQKsToO0OUXHcrrNCHDBzO.jpg", "width": 1920},
      {"file_path": "/9O7gLzmreU0nGkIB6K3BsJbzvNv.jpg", "width": 1920}
    ],
    "posters": [{"file_path": "/q6y0Go1tsGEsmtFryDOJo3dEmqu.jpg", "width": 2000}]
  }
}
''';

/// 详情响应但完全没有 images 段（老接口 / 自定义代理源可能如此）
const String _kDetailNoImagesJson = '''
{
  "id": 279,
  "title": "无图电影",
  "credits": {
    "cast": [{"name": "无名演员", "character": "路人"}]
  }
}
''';

void main() {
  group('A. TMDB 详情解析：头像 / 剧照 / 海报', () {
    test('profile_path → w185 完整 URL；缺失时保持 null', () async {
      final client = _FakeHttpClient(_kDetailJson);
      final ds = TmdbDataSource(client: client);
      final detail = await ds.getMovieDetail('278',
          config: const {}, credentials: const {'apiKey': 'test_key'});

      expect(detail.director, '弗兰克·德拉邦特');
      expect(detail.cast.length, 2);
      expect(detail.cast[0].name, '蒂姆·罗宾斯');
      expect(detail.cast[0].character, 'Andy Dufresne');
      expect(detail.cast[0].profilePath,
          'https://image.tmdb.org/t/p/w185/tR0BtsWw9uh8AU1VXT2l2NYnFhj.jpg',
          reason: '演员头像必须拼成可直接渲染的完整 URL');
      // 无头像的演员：profilePath 为 null → UI 回退中性灰渐变占位
      expect(detail.cast[1].profilePath, isNull);
      expect(detail.cast[1].character, "Ellis Boyd 'Red' Redding");
    });

    test('images.backdrops → w780 URL；posters → w500 URL', () async {
      final client = _FakeHttpClient(_kDetailJson);
      final ds = TmdbDataSource(client: client);
      final detail = await ds.getMovieDetail('278',
          config: const {}, credentials: const {'apiKey': 'test_key'});

      expect(detail.backdrops, [
        'https://image.tmdb.org/t/p/w780/kXfqcdQKsToO0OUXHcrrNCHDBzO.jpg',
        'https://image.tmdb.org/t/p/w780/9O7gLzmreU0nGkIB6K3BsJbzvNv.jpg',
      ]);
      expect(detail.posters, [
        'https://image.tmdb.org/t/p/w500/q6y0Go1tsGEsmtFryDOJo3dEmqu.jpg',
      ]);
    });

    test('请求带上 credits,images 与中文物料优先参数', () async {
      final client = _FakeHttpClient(_kDetailJson);
      final ds = TmdbDataSource(client: client);
      await ds.getMovieDetail('278',
          config: const {}, credentials: const {'apiKey': 'test_key'});

      expect(client.requested, hasLength(1));
      final q = client.requested.single.queryParameters;
      // 少任一个都拿不到头像或剧照：这是本次需求的硬前提
      expect(q['append_to_response'], 'credits,images');
      expect(q['include_image_language'], 'zh-CN,null');
      expect(q['api_key'], 'test_key');
    });

    test('响应无 images 段时不抛异常，剧照为空数组', () async {
      final client = _FakeHttpClient(_kDetailNoImagesJson);
      final ds = TmdbDataSource(client: client);
      final detail = await ds.getMovieDetail('279',
          config: const {}, credentials: const {'apiKey': 'test_key'});

      expect(detail.backdrops, isEmpty);
      expect(detail.posters, isEmpty);
      // 演员仍正常解析（只是没头像）
      expect(detail.cast.single.name, '无名演员');
    });
  });

  group('B. Movie.cast / Movie.stills 序列化', () {
    Movie baseMovie() => const Movie(
          id: 'm_test_1',
          title: '肖申克的救赎',
          year: 1994,
          status: MovieStatus.watched,
          rating: 5,
        );

    test('cast 快照（角色名 + 头像）与 stills 往返一致', () {
      final m = baseMovie().copyWith(
        cast: const [
          CastMember(
            name: '蒂姆·罗宾斯',
            character: 'Andy Dufresne',
            profilePath:
                'https://image.tmdb.org/t/p/w185/tR0BtsWw9uh8AU1VXT2l2NYnFhj.jpg',
          ),
          CastMember(name: '摩根·弗里曼', character: 'Red'),
        ],
        stills: [
          MediaRef.network('https://image.tmdb.org/t/p/w780/a.jpg'),
          MediaRef.network('https://image.tmdb.org/t/p/w780/b.jpg'),
        ],
      );

      final restored = Movie.fromJson(m.toJson());
      expect(restored.cast?.length, 2);
      expect(restored.cast?[0].name, '蒂姆·罗宾斯');
      expect(restored.cast?[0].character, 'Andy Dufresne');
      expect(restored.cast?[0].profilePath,
          'https://image.tmdb.org/t/p/w185/tR0BtsWw9uh8AU1VXT2l2NYnFhj.jpg');
      expect(restored.cast?[1].profilePath, isNull);
      expect(restored.stills?.length, 2);
      expect(restored.stills?[0].remoteUrl,
          'https://image.tmdb.org/t/p/w780/a.jpg');
      // 剧照是缓存：落盘后必须能原样读回，否则每次进详情页都要重新联网
      expect(restored == m, isTrue);
    });

    test('旧 JSON（无 cast / stills 字段）解析为 null，不报错', () {
      final old = <String, dynamic>{
        'id': 'm_old',
        'title': '老电影',
        'year': 2000,
        'status': 'watched',
        'rating': 4,
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      final m = Movie.fromJson(old);
      expect(m.cast, isNull);
      expect(m.stills, isNull);
      // 旧数据不落这两个 key，避免无谓放大存储
      expect(m.toJson().containsKey('cast'), isFalse);
      expect(m.toJson().containsKey('stills'), isFalse);
    });

    test('copyWith 可清空 cast / stills（sentinel 机制）', () {
      final m = baseMovie().copyWith(
        cast: const [CastMember(name: '临时演员')],
        stills: [MediaRef.network('https://x/y.jpg')],
      );
      expect(m.cast, isNotNull);
      expect(m.stills, isNotNull);

      final cleared = m.copyWith(cast: null, stills: null);
      expect(cleared.cast, isNull);
      expect(cleared.stills, isNull);
    });
  });

  group('C. 详情页 UI：演员区与剧照区', () {
    Widget wrap(LibraryProvider p, Widget home) =>
        ChangeNotifierProvider.value(
          value: p,
          child: MaterialApp(home: home),
        );

    /// 造一部带 cast 快照 + 剧照的电影（演员已入库，保证点击可跳转）
    (LibraryProvider, Movie) buildMovie({
      List<CastMember>? cast,
      List<MediaRef>? stills,
      String? director,
      MediaRef? poster,
      List<Actor> actors = const [],
    }) {
      final p = LibraryProvider();
      final ids = <String>[];
      for (final a in actors) {
        p.addActor(a);
        ids.add(a.id);
      }
      final base = p.movieList.first;
      final movie = base.copyWith(
        director: director,
        actorIds: ids.isEmpty ? null : ids,
        cast: cast,
        stills: stills,
        poster: poster ?? base.poster,
      );
      p.updateMovie(movie);
      return (p, movie);
    }

    testWidgets('有 cast 快照时显示角色名，并渲染「全部 N」入口', (tester) async {
      final (p, movie) = buildMovie(
        director: '弗兰克·德拉邦特',
        cast: const [
          CastMember(name: '蒂姆·罗宾斯', character: 'Andy Dufresne'),
          CastMember(name: '摩根·弗里曼', character: 'Red'),
        ],
        actors: [
          Actor(
              id: 'a_tim',
              name: '蒂姆·罗宾斯',
              createdAt: DateTime(2026, 1, 1)),
          Actor(
              id: 'a_morgan',
              name: '摩根·弗里曼',
              createdAt: DateTime(2026, 1, 1)),
        ],
      );

      await tester.pumpWidget(wrap(p, MovieDetailScreen(movieId: movie.id)));
      await tester.pumpAndSettle();

      // 角色名来自 cast 快照（本地 Actor 实体没有角色概念）
      expect(find.text('Andy Dufresne'), findsOneWidget);
      expect(find.text('Red'), findsOneWidget);
      // 导演也被纳入演职员表 → 总数 3（导演 + 2 演员）
      expect(find.text('全部 3'), findsOneWidget);
    });

    testWidgets('点击「全部」打开演职员表弹层，导演单独分组', (tester) async {
      final (p, movie) = buildMovie(
        director: '弗兰克·德拉邦特',
        cast: const [CastMember(name: '蒂姆·罗宾斯', character: 'Andy')],
        actors: [
          Actor(
              id: 'a_tim',
              name: '蒂姆·罗宾斯',
              createdAt: DateTime(2026, 1, 1)),
        ],
      );

      await tester.pumpWidget(wrap(p, MovieDetailScreen(movieId: movie.id)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('全部 2'));
      await tester.tap(find.text('全部 2'));
      await tester.pumpAndSettle();

      // 弹层标题带总数、副标题带片名
      expect(find.text('演职员表 (2)'), findsOneWidget);
      expect(find.text(movie.title), findsWidgets);
      // 分组：导演 / 主要演员
      expect(find.text('导演'), findsWidgets);
      expect(find.text('主要演员'), findsOneWidget);
      // 搜索框可用
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('弹层搜索无命中时显示空态文案', (tester) async {
      final (p, movie) = buildMovie(
        cast: const [
          CastMember(name: '蒂姆·罗宾斯', character: 'Andy'),
          CastMember(name: '摩根·弗里曼', character: 'Red'),
        ],
        actors: [
          Actor(
              id: 'a_tim',
              name: '蒂姆·罗宾斯',
              createdAt: DateTime(2026, 1, 1)),
          Actor(
              id: 'a_morgan',
              name: '摩根·弗里曼',
              createdAt: DateTime(2026, 1, 1)),
        ],
      );

      await tester.pumpWidget(wrap(p, MovieDetailScreen(movieId: movie.id)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('全部 2'));
      await tester.tap(find.text('全部 2'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '不存在的演员');
      await tester.pumpAndSettle();

      // 弹层专属空态（详情页横滑区不受搜索影响，故只断言这句）
      expect(find.text('没有匹配的演员'), findsOneWidget);
    });

    testWidgets('弹层搜索按姓名/角色过滤', (tester) async {
      final (p, movie) = buildMovie(
        cast: const [
          CastMember(name: '蒂姆·罗宾斯', character: 'Andy'),
          CastMember(name: '摩根·弗里曼', character: 'Red'),
        ],
        actors: [
          Actor(
              id: 'a_tim',
              name: '蒂姆·罗宾斯',
              createdAt: DateTime(2026, 1, 1)),
          Actor(
              id: 'a_morgan',
              name: '摩根·弗里曼',
              createdAt: DateTime(2026, 1, 1)),
        ],
      );

      await tester.pumpWidget(wrap(p, MovieDetailScreen(movieId: movie.id)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('全部 2'));
      await tester.tap(find.text('全部 2'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '摩根');
      await tester.pumpAndSettle();

      // 弹层是模态覆盖层，底层详情页横滑区仍在树里且恒显示两人：
      // 摩根 = 详情页 1 + 弹层 1；蒂姆 = 仅详情页 1（弹层已过滤掉）
      expect(find.text('摩根·弗里曼'), findsNWidgets(2));
      expect(find.text('蒂姆·罗宾斯'), findsOneWidget);
    });

    testWidgets('无剧照时显示空态，不显示「全部」入口', (tester) async {
      final (p, movie) = buildMovie(stills: const []);

      await tester.pumpWidget(wrap(p, MovieDetailScreen(movieId: movie.id)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('暂无剧照'));
      expect(find.text('暂无剧照'), findsOneWidget);
    });

    testWidgets('剧照「全部」跳转全量页，Tab 显示分类数量', (tester) async {
      // 用 local 引用：测试环境禁止真实网络（NetworkImage 恒 400 且会计入
      // 未处理异常），而本用例只校验「数量透传 + 跳转」，与图片来源无关。
      final (p, movie) = buildMovie(
        director: '某导演',
        poster: MediaRef.local('p.jpg'),
        stills: [
          MediaRef.local('a.jpg'),
          MediaRef.local('b.jpg'),
        ],
      );

      await tester.pumpWidget(wrap(p, MovieDetailScreen(movieId: movie.id)));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('全部 2'));
      await tester.tap(find.text('全部 2'));
      await tester.pumpAndSettle();

      expect(find.byType(MovieStillsScreen), findsOneWidget);
      // 2 张剧照 + 1 张主海报（详情页把主海报并入「海报」Tab）
      expect(find.text('全部 3'), findsOneWidget);
      expect(find.text('剧照 2'), findsOneWidget);
      expect(find.text('海报 1'), findsOneWidget);
    });

    testWidgets('无 cast 快照时回退本地演员实体（旧数据可用）', (tester) async {
      // 只给 actorIds，不给 cast 快照：模拟 v0.9.2 之前入库的电影。
      // 种子电影自带导演，显式清掉，保证演职员表只有「老演员」一人。
      final p = LibraryProvider();
      final actor =
          Actor(id: 'a_legacy', name: '老演员', createdAt: DateTime(2026, 1, 1));
      p.addActor(actor);
      final base = p.movieList.first;
      p.updateMovie(base.copyWith(
        director: null,
        actorIds: [actor.id],
        cast: null,
        stills: null,
      ));
      final movie = p.movieList.firstWhere((m) => m.id == base.id);

      await tester.pumpWidget(wrap(p, MovieDetailScreen(movieId: movie.id)));
      await tester.pumpAndSettle();

      expect(find.text('老演员'), findsOneWidget);
      // 回退路径没有角色名，但「全部」入口仍在
      expect(find.text('全部 1'), findsOneWidget);
    });
  });
}
