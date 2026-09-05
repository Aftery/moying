import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moying/data/library_store.dart';
import 'package:moying/data/mock_data.dart';
import 'package:moying/models/actor.dart';
import 'package:moying/models/book.dart';
import 'package:moying/models/movie.dart';
import 'package:moying/providers/library_provider.dart';

void main() {
  late Directory tmpDir;

  /// 临时目录上的持久 Provider（模拟手机/桌面接入）
  Future<LibraryProvider> makePersistentProvider() async {
    final store = LibraryStore(
      tmpDir,
      seed: LibrarySnapshot(
        books: kAllBooks,
        movies: kMovieList,
        actors: kActors,
      ),
    );
    final provider = LibraryProvider(store: store);
    await provider.init();
    return provider;
  }

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('moying_provider_test');
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  group('内存模式（无 store）', () {
    test('默认构造 = 内存 mock，isPersistent=false', () {
      final p = LibraryProvider();
      expect(p.isPersistent, isFalse);
      expect(p.books.length, kAllBooks.length);
      expect(p.movieList.length, kMovieList.length);
      expect(p.actors.length, kActors.length);
    });

    test('写操作只改内存，不产生任何磁盘文件', () async {
      final p = LibraryProvider();
      p.addBook(_newBook('临时书'));
      expect(p.books.first.title, '临时书');
      await p.flush(); // no-op
      expect(File('${tmpDir.path}/books.json').existsSync(), isFalse);
      expect(File('${tmpDir.path}/movies.json').existsSync(), isFalse);
      expect(File('${tmpDir.path}/actors.json').existsSync(), isFalse);
    });
  });

  group('持久模式：书籍重启保持', () {
    test('新增的书在重启后仍在（seed 不复活、不丢新数据）', () async {
      final p = await makePersistentProvider();
      final added = _newBook('持久化新书');
      p.addBook(added);
      await p.flush();

      final p2 = await makePersistentProvider(); // 模拟重启
      expect(p2.books.length, kAllBooks.length + 1);
      expect(p2.books.first.id, added.id);
      expect(p2.books.first.title, '持久化新书');
    });

    test('删除的书重启后不复活', () async {
      final p = await makePersistentProvider();
      p.deleteBook(kAllBooks.first.id);
      await p.flush();

      final p2 = await makePersistentProvider();
      expect(p2.books.any((b) => b.id == kAllBooks.first.id), isFalse);
    });

    test('更新重启后保留（含未改字段）', () async {
      final p = await makePersistentProvider();
      final original = p.books.first;
      p.updateBook(original.copyWith(
        rating: 4.5,
        notes: '持久化后仍记得',
        finishedAt: DateTime(2026, 6, 1),
      ));
      await p.flush();

      final p2 = await makePersistentProvider();
      final after = p2.books.firstWhere((b) => b.id == original.id);
      expect(after.rating, 4.5);
      expect(after.notes, '持久化后仍记得');
      expect(after.finishedAt, DateTime(2026, 6, 1));
      expect(after.title, original.title); // 未改字段保留
      expect(after.startedAt, original.startedAt);
    });
  });

  group('持久模式：电影重启保持', () {
    test('新增/更新/删除电影均落盘', () async {
      final p = await makePersistentProvider();
      const m = Movie(
        id: 'm_new_persist',
        title: '新电影持久化',
        year: 2026,
        status: MovieStatus.watchlist,
      );
      p.addMovie(m);
      await p.flush();

      final p2 = await makePersistentProvider();
      expect(p2.movieList.any((x) => x.id == m.id), isTrue);

      // 更新后重启
      p2.updateMovie(p2.movieList.firstWhere((x) => x.id == m.id)
          .copyWith(rating: 4.2, review: '补一条影评'));
      await p2.flush();
      final p3 = await makePersistentProvider();
      final updated = p3.movieList.firstWhere((x) => x.id == m.id);
      expect(updated.rating, 4.2);
      expect(updated.review, '补一条影评');

      // 删除后重启
      p3.deleteMovie(m.id);
      await p3.flush();
      final p4 = await makePersistentProvider();
      expect(p4.movieList.any((x) => x.id == m.id), isFalse);
    });
  });

  group('持久模式：演员 CRUD 与反查', () {
    test('新增演员重启后仍在', () async {
      final p = await makePersistentProvider();
      p.addActor(Actor(
        id: 'a_persist',
        name: '测试演员甲',
        createdAt: DateTime(2026, 9, 1),
      ));
      await p.flush();

      final p2 = await makePersistentProvider();
      expect(p2.actors.any((a) => a.id == 'a_persist'), isTrue);
    });

    test('被电影引用的演员禁止删除', () async {
      final p = await makePersistentProvider();
      final referenced = kActors.first; // seed 演员，被 mock 电影引用
      expect(p.moviesByActor(referenced.id), isNotEmpty);
      expect(p.deleteActor(referenced.id), isFalse);
      // 演员仍在，引用它的电影未被波及
      expect(p.actors.any((a) => a.id == referenced.id), isTrue);
      expect(p.moviesByActor(referenced.id).isNotEmpty, isTrue);
    });

    test('先删电影再删演员：引用清空后可删', () async {
      final p = await makePersistentProvider();
      final referenced = kActors.first;
      for (final m in p.moviesByActor(referenced.id).toList()) {
        p.deleteMovie(m.id);
      }
      expect(p.moviesByActor(referenced.id), isEmpty);
      expect(p.deleteActor(referenced.id), isTrue);
      await p.flush();

      final p2 = await makePersistentProvider();
      expect(p2.actors.any((a) => a.id == referenced.id), isFalse);
    });

    test('moviesByActor 反查与 actorsByIds 顺序保留/缺失跳过', () async {
      final p = await makePersistentProvider();
      // 反查：某演员的作品数 = mock 中引用它的电影数
      final target = kActors.first;
      final expectedCount =
          kMovieList.where((m) => m.actorIds?.contains(target.id) ?? false).length;
      expect(p.moviesByActor(target.id).length, expectedCount);

      // actorsByIds：按传入顺序返回，未知 id 静默跳过
      final ids = [kActors[1].id, 'no_such_id', kActors[0].id];
      final resolved = p.actorsByIds(ids);
      expect(resolved.length, 2);
      expect(resolved[0].id, kActors[1].id);
      expect(resolved[1].id, kActors[0].id);
    });
  });

  group('持久模式：UI 写操作语义', () {
    test('UI 的 void 写操作（不 await）+ 退出前 flush 后重启可见', () async {
      final p = await makePersistentProvider();
      // UI 场景：addBook 是 void，调用点不 await（合并写后台冲刷）
      p.addBook(_newBook('后台落盘书'));
      // 退出前冲刷（等同 main 生命周期钩子）→ 模拟重启
      await p.flush();
      final p2 = await makePersistentProvider();
      expect(p2.books.any((b) => b.title == '后台落盘书'), isTrue);
    });
  });
}

Book _newBook(String title) => Book(
      id: 'b_${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      author: '作者甲',
      totalPages: 100,
      createdAt: DateTime(2026, 9, 5),
    );
