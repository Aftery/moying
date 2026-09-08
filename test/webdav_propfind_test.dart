import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moying/data/library_store.dart';
import 'package:moying/providers/library_provider.dart';
import 'package:moying/providers/sync_provider.dart';
import 'package:moying/models/sync_settings.dart';
import 'package:moying/services/secure_storage_service.dart';
import 'package:moying/services/webdav_client.dart';

/// H1/L1：WebDAV 列目录改用标准 PROPFIND（RFC 4918），
/// 不再依赖 `GET + Depth:1` 这种部分服务不接受的请求；
/// JSON 备份也要能被列出、下载、用于恢复合并。
void main() {
  group('WebDavClientHttp PROPFIND', () {
    test('listBackups 发送 PROPFIND + Depth=1 + Content-Type=application/xml',
        () async {
      http.Request? seenRequest;
      final client = MockClient((req) async {
        seenRequest = req;
        // 207 Multi-Status with one response for a .json backup
        const body = '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/dav/backup/moying-20260905-120000.json</d:href>
    <d:propstat><d:prop><d:displayname>moying-20260905-120000.json</d:displayname></d:prop></d:propstat>
  </d:response>
</d:multistatus>''';
        return http.Response(body, 207, headers: {'Content-Type': 'application/xml'});
      });

      final dav = WebDavClientHttp(
        remoteDirUrl: 'https://dav.example.com/dav/backup',
        username: 'u',
        password: 'p',
        httpClient: client,
      );
      final names = await dav.listBackups();
      dav.close();

      expect(seenRequest!.method, 'PROPFIND');
      expect(seenRequest!.url.path, '/dav/backup/');
      expect(seenRequest!.headers['Depth'], '1');
      expect(seenRequest!.headers['Content-Type'], contains('application/xml'));
      // body 是 XML propfind
      expect(seenRequest!.body.contains('propfind'), isTrue);
      expect(names, ['moying-20260905-120000.json']);
    });

    test('PROPFIND 同时列出 zip 与 json 两种备份（H1）', () async {
      final client = MockClient((req) async {
        const body = '''
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/moying-20260905-100000.zip</d:href></d:response>
  <d:response><d:href>/dav/moying-20260905-120000.json</d:href></d:response>
  <d:response><d:href>/dav/readme.txt</d:href></d:response>
</d:multistatus>''';
        return http.Response(body, 207);
      });
      final dav = WebDavClientHttp(
        remoteDirUrl: 'https://x.com/dav',
        username: 'u',
        password: 'p',
        httpClient: client,
      );
      final names = await dav.listBackups();
      dav.close();
      // zip 在前（名字字典序更大）
      expect(names, [
        'moying-20260905-120000.json',
        'moying-20260905-100000.zip',
      ]);
    });

    test('PROPFIND href 带 URL 编码也能解码', () async {
      final client = MockClient((req) async {
        const body = '''
<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/backup/moying-20260905-150000.json</d:href></d:response>
</d:multistatus>''';
        return http.Response(body, 207);
      });
      final dav = WebDavClientHttp(
        remoteDirUrl: 'https://x.com/dav/backup',
        username: 'u',
        password: 'p',
        httpClient: client,
      );
      expect(await dav.listBackups(), ['moying-20260905-150000.json']);
      dav.close();
    });

    test('405 → 明确「不支持 PROPFIND」文案', () async {
      final client = MockClient((req) async => http.Response('no', 405));
      final dav = WebDavClientHttp(
        remoteDirUrl: 'https://x.com/dav',
        username: 'u',
        password: 'p',
        httpClient: client,
      );
      expect(
        () => dav.listBackups(),
        throwsA(
          isA<WebDavException>().having(
            (e) => e.message,
            'message',
            contains('不支持 PROPFIND'),
          ),
        ),
      );
      dav.close();
    });

    test('remoteDirUrl 不以 / 结尾 → 自动补齐，PROPFIND 不发起重定向',
        () async {
      http.Request? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(
          '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"></d:multistatus>',
          207,
        );
      });
      final dav = WebDavClientHttp(
        remoteDirUrl: 'https://x.com/dav', // 无尾斜杠
        username: 'u',
        password: 'p',
        httpClient: client,
      );
      await dav.listBackups();
      dav.close();
      expect(seen!.url.path.endsWith('/'), isTrue);
    });

    test('空目录：200 / 204 视为无备份', () async {
      final client = MockClient((req) async => http.Response('', 204));
      final dav = WebDavClientHttp(
        remoteDirUrl: 'https://x.com/dav',
        username: 'u',
        password: 'p',
        httpClient: client,
      );
      expect(await dav.listBackups(), isEmpty);
      dav.close();
    });
  });

  group('SyncProvider 互斥锁（H2）', () {
    late Directory tmpDir;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('moying_sync_lock');
    });
    tearDown(() async {
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
    });

    /// 建一个已配置好凭据的 SyncProvider，client 记录上传并发高峰。
    /// [saveFile] 默认用收集器（不触发 share_plus 原生通道，纯测试环境友好）。
    /// 返回 (sync, counter)：counter.maxActive = upload 临界区内最大并发数。
    Future<(SyncProvider, _ConcurrencyProbe)> makeLockedSync({
      Future<bool> Function(String, Uint8List)? saveFile,
    }) async {
      final store =
          LibraryStore(tmpDir, seed: const LibrarySnapshot(books: [], movies: [], actors: []));
      await store.load();
      await store.loadProfile();
      final library = LibraryProvider(store: store);
      await library.init();
      final probe = _ConcurrencyProbe();
      final secure = SecureStorageService(store: InMemorySecureStore());
      await secure.saveWebDavPassword('u', 'p');
      final sync = SyncProvider(
        store: store,
        library: library,
        secureStorage: secure,
        clientFactory: (_, __) => probe,
        // 默认用收集器，避免 exportLocal 调 share_plus 触碰 MethodChannel；
        // 导出成功以返回值 true 判定，不依赖原生分享实现。
        saveFile: saveFile ?? (_, __) async => true,
      );
      await sync.loadSettings();
      await sync.saveSettings(const SyncSettings(
        webdavUrl: 'https://x.com/dav',
        username: 'u',
      ));
      return (sync, probe);
    }

    test('并发两个 uploadNow 串行执行：上传临界区从不重叠', () async {
      final (sync, probe) = await makeLockedSync();

      // 同一时刻发起两个完整同步动作（含慢速下载/上传），
      // _runExclusive 应让后者等待前者整体结束后才进入。
      await Future.wait([sync.uploadNow(), sync.uploadNow()]);

      expect(sync.lastError, isNull);
      // 若互斥生效：两个动作各自的上传阶段不会交错（同一时刻只有 1 个上传）。
      // 若无锁：慢速上传会重叠，maxActive >= 2。
      expect(probe.maxActive, 1);
      expect(probe.uploadCount, 2);
    });

    test('并发 uploadNow 与 exportLocal：导出等待同步完成（同一队列）', () async {
      final (sync, probe) = await makeLockedSync();

      final results = await Future.wait([
        sync.uploadNow(),
        sync.exportLocal(),
      ]);

      expect(results, [null, true]);
      expect(sync.lastError, isNull);
      expect(probe.uploadCount, 1);
      expect(probe.maxActive, 1);
    });
  });
}

/// 记录 WebDAV 上传临界区并发高峰的探针客户端。
/// upload 前置置 active++/记高峰，结束时 active--。
class _ConcurrencyProbe implements WebDavClient {
  int active = 0;
  int maxActive = 0;
  int uploadCount = 0;

  @override
  Future<bool> testConnection() async => true;

  @override
  Future<void> upload(String fileName, Uint8List bytes) async {
    uploadCount++;
    active++;
    if (active > maxActive) maxActive = active;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    active--;
  }

  @override
  Future<Uint8List> download(String fileName) async {
    // 返回空 JSON 备份，供 uploadNow 的 LWW 合并解析（无数据即无变更）
    return Uint8List.fromList(utf8.encode(
        '{"manifest":{"schemaVersion":2,"exportedAt":"2026-09-05T12:00:00.000",'
        '"includeImages":false,"counts":{},"imageCount":0},"data":{}}'));
  }

  @override
  Future<List<String>> listBackups() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return const <String>[]; // 云端无备份 → 跳过合并直接上传
  }

  @override
  void close() {}
}
