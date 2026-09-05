import 'package:flutter_test/flutter_test.dart';
import 'package:moying/models/actor.dart';
import 'package:moying/models/book.dart';
import 'package:moying/models/media_ref.dart';
import 'package:moying/models/movie.dart';

/// P1 序列化 round-trip 测试
///
/// 覆盖：MediaRef / Actor / Book / Movie 的 toJson→fromJson 往返一致、
/// 空字段省略、缺键默认值、枚举与 DateTime 保真、copyWith sentinel 新参数。
void main() {
  group('MediaRef 序列化', () {
    test('网络图 round-trip', () {
      final ref = MediaRef.network('https://example.com/p.jpg');
      expect(MediaRef.fromJson(ref.toJson()), ref);
      expect(ref.isNetwork, isTrue);
    });

    test('本地图 round-trip', () {
      final ref = MediaRef.local('m3.jpg');
      expect(MediaRef.fromJson(ref.toJson()), ref);
      expect(ref.isLocal, isTrue);
    });

    test('全空 toJson 为空 map，fromJson 缺键得空引用', () {
      const ref = MediaRef();
      expect(ref.toJson(), isEmpty);
      expect(MediaRef.fromJson(const {}), ref);
      expect(ref.isEmpty, isTrue);
    });
  });

  group('Actor 序列化', () {
    final now = DateTime(2026, 9, 5, 10, 30);

    test('全字段 round-trip', () {
      final actor = Actor(
        id: 'a_1',
        name: '马修·麦康纳',
        avatar: const MediaRef(remoteUrl: 'https://example.com/a.jpg'),
        bio: '美国演员，代表作《星际穿越》',
        createdAt: now,
      );
      expect(Actor.fromJson(actor.toJson()), actor);
    });

    test('最小字段 round-trip（无头像无简介）', () {
      final actor = Actor(id: 'a_2', name: '宫崎骏', createdAt: now);
      expect(Actor.fromJson(actor.toJson()), actor);
    });

    test('空字段 toJson 省略，不产生 null 值', () {
      final json =
          Actor(id: 'a_3', name: '张三', createdAt: now).toJson();
      expect(json.containsKey('avatar'), isFalse);
      expect(json.containsKey('bio'), isFalse);
      expect(json.values.any((v) => v == null), isFalse);
    });

    test('copyWith sentinel：省略保留、null 清空', () {
      final avatar = MediaRef.local('a.jpg');
      final actor = Actor(
        id: 'a_4',
        name: '李四',
        avatar: avatar,
        bio: '简介',
        createdAt: now,
      );
      expect(actor.copyWith(name: '李四四').avatar, avatar);
      expect(actor.copyWith(avatar: null).avatar, isNull);
      expect(actor.copyWith(bio: null).bio, isNull);
    });
  });

  group('Book 序列化', () {
    test('全字段 round-trip', () {
      final book = Book(
        id: 'b1',
        title: '三体',
        author: '刘慈欣',
        totalPages: 302,
        createdAt: DateTime(2026, 1, 1, 9, 0),
        currentPage: 150,
        status: BookStatus.reading,
        coverHue: 210,
        rating: 4.5,
        year: 2008,
        emoji: '🛸',
        category: '科幻',
        description: '地球文明向宇宙发出的第一声啼鸣',
        notes: '黑暗森林法则震撼',
        startedAt: DateTime(2026, 1, 2),
        finishedAt: DateTime(2026, 2, 3),
        cover: const MediaRef(remoteUrl: 'https://example.com/cover.jpg'),
        source: 'googleBooks:Q0YPAQAAQBAJ',
      );
      expect(Book.fromJson(book.toJson()), book);
    });

    test('最小 json 缺键 → 默认值恢复', () {
      final book = Book.fromJson({
        'id': 'b2',
        'title': '无人生还',
        'author': '阿加莎',
        'totalPages': 264,
        'createdAt': DateTime(2026, 3, 1).toIso8601String(),
      });
      expect(book.currentPage, 0);
      expect(book.status, BookStatus.planToRead);
      expect(book.coverHue, 250);
      expect(book.rating, isNull);
      expect(book.cover, isNull);
      expect(book.source, isNull);
    });

    test('空字段 toJson 省略，不产生 null 值', () {
      final book = Book(
        id: 'b3',
        title: 't',
        author: 'a',
        totalPages: 10,
        createdAt: DateTime(2026, 5, 1),
      );
      final json = book.toJson();
      for (final key in [
        'rating', 'year', 'emoji', 'category', 'description', 'notes',
        'startedAt', 'finishedAt', 'cover', 'source',
      ]) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
      expect(json.values.any((v) => v == null), isFalse);
    });

    test('copyWith sentinel：cover/source 省略保留、null 清空', () {
      final cover = MediaRef.local('b.jpg');
      final book = Book(
        id: 'b4',
        title: 't',
        author: 'a',
        totalPages: 1,
        createdAt: DateTime(2026, 5, 1),
        cover: cover,
        source: 'x',
      );
      expect(book.copyWith(title: 't2').cover, cover);
      expect(book.copyWith(cover: null).cover, isNull);
      expect(book.copyWith(source: null).source, isNull);
    });

    test('DateTime 本地时间 round-trip 不丢时刻', () {
      final t = DateTime(2026, 9, 5, 14, 25, 36, 123, 456);
      final json = Book(
        id: 'b5',
        title: 't',
        author: 'a',
        totalPages: 1,
        createdAt: t,
      ).toJson();
      expect(DateTime.parse(json['createdAt'] as String), t);
    });
  });

  group('Movie 序列化', () {
    test('全字段 round-trip', () {
      final movie = Movie(
        id: 'm1',
        title: '星际穿越',
        year: 2014,
        englishTitle: 'Interstellar',
        director: '克里斯托弗·诺兰',
        status: MovieStatus.rated,
        rating: 4.9,
        coverHue: 215,
        emoji: '🌌',
        releaseDate: DateTime(2014, 11, 7),
        watchDate: DateTime(2023, 11, 5),
        duration: 169,
        genres: ['科幻', '冒险'],
        description: 'desc',
        review: 'review',
        actorIds: ['a_1', 'a_2'],
        poster: const MediaRef(localFile: 'm1.jpg'),
        source: 'tmdb:157336',
      );
      expect(Movie.fromJson(movie.toJson()), movie);
    });

    test('最小 json 缺键 → 默认值恢复', () {
      final movie = Movie.fromJson({
        'id': 'm2',
        'title': 't',
        'year': 2020,
      });
      expect(movie.status, MovieStatus.watchlist);
      expect(movie.coverHue, 165);
      expect(movie.genres, isNull);
      expect(movie.actorIds, isNull);
      expect(movie.poster, isNull);
      expect(movie.source, isNull);
    });

    test('空字段 toJson 省略，不产生 null 值', () {
      final json = const Movie(id: 'm3', title: 't', year: 2020).toJson();
      for (final key in [
        'englishTitle', 'director', 'rating', 'emoji', 'releaseDate',
        'watchDate', 'duration', 'genres', 'description', 'review',
        'actorIds', 'poster', 'source',
      ]) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
      expect(json.values.any((v) => v == null), isFalse);
    });

    test('列表字段非 null 即写（空数组与 null 语义不同）', () {
      final json = const Movie(
        id: 'm4',
        title: 't',
        year: 2020,
        genres: [],
        actorIds: [],
      ).toJson();
      expect(json['genres'], isEmpty);
      expect(json['actorIds'], isEmpty);
    });

    test('copyWith sentinel：poster/source/actorIds 省略保留、null 清空', () {
      final poster = MediaRef.local('p.jpg');
      final movie = Movie(
        id: 'm5',
        title: 't',
        year: 2020,
        actorIds: const ['a_1'],
        poster: poster,
        source: 's',
      );
      expect(movie.copyWith(title: 't2').poster, poster);
      expect(movie.copyWith(actorIds: null).actorIds, isNull);
      expect(movie.copyWith(poster: null).poster, isNull);
      expect(movie.copyWith(source: null).source, isNull);
    });
  });
}
