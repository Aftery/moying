import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:moying/data/library_store.dart';
import 'package:moying/data/mock_data.dart';
import 'package:moying/models/sync_settings.dart';
import 'package:moying/providers/library_provider.dart';
import 'package:moying/providers/sync_provider.dart';
import 'package:moying/screens/data_sync_screen.dart';
import 'package:moying/services/backup_service.dart';
import 'package:moying/services/secure_storage_service.dart';
import 'package:moying/services/webdav_client.dart';
import 'helpers/fake_webdav_client.dart';

/// P5 数据同步/备份：备份往返、版本校验、路径拼接、fake WebDAV、
/// SyncProvider 动作链、页面禁用态与开关联动。

LibrarySnapshot _seed() => LibrarySnapshot(
      books: kAllBooks,
      movies: kMovieList,
      actors: kActors,
    );

/// 建一个已初始化（四集合文件齐全）的 store，数据目录用子目录隔离
Future<LibraryStore> _makeStore(Directory root, String name) async {
  final dir = Directory('${root.path}${Platform.pathSeparator}$name');
  final store = LibraryStore(dir, seed: _seed());
  await store.load();
  await store.loadProfile();
  return store;
}

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('moying_sync_test');
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  group('BackupService 备份/还原', () {
    test('JSON 备份（不含图）往返：新 store 还原后数据一致', () async {
      final src = await _makeStore(tmpDir, 'src');
      final bytes =
          await BackupService(store: src).buildBackup(includeImages: false);

      // ZIP 魔数不应出现（JSON 文本备份）
      expect(bytes[0] == 0x50 && bytes[1] == 0x4B, isFalse);

      final dst = await _makeStore(tmpDir, 'dst');
      await BackupService(store: dst).restoreBackup(bytes);

      final snap = await dst.load();
      final profile = await dst.loadProfile();
      expect(snap.books.length, kAllBooks.length);
      expect(snap.movies.length, kMovieList.length);
      expect(snap.movies.first.title, kMovieList.first.title);
      expect(profile.nickname, isNotEmpty);
    });

    test('ZIP 备份（含图）往返：图片随包还原，manifest 记录张数', () async {
      final src = await _makeStore(tmpDir, 'src');
      await src.imagesDir.create(recursive: true);
      await src
          .imageFileByName('poster.jpg')
          .writeAsBytes(Uint8List.fromList([1, 2, 3, 4]));

      final bytes =
          await BackupService(store: src).buildBackup(includeImages: true);
      expect(bytes[0] == 0x50 && bytes[1] == 0x4B, isTrue); // ZIP 魔数

      final manifest = await BackupService(store: src).peekBackup(bytes);
      expect(manifest.imageCount, 1);
      expect(manifest.counts['books.json'], kAllBooks.length);

      final dst = await _makeStore(tmpDir, 'dst');
      await BackupService(store: dst).restoreBackup(bytes);

      final restored = await dst.imageFileByName('poster.jpg').readAsBytes();
      expect(restored, Uint8List.fromList([1, 2, 3, 4]));
    });

    test('恢复覆盖前保留现状快照 backup-pre-restore/', () async {
      final src = await _makeStore(tmpDir, 'src');
      final bytes =
          await BackupService(store: src).buildBackup(includeImages: false);

      final dst = await _makeStore(tmpDir, 'dst');
      await BackupService(store: dst).restoreBackup(bytes);

      final pre = File(
        '${dst.dataDir.path}${Platform.pathSeparator}'
        'backup-pre-restore${Platform.pathSeparator}books.json',
      );
      expect(pre.existsSync(), isTrue);
    });

    test('版本校验：过高/过低的 schemaVersion 拒绝恢复', () async {
      final dst = await _makeStore(tmpDir, 'dst');

      Uint8List crafted(int version) => Uint8List.fromList(utf8.encode(
            '{"manifest":{"schemaVersion":$version,"exportedAt":'
            '"2026-09-05T12:00:00.000","includeImages":false,"counts":{}'
            ',"imageCount":0},"data":{}}',
          ));

      expect(
        () => BackupService(store: dst).restoreBackup(crafted(3)),
        throwsA(isA<BackupException>()),
      );
      expect(
        () => BackupService(store: dst).restoreBackup(crafted(1)),
        throwsA(isA<BackupException>()),
      );
    });

    test('备份文件名时间戳：冒号换连字符，跨平台安全', () {
      final src = LibraryStore(
        Directory('${tmpDir.path}${Platform.pathSeparator}stamp'),
        seed: _seed(),
      );
      final name = BackupService(store: src)
          .backupFileStamp(DateTime(2026, 9, 5, 14, 30, 9));
      expect(name, 'moying-20260905-143009');
    });
  });

  group('SyncSettings', () {
    test('remoteDirUrl 斜杠边界自动补齐', () {
      expect(
        const SyncSettings(
          webdavUrl: 'https://dav.jianguoyun.com/dav',
        ).remoteDirUrl,
        'https://dav.jianguoyun.com/dav/墨影Backup/',
      );
      expect(
        const SyncSettings(
          webdavUrl: 'https://x.com/dav//',
          remoteFolder: '/myBackup//',
        ).remoteDirUrl,
        'https://x.com/dav/myBackup/',
      );
      expect(
        const SyncSettings(webdavUrl: 'https://x.com/dav', remoteFolder: '/')
            .remoteDirUrl,
        'https://x.com/dav/',
      );
    });

    test('settings.json 往返持久化，且不含密码字段', () async {
      final store = await _makeStore(tmpDir, 'settings');
      const settings = SyncSettings(
        webdavUrl: 'https://dav.example.com/dav',
        username: 'user@test.com',
        autoSync: true,
        onlyOnWifi: false,
      );
      await store.saveSettings(settings.copyWith(
        lastSyncAt: DateTime(2026, 9, 5, 10, 0),
      ));

      final raw = await store.fileInDataDir('settings.json').readAsString();
      expect(raw.contains('password'), isFalse); // 密码绝不落 settings.json

      final loaded = await store.loadSettings();
      expect(loaded.webdavUrl, settings.webdavUrl);
      expect(loaded.username, settings.username);
      expect(loaded.autoSync, isTrue);
      expect(loaded.onlyOnWifi, isFalse);
      expect(loaded.lastSyncAt, DateTime(2026, 9, 5, 10, 0));
      expect(loaded.remoteFolder, SyncSettings.defaultRemoteFolder);
    });
  });

  group('WebDAV 客户端', () {
    test('Fake：上传下载字节一致；listBackups 时间倒序；未存文件 404', () async {
      final fake = FakeWebDavClient();
      await fake.upload('moying-20260905-120000.json', Uint8List.fromList([9]));
      await fake.upload('moying-20260905-140000.json', Uint8List.fromList([1]));

      expect(await fake.download('moying-20260905-120000.json'),
          Uint8List.fromList([9]));
      expect(await fake.listBackups(), [
        'moying-20260905-140000.json',
        'moying-20260905-120000.json',
      ]);
      expect(
        () => fake.download('moying-20250101-000000.json'),
        throwsA(isA<WebDavException>()),
      );
    });
  });

  group('SyncProvider 动作链', () {
    Future<SyncProvider> makeSync(
      LibraryStore store, {
      FakeWebDavClient? client,
      SecureStorageService? secure,
    }) async {
      final library = LibraryProvider(store: store);
      await library.init();
      final sync = SyncProvider(
        store: store,
        library: library,
        secureStorage:
            secure ?? SecureStorageService(store: InMemorySecureStore()),
        clientFactory: client != null ? (s, p) => client : null,
        saveFile: (_, __) async => true,
      );
      await sync.loadSettings();
      return sync;
    }

    test('未配置时 uploadNow 抛 WebDavException', () async {
      final store = await _makeStore(tmpDir, 'unconfigured');
      final sync = await makeSync(store);
      expect(
        () => sync.uploadNow(),
        throwsA(isA<WebDavException>()),
      );
    });

    test('uploadNow：fake 收到备份字节，lastSyncAt 更新并落盘', () async {
      final store = await _makeStore(tmpDir, 'upload');
      final fake = FakeWebDavClient();
      final secure = SecureStorageService(store: InMemorySecureStore());
      await secure.saveWebDavPassword('user@test.com', 'pwd');

      final sync = await makeSync(store, client: fake, secure: secure);
      await sync.saveSettings(const SyncSettings(
        webdavUrl: 'https://dav.example.com/dav',
        username: 'user@test.com',
        includeImages: false,
      ));

      await sync.uploadNow();

      expect(fake.uploadCalls, 1);
      expect(fake.store.keys.single, startsWith('moying-'));
      expect(fake.store.keys.single.endsWith('.json'), isTrue);
      expect(sync.settings.lastSyncAt, isNotNull);
      expect(sync.lastError, isNull);

      // lastSyncAt 已持久化到 settings.json
      final reloaded = await store.loadSettings();
      expect(reloaded.lastSyncAt, isNotNull);
    });

    test('自动同步节流：刚同步过不再触发；autoSync 关闭不触发', () async {
      final store = await _makeStore(tmpDir, 'auto');
      final fake = FakeWebDavClient();
      final secure = SecureStorageService(store: InMemorySecureStore());
      await secure.saveWebDavPassword('user@test.com', 'pwd');

      final sync = await makeSync(store, client: fake, secure: secure);
      await sync.saveSettings(const SyncSettings(
        webdavUrl: 'https://dav.example.com/dav',
        username: 'user@test.com',
        autoSync: true,
      ));

      await sync.uploadNow();
      expect(fake.uploadCalls, 1);

      // 刚同步过（节流 1 小时内）→ 不再上传
      await sync.tryAutoSyncOnResume();
      expect(fake.uploadCalls, 1);

      // 关闭自动同步 → 不上传
      await sync.saveSettings(sync.settings.copyWith(autoSync: false));
      await sync.tryAutoSyncOnResume();
      expect(fake.uploadCalls, 1);
    });
  });

  group('DataSyncScreen 页面', () {
    Widget wrap(LibraryProvider lib, SyncProvider sync) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: lib),
            ChangeNotifierProvider.value(value: sync),
          ],
          child: const MaterialApp(home: DataSyncScreen()),
        );

    Finder rowSwitch(String title) => find.descendant(
          of: find.ancestor(
            of: find.text(title),
            matching: find.byType(ListTile),
          ),
          matching: find.byType(Switch),
        );

    testWidgets('未配置时动作按钮禁用，上次同步显示「从未同步」', (tester) async {
      final lib = LibraryProvider();
      final sync = SyncProvider(store: null, library: lib);
      await tester.pumpWidget(wrap(lib, sync));
      await tester.pumpAndSettle();

      expect(find.text('从未同步'), findsOneWidget);
      // .icon 构造产生私有子类，用谓词匹配（byType 是精确 runtimeType）
      final upload = tester.widget<FilledButton>(
        find
            .ancestor(
              of: find.text('立即备份'),
              matching: find.byWidgetPredicate((w) => w is FilledButton),
            )
            .first,
      );
      expect(upload.onPressed, isNull);
      final restore = tester.widget<OutlinedButton>(
        find
            .ancestor(
              of: find.text('从云端恢复'),
              matching: find.byWidgetPredicate((w) => w is OutlinedButton),
            )
            .first,
      );
      expect(restore.onPressed, isNull);
    });

    testWidgets('开关联动：仅 Wi-Fi 随自动同步灰显，切换后 settings 生效', (tester) async {
      // 同步偏好区在默认视口折叠线以下（懒列表未 build），放大视口
      tester.view.physicalSize = const Size(800, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final lib = LibraryProvider();
      final sync = SyncProvider(store: null, library: lib);
      await tester.pumpWidget(wrap(lib, sync));
      await tester.pumpAndSettle();

      // 默认 autoSync=false → 仅 Wi-Fi 开关禁用
      expect(tester.widget<Switch>(rowSwitch('仅 Wi-Fi 下同步')).onChanged, isNull);

      await tester.tap(rowSwitch('启动时自动同步'));
      await tester.pumpAndSettle();

      expect(sync.settings.autoSync, isTrue);
      // 解禁后开关可交互
      expect(
          tester.widget<Switch>(rowSwitch('仅 Wi-Fi 下同步')).onChanged, isNotNull);

      // 再关掉 → 重新灰显且值被保留（true）
      await tester.tap(rowSwitch('启动时自动同步'));
      await tester.pumpAndSettle();
      expect(sync.settings.autoSync, isFalse);
      expect(sync.settings.onlyOnWifi, isTrue);
    });
  });

  group('本地导出（选位置保存 + 含图开关）', () {
    Future<SyncProvider> makeExportSync(
      LibraryStore store, {
      required Future<bool> Function(String, Uint8List) saveFile,
    }) async {
      final library = LibraryProvider(store: store);
      await library.init();
      final sync = SyncProvider(
        store: store,
        library: library,
        secureStorage: SecureStorageService(store: InMemorySecureStore()),
        saveFile: saveFile,
      );
      await sync.loadSettings();
      return sync;
    }

    test('不含图：导出 .json，内容为有效备份', () async {
      final store = await _makeStore(tmpDir, 'exp-json');
      String? savedName;
      Uint8List? savedBytes;
      final sync = await makeExportSync(store, saveFile: (name, bytes) async {
        savedName = name;
        savedBytes = bytes;
        return true;
      });
      await sync.saveSettings(const SyncSettings(includeImages: false));

      final ok = await sync.exportLocal();

      expect(ok, isTrue);
      expect(savedName, startsWith('moying-'));
      expect(savedName, endsWith('.json'));
      // JSON 文本备份不应出现 ZIP 魔数
      expect(savedBytes![0] == 0x50 && savedBytes![1] == 0x4B, isFalse);
      final manifest =
          await BackupService(store: store).peekBackup(savedBytes!);
      expect(manifest.includeImages, isFalse);
    });

    test('含图：导出 .zip（PK 魔数），清单标记 includeImages', () async {
      final store = await _makeStore(tmpDir, 'exp-zip');
      String? savedName;
      Uint8List? savedBytes;
      final sync = await makeExportSync(store, saveFile: (name, bytes) async {
        savedName = name;
        savedBytes = bytes;
        return true;
      });
      await sync.saveSettings(const SyncSettings(includeImages: true));

      await sync.exportLocal();

      expect(savedName, endsWith('.zip'));
      expect(savedBytes![0] == 0x50 && savedBytes![1] == 0x4B, isTrue);
      final manifest =
          await BackupService(store: store).peekBackup(savedBytes!);
      expect(manifest.includeImages, isTrue);
    });

    test('用户取消选位置：saveFile 返回 false 透传', () async {
      final store = await _makeStore(tmpDir, 'exp-cancel');
      final sync = await makeExportSync(
        store,
        saveFile: (_, __) async => false,
      );

      expect(await sync.exportLocal(), isFalse);
    });
  });
}
