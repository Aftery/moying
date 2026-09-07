import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moying/data/library_store.dart';
import 'package:moying/data/mock_data.dart';
import 'package:moying/models/book.dart';

void main() {
  late Directory tmpDir;

  LibraryStore makeStore(Directory dir) => LibraryStore(
        dir,
        seed: LibrarySnapshot(
          books: kAllBooks,
          movies: kMovieList,
          actors: kActors,
        ),
      );

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('moying_store_test');
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  group('引用完整性（seed 数据不变量）', () {
    test('每部电影的 actorIds 都指向存在的演员', () {
      final actorIds = kActors.map((a) => a.id).toSet();
      for (final movie in kMovieList) {
        for (final id in movie.actorIds ?? const <String>[]) {
          expect(actorIds.contains(id), isTrue,
              reason: '电影 ${movie.id} 引用了不存在的演员 $id');
        }
      }
    });

    test('seed 演员无重复 id', () {
      expect(kActors.map((a) => a.id).toSet().length, kActors.length);
    });
  });

  group('首启 seed', () {
    test('空目录 load：返回 seed 数据且三集合文件落盘', () async {
      final store = makeStore(tmpDir);
      final snap = await store.load();

      expect(snap.books.length, kAllBooks.length);
      expect(snap.movies.length, kMovieList.length);
      expect(snap.actors.length, kActors.length);
      expect(snap.books, everyElement(isA<Book>()));
      expect(File('${tmpDir.path}/books.json').existsSync(), isTrue);
      expect(File('${tmpDir.path}/movies.json').existsSync(), isTrue);
      expect(File('${tmpDir.path}/actors.json').existsSync(), isTrue);
    });

    test('v0.9.0 首启空库：空 seed 时返回空三集合且文件正常落盘', () async {
      final store = LibraryStore(
        tmpDir,
        seed: const LibrarySnapshot(books: [], movies: [], actors: []),
      );
      final snap = await store.load();

      expect(snap.books, isEmpty);
      expect(snap.movies, isEmpty);
      expect(snap.actors, isEmpty);
      // 三集合文件照常落盘，二次启动走正常读取路径（不会再碰 seed）
      expect(File('${tmpDir.path}/books.json').existsSync(), isTrue);
      expect(File('${tmpDir.path}/movies.json').existsSync(), isTrue);
      expect(File('${tmpDir.path}/actors.json').existsSync(), isTrue);

      final reload = await store.load();
      expect(reload.books, isEmpty);
      expect(reload.movies, isEmpty);
      expect(reload.actors, isEmpty);
    });

    test('落盘文件带 schemaVersion:2 头（v1 仍可读，见旧数据兼容组）', () async {
      await makeStore(tmpDir).load();
      final root =
          jsonDecode(File('${tmpDir.path}/books.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(root['schemaVersion'], 2);
      expect(root['items'], isA<List<dynamic>>());
    });

    test('文件存在时走读盘路径（不是 seed 兜底）', () async {
      // 手工写一个只含 1 本书的 books.json，其余文件缺失
      final b = kAllBooks.first;
      File('${tmpDir.path}/books.json').writeAsStringSync(jsonEncode({
        'schemaVersion': 1,
        'items': [b.toJson()],
      }));
      final snap = await makeStore(tmpDir).load();

      expect(snap.books.length, 1); // 读盘所得，不是 12 本 seed
      expect(snap.movies.length, kMovieList.length); // 缺失的集合由 seed 补
      expect(snap.actors.length, kActors.length);
    });
  });

  group('二次启动读盘', () {
    test('删除过的书不复活（seed 只发生一次）', () async {
      final store = makeStore(tmpDir);
      final snap = await store.load();

      // 删一本书并落盘
      final remaining =
          snap.books.where((b) => b.id != kAllBooks.first.id).toList();
      await store.saveBooks(remaining);

      // 模拟重启：新 store 实例、同一目录
      final snap2 = await makeStore(tmpDir).load();
      expect(snap2.books.length, kAllBooks.length - 1);
      expect(snap2.books.any((b) => b.id == kAllBooks.first.id), isFalse,
          reason: '删除的书被 seed 复活了');
    });

    test('update round-trip：改动生效且未改字段原样保留', () async {
      final store = makeStore(tmpDir);
      final snap = await store.load();

      final original = snap.books.first;
      final edited =
          original.copyWith(rating: 4.5, notes: '仅改评分和笔记');
      final updated =
          snap.books.map((b) => b.id == original.id ? edited : b).toList();
      await store.saveBooks(updated);

      final reloaded = await makeStore(tmpDir).load();
      final after = reloaded.books.firstWhere((b) => b.id == original.id);
      expect(after.rating, 4.5);
      expect(after.notes, '仅改评分和笔记');
      // 未改字段原样保留（sentinel copyWith 语义的落盘对应物）
      expect(after.title, original.title);
      expect(after.author, original.author);
      expect(after.totalPages, original.totalPages);
      expect(after.createdAt, original.createdAt);
      expect(after.startedAt, original.startedAt);
      expect(after.finishedAt, original.finishedAt);
    });

    test('电影与演员集合 round-trip 保持值相等', () async {
      final store = makeStore(tmpDir);
      final snap = await store.load();
      await store.saveMovies(snap.movies);
      await store.saveActors(snap.actors);

      final reloaded = await makeStore(tmpDir).load();
      expect(reloaded.movies, snap.movies);
      expect(reloaded.actors, snap.actors);
      // 读盘后的快照同样满足引用完整性
      final actorIds = reloaded.actors.map((a) => a.id).toSet();
      for (final m in reloaded.movies) {
        for (final id in m.actorIds ?? const <String>[]) {
          expect(actorIds.contains(id), isTrue,
              reason: '读盘后电影 ${m.id} 悬空引用 $id');
        }
      }
    });
  });

  group('容错与校验', () {
    test('JSON 损坏：隔离坏文件并回退空列表（不白屏）', () async {
      await makeStore(tmpDir).load();
      File('${tmpDir.path}/books.json')
          .writeAsStringSync('{"schemaVersion": 1, "items": [半截');
      final snap = await makeStore(tmpDir).load();
      expect(snap.books, isEmpty);
      expect(File('${tmpDir.path}/books.json').existsSync(), isFalse);
      final corrupted = tmpDir.listSync().where((e) => e.path.contains('.corrupt-'));
      expect(corrupted, isNotEmpty);
    });

    test('schemaVersion 不符：隔离坏文件并回退空列表', () async {
      await makeStore(tmpDir).load();
      File('${tmpDir.path}/books.json').writeAsStringSync(jsonEncode({
        'schemaVersion': 99,
        'items': <Map<String, dynamic>>[],
      }));
      final snap = await makeStore(tmpDir).load();
      expect(snap.books, isEmpty);
      expect(File('${tmpDir.path}/books.json').existsSync(), isFalse);
      final corrupted = tmpDir.listSync().where((e) => e.path.contains('.corrupt-'));
      expect(corrupted, isNotEmpty);
    });

    test('顶层不是对象：隔离坏文件并回退空列表', () async {
      await makeStore(tmpDir).load();
      File('${tmpDir.path}/books.json').writeAsStringSync('[1,2,3]');
      final snap = await makeStore(tmpDir).load();
      expect(snap.books, isEmpty);
      expect(File('${tmpDir.path}/books.json').existsSync(), isFalse);
      final corrupted = tmpDir.listSync().where((e) => e.path.contains('.corrupt-'));
      expect(corrupted, isNotEmpty);
    });
  });

  group('图片目录操作', () {
    test('copyImage 复制进 images/ 并返回相对文件名', () async {
      final store = makeStore(tmpDir);
      final src = File('${tmpDir.path}/src.jpg');
      await src.writeAsBytes([1, 2, 3]);

      final name = await store.copyImage(src, 'm3');
      expect(name, 'm3.jpg');
      final dest = File('${tmpDir.path}/images/m3.jpg');
      expect(await dest.exists(), isTrue);
      expect(await dest.readAsBytes(), [1, 2, 3]);
    });

    test('同 id 重传覆盖旧图', () async {
      final store = makeStore(tmpDir);
      final src1 = File('${tmpDir.path}/a.png');
      final src2 = File('${tmpDir.path}/b.png');
      await src1.writeAsBytes([1]);
      await src2.writeAsBytes([2, 2]);

      final n1 = await store.copyImage(src1, 'm1');
      final n2 = await store.copyImage(src2, 'm1');
      expect(n1, n2); // 同名覆盖
      final dest = File('${tmpDir.path}/images/m1.png');
      expect(await dest.readAsBytes(), [2, 2]);
    });

    test('deleteImage 删除存在文件，静默容忍不存在', () async {
      final store = makeStore(tmpDir);
      final src = File('${tmpDir.path}/a.jpg');
      await src.writeAsBytes([1]);
      final name = await store.copyImage(src, 'm1');

      await store.deleteImage(name);
      expect(File('${tmpDir.path}/images/m1.jpg').existsSync(), isFalse);
      // 不存在的文件不抛
      await store.deleteImage(name);
    });

    test('目录穿越路径被拒绝', () async {
      final store = makeStore(tmpDir);
      await expectLater(store.deleteImage('../evil.json'),
          throwsA(isA<StoreException>()));
      await expectLater(store.deleteImage('a/b.jpg'),
          throwsA(isA<StoreException>()));
    });
  });

  group('合并写', () {
    test('同 tick 连续多次 save：flush 前磁盘仍是旧内容，flush 后为最后状态', () async {
      final store = makeStore(tmpDir);
      await store.load(); // 首启 seed 落盘
      final before = File('${tmpDir.path}/books.json').readAsStringSync();

      // fire-and-forget 连续 5 次修改（模拟快速连续保存），不逐个 await
      var list = List.of(kAllBooks);
      for (var i = 0; i < 5; i++) {
        list = [
          for (final b in list)
            b.id == list.first.id ? b.copyWith(title: '连改-$i') : b,
        ];
        unawaited(store.saveBooks(list));
      }
      // 同步段内磁盘仍是旧内容（pending 尚未冲刷）
      expect(File('${tmpDir.path}/books.json').readAsStringSync(), before);

      await store.flush();
      final root = jsonDecode(
              File('${tmpDir.path}/books.json').readAsStringSync())
          as Map<String, dynamic>;
      final items = root['items'] as List<dynamic>;
      expect(items.length, kAllBooks.length);
      final first =
          Book.fromJson(items.first as Map<String, dynamic>);
      expect(first.title, '连改-4'); // last-write-wins，只保留最终状态
      // 无 .tmp 残留
      final tmps = tmpDir
          .listSync()
          .where((e) => e.path.endsWith('.tmp'));
      expect(tmps, isEmpty);
    });

    test('await saveXxx 返回即已落盘（保留原契约）', () async {
      final store = makeStore(tmpDir);
      await store.load();
      await store.saveBooks(kAllBooks.sublist(1));
      final root = jsonDecode(
              File('${tmpDir.path}/books.json').readAsStringSync())
          as Map<String, dynamic>;
      expect((root['items'] as List<dynamic>).length, kAllBooks.length - 1);
    });

    test('无待写内容时 flush 为无害空冲刷', () async {
      final store = makeStore(tmpDir);
      await store.load();
      await store.flush(); // 不抛、不写坏文件
      final root = jsonDecode(
              File('${tmpDir.path}/books.json').readAsStringSync())
          as Map<String, dynamic>;
      expect((root['items'] as List<dynamic>).length, kAllBooks.length);
    });
  });
}
