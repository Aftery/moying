import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:moying/data/library_store.dart';
import 'package:moying/models/actor.dart';
import 'package:moying/models/book.dart';
import 'package:moying/models/movie.dart';
import 'package:moying/models/sync_settings.dart';
import 'package:moying/providers/sync_provider.dart';
import 'package:moying/services/backup_service.dart';
import 'package:moying/services/merge_engine.dart';
import 'package:moying/services/snapshot_service.dart';
import 'package:moying/services/secure_storage_service.dart';
import 'package:moying/providers/library_provider.dart';
import 'helpers/fake_webdav_client.dart';

/// 记录级 LWW 合并引擎 + 同步前快照 + 旧数据（无 updatedAt）兼容

Book _book(String id, String title, DateTime updatedAt) => Book(
      id: id,
      title: title,
      author: '作者',
      totalPages: 100,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: updatedAt,
    );

Movie _movie(String id, String title, DateTime? updatedAt) => Movie(
      id: id,
      title: title,
      year: 2026,
      updatedAt: updatedAt,
    );

Actor _actor(String id, DateTime updatedAt) => Actor(
      id: id,
      name: '演员$id',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: updatedAt,
    );

void main() {
  group('mergeSnapshot：记录级 LWW', () {
    test('双端各自新增 → 并集，两侧都保留', () {
      final local = LibrarySnapshot(
        books: [_book('a', '本地A', DateTime(2026, 9, 1))],
        movies: const [],
        actors: const [],
      );
      final remote = LibrarySnapshot(
        books: [_book('b', '云端B', DateTime(2026, 9, 2))],
        movies: const [],
        actors: const [],
      );

      final r = mergeSnapshot(local: local, remote: remote);

      expect(r.snapshot.books.map((b) => b.id), ['a', 'b']);
      expect(r.localOnly, 1); // 云端并入
      expect(r.fromRemote, 0);
      expect(r.localKept, 0);
      expect(r.hasChanges, isTrue);
    });

    test('同 id 冲突：云端 updatedAt 较新 → 云端胜', () {
      final local = LibrarySnapshot(
        books: [_book('a', '本地旧版', DateTime(2026, 9, 1))],
        movies: const [],
        actors: const [],
      );
      final remote = LibrarySnapshot(
        books: [_book('a', '云端新版', DateTime(2026, 9, 5))],
        movies: const [],
        actors: const [],
      );

      final r = mergeSnapshot(local: local, remote: remote);

      expect(r.snapshot.books.single.title, '云端新版');
      expect(r.fromRemote, 1);
      expect(r.hasChanges, isTrue);
    });

    test('同 id 冲突：本地较新 → 保留本地', () {
      final local = LibrarySnapshot(
        books: [_book('a', '本地新版', DateTime(2026, 9, 6))],
        movies: const [],
        actors: const [],
      );
      final remote = LibrarySnapshot(
        books: [_book('a', '云端旧版', DateTime(2026, 9, 5))],
        movies: const [],
        actors: const [],
      );

      final r = mergeSnapshot(local: local, remote: remote);

      expect(r.snapshot.books.single.title, '本地新版');
      expect(r.localKept, 1);
      expect(r.hasChanges, isFalse);
    });

    test('updatedAt 完全相等 → 保留本地（确定性，避免抖动）', () {
      final t = DateTime(2026, 9, 5, 12, 0);
      final local = LibrarySnapshot(
        books: [_book('a', '本地', t)],
        movies: const [],
        actors: const [],
      );
      final remote = LibrarySnapshot(
        books: [_book('a', '云端', t)],
        movies: const [],
        actors: const [],
      );

      final r = mergeSnapshot(local: local, remote: remote);

      expect(r.snapshot.books.single.title, '本地');
      expect(r.localKept, 1);
    });

    test('Movie：updatedAt null（旧想看）让位于有值一端；双 null 保留本地', () {
      final local = LibrarySnapshot(
        movies: [_movie('m1', '本地未改', null), _movie('m2', '本地也未改', null)],
        books: const [],
        actors: const [],
      );
      final remote = LibrarySnapshot(
        movies: [_movie('m1', '云端改过', DateTime(2026, 9, 5))],
        books: const [],
        actors: const [],
      );

      final r = mergeSnapshot(local: local, remote: remote);

      expect(r.snapshot.movies.length, 2);
      expect(
        r.snapshot.movies.firstWhere((m) => m.id == 'm1').title,
        '云端改过',
      );
      expect(
        r.snapshot.movies.firstWhere((m) => m.id == 'm2').title,
        '本地也未改',
      );
    });

    test('三集合独立合并：Actor 冲突同样按 updatedAt 裁决', () {
      final local = LibrarySnapshot(
        books: const [],
        movies: const [],
        actors: [_actor('a1', DateTime(2026, 9, 1))],
      );
      final remote = LibrarySnapshot(
        books: const [],
        movies: const [],
        actors: [_actor('a1', DateTime(2026, 9, 3), )],
      );

      final r = mergeSnapshot(local: local, remote: remote);
      expect(r.fromRemote, 1);
    });
  });

  group('旧数据兼容（无 updatedAt 字段的 v1 集合文件）', () {
    test('Book.fromJson：无 updatedAt → 兜底为 createdAt', () {
      final json = {
        'id': 'b1',
        'title': '1984',
        'author': '奥威尔',
        'totalPages': 300,
        'createdAt': '2026-05-01T10:00:00.000',
        'currentPage': 0,
        'status': 'planToRead',
        'coverHue': 250,
      };
      final b = Book.fromJson(json);
      expect(b.updatedAt, DateTime.parse('2026-05-01T10:00:00.000'));
    });

    test('Movie.fromJson：无 updatedAt → null；toJson 不写该键', () {
      final json = {
        'id': 'm1',
        'title': '星际穿越',
        'year': 2014,
        'status': 'watchlist',
        'coverHue': 165,
      };
      final m = Movie.fromJson(json);
      expect(m.updatedAt, isNull);
      expect(m.toJson().containsKey('updatedAt'), isFalse);
    });

    test('Actor.fromJson：无 updatedAt → 兜底为 createdAt', () {
      final a = Actor.fromJson({
        'id': 'a1',
        'name': '马修',
        'createdAt': '2026-03-03T08:00:00.000',
      });
      expect(a.updatedAt, DateTime.parse('2026-03-03T08:00:00.000'));
    });

    test('LibraryStore：schemaVersion 1 的旧集合文件可读，写回落 v2 头', () async {
      final dir = await Directory.systemTemp.createTemp('moying_v1_test');
      addTearDown(() => dir.delete(recursive: true));
      final store = LibraryStore(
        dir,
        seed: const LibrarySnapshot(books: [], movies: [], actors: []),
      );
      await dir.create(recursive: true);
      await File('${dir.path}${Platform.pathSeparator}books.json').writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'items': [
            {
              'id': 'b1',
              'title': '旧数据',
              'author': '作者',
              'totalPages': 10,
              'createdAt': '2026-01-01T00:00:00.000',
              'currentPage': 0,
              'status': 'planToRead',
              'coverHue': 250,
            }
          ],
        }),
      );

      final snap = await store.load();
      expect(snap.books.single.title, '旧数据'); // 未被隔离

      await store.saveBooks(snap.books); // 触发写盘
      final head =
          jsonDecode(await File('${dir.path}${Platform.pathSeparator}books.json')
              .readAsString()) as Map<String, dynamic>;
      expect(head['schemaVersion'], 2); // 写回 v2 头
    });
  });

  group('SyncProvider LWW 集成（fake WebDAV）', () {
    late Directory tmpDir;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('moying_lww_test');
    });
    tearDown(() async {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });

    LibrarySnapshot seedOf(List<Book> books) =>
        LibrarySnapshot(books: books, movies: const [], actors: const []);

    Future<LibraryStore> makeStore(String name, List<Book> books) async {
      final store = LibraryStore(
        Directory('${tmpDir.path}${Platform.pathSeparator}$name'),
        seed: seedOf(books),
      );
      await store.load();
      await store.loadProfile();
      return store;
    }

    test('uploadNow：本地旧改 + 云端新改 → 云端胜并写回；云端独有并入；上传包含合并结果', () async {
      // 本地：A（旧改 9/1）、B（本地独有）
      final store = await makeStore('local', [
        _book('a', '本地旧版A', DateTime(2026, 9, 1)),
        _book('b', '本地B', DateTime(2026, 9, 1)),
      ]);
      // 云端：A（新改 9/5）、C（云端独有）
      final remoteStore = await makeStore('remote', [
        _book('a', '云端新版A', DateTime(2026, 9, 5)),
        _book('c', '云端C', DateTime(2026, 9, 2)),
      ]);
      final remoteBytes = await BackupService(store: remoteStore)
          .buildBackup(includeImages: false);

      final fake = FakeWebDavClient();
      await fake.upload('moying-20260901-000000.json', remoteBytes);

      final library = LibraryProvider(store: store);
      await library.init();
      final secure = SecureStorageService(store: InMemorySecureStore());
      await secure.saveWebDavPassword('user@test.com', 'pwd');
      final sync = SyncProvider(
        store: store,
        library: library,
        secureStorage: secure,
        clientFactory: (s, p) => fake,
        saveFile: (_, __) async => true,
      );
      await sync.loadSettings();
      await sync.saveSettings(const SyncSettings(
        webdavUrl: 'https://dav.example.com/dav',
        username: 'user@test.com',
        includeImages: false,
      ));

      await sync.uploadNow();

      // 合并结果写回本地库
      expect(library.books.map((b) => b.id), containsAll(['a', 'b', 'c']));
      expect(
        library.books.firstWhere((b) => b.id == 'a').title,
        '云端新版A',
      );
      // 合并统计
      expect(sync.lastMerge!.fromRemote, 1);
      expect(sync.lastMerge!.localOnly, 1);
      // 上传的包 = 合并后全量（3 本书）
      final uploaded = await BackupService(store: store)
          .extractSnapshot(fake.store.values.last);
      expect(uploaded.books.length, 3);

      // merge 前本地快照已生成
      final snapshots = await SnapshotService(store: store).list();
      expect(snapshots, isNotEmpty);
    });

    test('extractSnapshot：备份字节 → 三集合 round-trip', () async {
      final store = await makeStore('rt', [
        _book('a', '书A', DateTime(2026, 9, 1)),
      ]);
      await store.saveMovies([_movie('m1', '影M', DateTime(2026, 9, 2))]);
      await store.flush();
      final bytes =
          await BackupService(store: store).buildBackup(includeImages: false);

      final snap = await BackupService(store: store).extractSnapshot(bytes);
      expect(snap.books.single.title, '书A');
      expect(snap.movies.single.title, '影M');
      expect(snap.movies.single.updatedAt, DateTime(2026, 9, 2));
    });
  });
}
