// MovieEditController 单元测试（M-5b）
//
// 导演 ↔ 演员槽位联动、类型标签拼接、演员吸附/新建、海报解析这些规则此前
// 埋在 1700 行的 State 里，只能靠 pump 编辑页间接验证。迁进控制器后可以直接断言。
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:moying/business/shared/model/actor.dart';
import 'package:moying/business/shared/model/movie.dart';
import 'package:moying/business/library/view_model/library_provider.dart';
import 'package:moying/business/library/view_model/movie_edit_controller.dart';
import 'package:moying/business/shared/model/data_source.dart'
    show CastMember;
import 'package:moying/component/media/model/media_ref.dart';

Movie sampleMovie({
  String id = 'm_1',
  String title = '星际穿越',
  String? englishTitle = 'Interstellar',
  int year = 2014,
  String? director = '诺兰',
  MovieStatus status = MovieStatus.rated,
  double? rating = 4.5,
  double coverHue = 210,
  String? emoji = '🎬',
  int? duration = 169,
  List<String>? genres = const ['科幻'],
  String? review = '很好',
  List<String>? actorIds = const ['a_1'],
  MediaRef? poster,
  DateTime? releaseDate,
  DateTime? watchDate,
  List<CastMember>? cast,
  List<MediaRef>? stills,
  String? source = 'tmdb:157336',
}) =>
    Movie(
      id: id,
      title: title,
      englishTitle: englishTitle,
      year: year,
      director: director,
      status: status,
      rating: rating,
      coverHue: coverHue,
      emoji: emoji,
      duration: duration,
      genres: genres,
      review: review,
      actorIds: actorIds,
      poster: poster,
      releaseDate: releaseDate,
      watchDate: watchDate,
      cast: cast,
      stills: stills,
      description: null,
      source: source,
    );

Actor actor(String id, String name) =>
    Actor(id: id, name: name, createdAt: DateTime(2026, 1, 1));

void main() {
  group('MovieEditController · 新增模式', () {
    test('默认值：无原片、无评分、无标签、无槽位', () {
      final c = MovieEditController();
      addTearDown(c.dispose);

      expect(c.isEditMode, isFalse);
      expect(c.notFound, isFalse);
      expect(c.movie, isNull);
      expect(c.titleCtrl.text, '');
      expect(c.durationCtrl.text, '');
      expect(c.rating, 0);
      expect(c.selectedGenres, isEmpty);
      expect(c.actorSlots, isEmpty);
      expect(c.releaseDate, isNull);
      expect(c.watchDate, isNull);
      expect(c.posterEdited, isFalse);
      expect(c.cast, isNull);
      expect(c.stills, isNull);
    });

    test('validate：标题为空给出统一文案', () {
      final c = MovieEditController();
      addTearDown(c.dispose);

      expect(c.validate(), '电影标题不能为空');
      c.titleCtrl.text = '  ';
      expect(c.validate(), '电影标题不能为空');
      c.titleCtrl.text = '星际穿越';
      expect(c.validate(), isNull);
    });

    test('composeMovie：生成新实体，year 取上映年、无评分即「想看」', () async {
      final c = MovieEditController();
      addTearDown(c.dispose);
      c.titleCtrl.text = '  星际穿越  ';
      c.englishCtrl.text = ' Interstellar ';
      c.directorCtrl.text = ' 诺兰 ';
      c.durationCtrl.text = '169';
      c.releaseDate = DateTime(2014, 11, 12);
      c.addGenre('科幻');
      c.reviewCtrl.text = ' 很好 ';

      final m = await c.composeMovie(LibraryProvider());

      expect(m, isNotNull);
      expect(m!.id, startsWith('m_'));
      expect(m.title, '星际穿越');
      expect(m.englishTitle, 'Interstellar');
      expect(m.director, '诺兰');
      expect(m.duration, 169);
      expect(m.year, 2014);
      expect(m.rating, isNull);
      expect(m.status, MovieStatus.watchlist);
      expect(m.genres, ['科幻']);
      expect(m.review, '很好');
      expect(m.coverHue, 165);
      expect(m.actorIds, isNull);
      expect(m.source, isNull);
    });

    test('composeMovie：空白文本字段归一为 null', () async {
      final c = MovieEditController();
      addTearDown(c.dispose);
      c.titleCtrl.text = '片名';
      c.englishCtrl.text = '  ';
      c.directorCtrl.text = '';
      c.durationCtrl.text = '不是数字';

      final m = await c.composeMovie(LibraryProvider());

      expect(m!.englishTitle, isNull);
      expect(m.director, isNull);
      expect(m.duration, isNull);
      expect(m.genres, isNull);
    });

    test('composeMovie：有评分即「已评分」', () async {
      final c = MovieEditController();
      addTearDown(c.dispose);
      c.titleCtrl.text = '片名';
      c.rating = 4;

      expect(
          (await c.composeMovie(LibraryProvider()))!.status, MovieStatus.rated);
    });
  });

  group('MovieEditController · 编辑模式', () {
    test('从原片回填全部表单字段与标签', () {
      final original = sampleMovie(
        releaseDate: DateTime(2014, 11, 12),
        watchDate: DateTime(2026, 3, 3),
      );
      final c = MovieEditController(movieId: 'm_1', initialMovie: original);
      addTearDown(c.dispose);

      expect(c.isEditMode, isTrue);
      expect(c.notFound, isFalse);
      expect(c.titleCtrl.text, '星际穿越');
      expect(c.englishCtrl.text, 'Interstellar');
      expect(c.directorCtrl.text, '诺兰');
      expect(c.durationCtrl.text, '169');
      expect(c.reviewCtrl.text, '很好');
      expect(c.rating, 4.5);
      expect(c.selectedGenres, {'科幻'});
      expect(c.releaseDate, DateTime(2014, 11, 12));
      expect(c.watchDate, DateTime(2026, 3, 3));
    });

    test('初始演员槽位来自传入的实体（actorIds 解析结果），导演自动槽排第 0 位', () {
      // 无导演：只留 actorIds 解析出的槽位
      final plain = MovieEditController(
        movieId: 'm_1',
        initialMovie: sampleMovie(director: null),
        initialActors: [actor('a_1', '马修')],
      );
      addTearDown(plain.dispose);

      expect(plain.actorSlots.length, 1);
      expect(plain.actorSlots.first.ctrl.text, '马修');
      expect(plain.actorSlots.first.picked!.id, 'a_1');

      // 有导演：构造时同步一次，自动槽插在第 0 位
      final withDirector = MovieEditController(
        movieId: 'm_1',
        initialMovie: sampleMovie(),
        initialActors: [actor('a_1', '马修')],
      );
      addTearDown(withDirector.dispose);

      expect(withDirector.actorSlots.length, 2);
      expect(withDirector.actorSlots.first.ctrl.text, '诺兰');
      expect(withDirector.actorSlots.first.autoFromDirector, isTrue);
      expect(withDirector.actorSlots.last.ctrl.text, '马修');
    });

    test('按 id 找不到影片 → notFound，composeMovie 返回 null', () async {
      final c = MovieEditController(movieId: 'nope');
      addTearDown(c.dispose);

      expect(c.notFound, isTrue);
      expect(c.movie, isNull);
      expect(await c.composeMovie(LibraryProvider()), isNull);
    });

    test('composeMovie：保留色相 / 年份 / 未在表单出现的字段', () async {
      final c =
          MovieEditController(movieId: 'm_1', initialMovie: sampleMovie());
      addTearDown(c.dispose);
      c.titleCtrl.text = '星际穿越（重看）';

      final m = await c.composeMovie(LibraryProvider());

      expect(m!.id, 'm_1');
      expect(m.title, '星际穿越（重看）');
      expect(m.coverHue, 210);
      expect(m.year, 2014);
      expect(m.duration, 169);
    });

    test('composeMovie：emoji 得以保留（编辑页不传 emoji，哨兵语义保留原值）', () async {
      final c =
          MovieEditController(movieId: 'm_1', initialMovie: sampleMovie());
      addTearDown(c.dispose);

      final m = await c.composeMovie(LibraryProvider());

      // Movie.copyWith 的 emoji 已改为 `Object? emoji = _unset`——省略参数
      // 保留原值。修复前默认值是 null，「未传」被当成「显式清空」，
      // 编辑页保存会静默丢掉占位符。
      expect(m!.emoji, '🎬');
      expect(c.movie!.emoji, '🎬');
    });

    test('copyWith：显式传 null 清空 emoji（哨兵语义的另一半）', () {
      final m = sampleMovie();

      expect(m.copyWith(emoji: null).emoji, isNull);
      expect(m.copyWith(emoji: '🌌').emoji, '🌌');
      expect(m.copyWith().emoji, '🎬'); // 省略 → 保留
    });

    test('composeMovie：评分被清空时从「已评分」降级为「已看」', () async {
      final c =
          MovieEditController(movieId: 'm_1', initialMovie: sampleMovie());
      addTearDown(c.dispose);
      c.rating = 0;

      final m = await c.composeMovie(LibraryProvider());

      expect(m!.status, MovieStatus.watched);
      // rating 走 `??`：显式 null 保留原值（与旧行为一致）
      expect(m.rating, 4.5);
    });

    test('composeMovie：未重新检索时保留原溯源标记', () async {
      final c =
          MovieEditController(movieId: 'm_1', initialMovie: sampleMovie());
      addTearDown(c.dispose);

      expect((await c.composeMovie(LibraryProvider()))!.source, 'tmdb:157336');
    });

    test('composeMovie：清空全部类型标签会写入 null（sentinel 语义）', () async {
      final c =
          MovieEditController(movieId: 'm_1', initialMovie: sampleMovie());
      addTearDown(c.dispose);
      c.selectedGenres.clear();

      expect((await c.composeMovie(LibraryProvider()))!.genres, isNull);
    });
  });

  group('MovieEditController · 导演 ↔ 演员槽位联动', () {
    test('导演非空 → 第 0 位插入自动槽，并记录自动槽文本', () {
      final c = MovieEditController();
      addTearDown(c.dispose);

      c.directorCtrl.text = '诺兰';
      c.applyDirectorSync();

      expect(c.actorSlots.length, 1);
      expect(c.actorSlots.first.ctrl.text, '诺兰');
      expect(c.actorSlots.first.autoFromDirector, isTrue);
      expect(c.directorAutoName, '诺兰');
    });

    test('再次同步：不重复插入，自动槽文本跟随导演', () {
      final c = MovieEditController();
      addTearDown(c.dispose);
      c.directorCtrl.text = '诺兰';
      c.applyDirectorSync();

      c.directorCtrl.text = '克里斯托弗·诺兰';
      c.applyDirectorSync();

      expect(c.actorSlots.length, 1);
      expect(c.actorSlots.first.ctrl.text, '克里斯托弗·诺兰');
      expect(c.actorSlots.first.autoFromDirector, isTrue);
    });

    test('用户改过自动槽文本 → 降级为普通槽，另起新自动槽', () {
      final c = MovieEditController();
      addTearDown(c.dispose);
      c.directorCtrl.text = '诺兰';
      c.applyDirectorSync();

      c.actorSlots.first.ctrl.text = '马修'; // 用户手动改成演员名
      c.applyDirectorSync();

      expect(c.actorSlots.length, 2);
      expect(c.actorSlots.first.ctrl.text, '诺兰'); // 新自动槽在第 0 位
      expect(c.actorSlots.first.autoFromDirector, isTrue);
      expect(c.actorSlots.last.ctrl.text, '马修');
      expect(c.actorSlots.last.autoFromDirector, isFalse);
    });

    test('导演清空 → 自动槽被移除', () {
      final c = MovieEditController();
      addTearDown(c.dispose);
      c.directorCtrl.text = '诺兰';
      c.applyDirectorSync();

      c.directorCtrl.text = '';
      c.applyDirectorSync();

      expect(c.actorSlots, isEmpty);
      expect(c.directorAutoName, isNull);
    });

    test('演员区已有同名 → 不再插入自动槽', () {
      final c = MovieEditController();
      addTearDown(c.dispose);
      c.actorSlots.add(ActorSlot(ctrl: TextEditingController(text: '诺兰')));

      c.directorCtrl.text = '诺兰';
      c.applyDirectorSync();

      expect(c.actorSlots.length, 1);
    });

    test('手动删除自动槽后，同导演不再自动弹回', () {
      final c = MovieEditController();
      addTearDown(c.dispose);
      c.directorCtrl.text = '诺兰';
      c.applyDirectorSync();

      c.removeActorSlot(c.actorSlots.first);
      expect(c.directorAutoDismissed, '诺兰');

      c.applyDirectorSync();
      expect(c.actorSlots, isEmpty);

      // 换导演 → 恢复自动补齐
      c.directorCtrl.text = '维伦纽瓦';
      c.applyDirectorSync();
      expect(c.actorSlots.length, 1);
      expect(c.actorSlots.first.ctrl.text, '维伦纽瓦');
    });

    test('移除普通槽位不记录 dismissed', () {
      final c = MovieEditController();
      addTearDown(c.dispose);
      c.actorSlots.add(ActorSlot(ctrl: TextEditingController(text: '马修')));

      c.removeActorSlot(c.actorSlots.first);

      expect(c.directorAutoDismissed, isNull);
      expect(c.actorSlots, isEmpty);
    });
  });

  group('MovieEditController · 类型标签', () {
    test('addGenre：空串与重复静默忽略', () {
      final c = MovieEditController();
      addTearDown(c.dispose);

      expect(c.addGenre('  '), isFalse);
      expect(c.addGenre(' 科幻 '), isTrue);
      expect(c.addGenre('科幻'), isFalse);
      expect(c.selectedGenres, {'科幻'});
    });

    test('commitGenreText：收进标签并清空输入框；括号内文本仍会清空', () {
      final c = MovieEditController();
      addTearDown(c.dispose);

      c.genreCtrl.text = ' 悬疑 ';
      expect(c.commitGenreText(), isTrue);
      expect(c.selectedGenres, {'悬疑'});
      expect(c.genreCtrl.text, '');

      // 已存在的标签：返回 false（无需重建），但仍清空输入框
      c.genreCtrl.text = '悬疑';
      expect(c.commitGenreText(), isFalse);
      expect(c.genreCtrl.text, '');
    });

    test('commitGenreText：空输入 no-op', () {
      final c = MovieEditController();
      addTearDown(c.dispose);

      expect(c.commitGenreText(), isFalse);
      expect(c.selectedGenres, isEmpty);
    });

    test('selectGenreOption：解析「添加“X”」哨兵取真实值', () {
      final c = MovieEditController();
      addTearDown(c.dispose);

      expect(
        c.selectGenreOption(
          '${MovieEditController.genreCreateSentinel}自造类型',
        ),
        isTrue,
      );
      expect(c.selectedGenres, {'自造类型'});
      expect(c.genreCtrl.text, '');
    });

    test('genreOptionsFor：空输入给全部候选（已选被剔除）', () {
      final c = MovieEditController();
      addTearDown(c.dispose);
      c.addGenre('科幻');

      final options = c.genreOptionsFor('', const []);

      expect(options, contains('悬疑'));
      expect(options, isNot(contains('科幻')));
    });

    test('genreOptionsFor：精确命中置顶、未命中追加哨兵', () {
      final c = MovieEditController();
      addTearDown(c.dispose);

      final exact = c.genreOptionsFor('科幻', const []);
      expect(exact.first, '科幻');

      final custom = c.genreOptionsFor('蒸汽朋克', const []);
      expect(custom, ['${MovieEditController.genreCreateSentinel}蒸汽朋克']);
    });

    test('genreCandidates：并入影库用过的类型且去重', () {
      final c = MovieEditController();
      addTearDown(c.dispose);

      final options = c.genreCandidates(['科幻', '自造类型']);

      expect(options.first, kMovieCategories.first);
      expect(options, contains('自造类型'));
      expect(options.where((g) => g == '科幻').length, 1);
    });
  });

  group('MovieEditController · 演员槽位与吸附', () {
    late LibraryProvider lib;

    setUp(() => lib = LibraryProvider());

    test('actorOptions：排除其他槽位已选，命中为空时追加「新建」哨兵', () {
      final c = MovieEditController();
      addTearDown(c.dispose);
      lib.addActor(actor('a_9', '马修·麦康纳'));
      final slotA = ActorSlot(ctrl: TextEditingController(text: '马修·麦康纳'));
      final slotB = ActorSlot();
      c.actorSlots
        ..add(slotA)
        ..add(slotB);
      slotA.picked = actor('a_9', '马修·麦康纳');

      // 已选槽位在别人的候选里应被排除
      final forB = c.actorOptions(slotB, '马修', lib);
      expect(forB.any((a) => a.id == 'a_9'), isFalse);

      // 本槽仍可命中自己
      final forA = c.actorOptions(slotA, '康纳', lib);
      expect(forA.any((a) => a.id == 'a_9'), isTrue);

      // 无精确命中 → 尾项为新建哨兵
      final none = c.actorOptions(slotB, '全新演员', lib);
      expect(none.last.id, MovieEditController.actorCreateId);
      expect(none.last.name, '全新演员');

      // 空查询不追加哨兵
      expect(
        c
            .actorOptions(slotB, '  ', lib)
            .any((a) => a.id == MovieEditController.actorCreateId),
        isFalse,
      );
    });

    test('pickActor：普通候选直接吸附', () {
      final c = MovieEditController();
      addTearDown(c.dispose);
      final slot = ActorSlot();
      c.actorSlots.add(slot);
      final existing = actor('a_5', '安妮');

      c.pickActor(slot, existing, lib);

      expect(slot.picked!.id, 'a_5');
      expect(lib.actors.any((a) => a.id == 'a_5'), isFalse); // 未新建
    });

    test('pickActor：命中哨兵 → 新建实体并落库', () {
      final c = MovieEditController();
      addTearDown(c.dispose);
      final slot = ActorSlot();
      c.actorSlots.add(slot);
      final before = lib.actors.length;

      c.pickActor(
        slot,
        actor(MovieEditController.actorCreateId, '新人'),
        lib,
      );

      expect(lib.actors.length, before + 1);
      expect(slot.picked!.id, startsWith('a_'));
      expect(slot.picked!.name, '新人');
    });

    test('collectActorIds：自由文本精确吸附已有演员，不重复建实体', () {
      final c = MovieEditController();
      addTearDown(c.dispose);
      lib.addActor(actor('a_7', '测试演员甲'));
      c.actorSlots.add(ActorSlot(ctrl: TextEditingController(text: '测试演员甲')));
      final before = lib.actors.length;

      final ids = c.collectActorIds(lib);

      expect(ids, ['a_7']);
      expect(lib.actors.length, before);
      expect(c.actorSlots.first.picked!.id, 'a_7');
    });

    test('collectActorIds：库里没有 → 兜底新建并带上检索头像', () {
      final c = MovieEditController();
      addTearDown(c.dispose);
      c.actorSlots.add(ActorSlot(
        ctrl: TextEditingController(text: '测试演员乙'),
        avatarUrl: 'https://img/face.jpg',
      ));

      final ids = c.collectActorIds(lib);

      expect(ids, hasLength(1));
      final created = lib.actors.firstWhere((a) => a.id == ids!.first);
      expect(created.name, '测试演员乙');
      expect(created.avatar!.remoteUrl, 'https://img/face.jpg');
    });

    test('collectActorIds：空槽位跳过，全空返回 null，重复 id 去重', () {
      final c = MovieEditController();
      addTearDown(c.dispose);

      c.actorSlots.add(ActorSlot());
      expect(c.collectActorIds(lib), isNull);

      c.actorSlots.add(ActorSlot(ctrl: TextEditingController(text: '甲')));
      c.actorSlots.add(ActorSlot(ctrl: TextEditingController(text: '甲')));
      final ids = c.collectActorIds(lib);
      expect(ids, hasLength(1));
    });

    test('slotInitial / actorHue', () {
      final c = MovieEditController();
      addTearDown(c.dispose);
      final slot = ActorSlot();
      c.actorSlots.add(slot);

      expect(c.slotInitial(slot, 0), '1');
      slot.ctrl.text = '马修';
      expect(c.slotInitial(slot, 0), '马');

      expect(MovieEditController.actorHue('诺兰'), inInclusiveRange(0, 359));
      expect(MovieEditController.actorHue('诺兰'),
          MovieEditController.actorHue('诺兰'));
    });
  });

  group('MovieEditController · 海报预览与保存', () {
    test('编辑态未改动 → 沿用原图；无图 → null', () {
      final poster = MediaRef.network('https://img/p.jpg');
      final c = MovieEditController(
        movieId: 'm_1',
        initialMovie: sampleMovie(poster: poster),
      );
      addTearDown(c.dispose);
      expect(c.previewPosterMedia, same(poster));

      final blank = MovieEditController();
      addTearDown(blank.dispose);
      expect(blank.previewPosterMedia, isNull);
    });

    test('改动后填 URL → 网络图；清空 → 占位', () {
      final c = MovieEditController();
      addTearDown(c.dispose);

      c.posterEdited = true;
      c.posterUrlCtrl.text = 'https://img/new.jpg';
      expect(c.previewPosterMedia!.remoteUrl, 'https://img/new.jpg');

      c.posterUrlCtrl.text = '  ';
      expect(c.previewPosterMedia, isNull);
    });

    test('composeMovie：URL 海报在内存模式下退化为纯网络引用', () async {
      final c = MovieEditController();
      addTearDown(c.dispose);
      c.titleCtrl.text = '片名';
      c.posterEdited = true;
      c.posterUrlCtrl.text = 'https://img/new.jpg';

      final m = await c.composeMovie(LibraryProvider());

      expect(m!.poster!.remoteUrl, 'https://img/new.jpg');
      expect(m.poster!.localFile, isNull);
    });

    test('composeMovie：移除海报 → null；未动过 → 沿用原图', () async {
      final poster = MediaRef.network('https://img/p.jpg');
      final c = MovieEditController(
        movieId: 'm_1',
        initialMovie: sampleMovie(poster: poster),
      );
      addTearDown(c.dispose);

      expect((await c.composeMovie(LibraryProvider()))!.poster, same(poster));

      c.posterEdited = true;
      c.posterUrlCtrl.clear();
      expect((await c.composeMovie(LibraryProvider()))!.poster, isNull);
    });
  });

  group('MovieEditController · 检索回填快照', () {
    test('applyCastDetail：追加主演槽位、跳过同名、非空才覆盖快照', () {
      final c = MovieEditController();
      addTearDown(c.dispose);
      c.actorSlots.add(ActorSlot(ctrl: TextEditingController(text: '马修')));

      c.applyCastDetail(
        const [
          CastMember(name: '马修', profilePath: 'https://img/a.jpg'),
          CastMember(name: '安妮', profilePath: 'https://img/b.jpg'),
        ],
        const ['https://img/s1.jpg', 'https://img/s2.jpg'],
      );

      expect(c.actorSlots.length, 2); // 同名不重复追加
      expect(c.actorSlots.last.ctrl.text, '安妮');
      expect(c.actorSlots.last.avatarUrl, 'https://img/b.jpg');
      expect(c.cast, hasLength(2));
      expect(c.stills, hasLength(2));
      expect(c.stills!.first.remoteUrl, 'https://img/s1.jpg');
    });

    test('applyCastDetail：详情为空时不覆盖既有快照', () {
      final c = MovieEditController(
        movieId: 'm_1',
        initialMovie: sampleMovie(
          cast: const [CastMember(name: '原班')],
          stills: [MediaRef.network('https://img/keep.jpg')],
        ),
      );
      addTearDown(c.dispose);

      c.applyCastDetail(const [], const []);

      expect(c.cast!.first.name, '原班');
      expect(c.stills!.first.remoteUrl, 'https://img/keep.jpg');
    });
  });

  group('MovieEditController · 生命周期', () {
    test('dispose 释放全部表单控制器与槽位', () {
      final c = MovieEditController();
      c.actorSlots.add(ActorSlot());
      final slotCtrl = c.actorSlots.first.ctrl;
      c.dispose();

      expect(() => c.titleCtrl.text = 'x', throwsFlutterError);
      expect(() => slotCtrl.text = 'x', throwsFlutterError);
      expect(() => c.directorFocus.dispose(), throwsFlutterError);
    });
  });
}
