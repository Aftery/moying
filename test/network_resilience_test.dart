// P1 抗慢 —— 网络层与地址解析
//
// 覆盖三块：
// 1. 封面 Referer：豆瓣图床无 Referer 一律 418，其他源一个头都不该多带；
// 2. TTL + LRU 缓存：过期逐出、超容淘汰、探测不提权；
// 3. 分层超时重试：只对可重放的失败重试一次，HTTP 错误与非 Exception 不重试；
// 4. 可配置镜像地址：配置生效、尾斜杠归一、未配置回落官方地址。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moying/services/cover_headers.dart';
import 'package:moying/services/data_sources/google_books_data_source.dart';
import 'package:moying/services/data_sources/open_library_data_source.dart';
import 'package:moying/services/http_retry.dart';
import 'package:moying/services/ttl_cache.dart';

const Map<String, String> _utf8Json = {
  'content-type': 'application/json; charset=utf-8',
};

void main() {
  group('封面 Referer（豆瓣图床反盗链）', () {
    test('豆瓣图床各主机都补 Referer', () {
      for (final host in [
        'img1.doubanio.com',
        'img3.doubanio.com',
        'img9.doubanio.com',
        'doubanio.com',
        'book.douban.com',
      ]) {
        final headers = coverHeadersFor('https://$host/view/subject/l/x.jpg');
        expect(headers, isNotNull, reason: '$host 需要 Referer，否则吃 418');
        expect(headers!['Referer'], kDoubanReferer);
      }
    });

    test('其他源不额外加头（免得平白多一项请求头影响缓存命中）', () {
      expect(coverHeadersFor('https://covers.openlibrary.org/b/id/1-M.jpg'),
          isNull);
      expect(coverHeadersFor('https://books.google.com/books/content?id=1'),
          isNull);
      expect(coverHeadersFor('https://image.tmdb.org/t/p/w500/x.jpg'), isNull);
    });

    test('伪造域名不被误命中（后缀匹配必须带点）', () {
      expect(coverHeadersFor('https://evil-doubanio.com/x.jpg'), isNull);
      expect(coverHeadersFor('https://doubanio.com.evil.com/x.jpg'), isNull);
    });

    test('null / 空 / 非法 URL 返回 null，不抛异常', () {
      expect(coverHeadersFor(null), isNull);
      expect(coverHeadersFor(''), isNull);
      expect(coverHeadersFor('not a url'), isNull);
    });
  });

  group('TtlCache（TTL + LRU）', () {
    test('未过期命中，到期即逐出', () {
      var now = DateTime(2026, 9, 11, 10);
      final cache = TtlCache<String, int>(
        ttl: const Duration(minutes: 10),
        clock: () => now,
      );

      cache.put('三体', 1);
      expect(cache.get('三体'), 1);

      now = now.add(const Duration(minutes: 9, seconds: 59));
      expect(cache.get('三体'), 1, reason: '尚未到期');

      now = now.add(const Duration(seconds: 1));
      expect(cache.get('三体'), isNull, reason: '正好到期应视为过期');
      expect(cache.length, 0, reason: '过期条目由 get 顺手带走');
    });

    test('容量满时淘汰最久未用的一项（get 会提权）', () {
      var now = DateTime(2026, 9, 11);
      final cache = TtlCache<String, int>(
        ttl: const Duration(minutes: 10),
        maxEntries: 2,
        clock: () => now,
      );

      cache.put('a', 1);
      cache.put('b', 2);
      cache.get('a'); // a 成为最近使用
      cache.put('c', 3); // 淘汰 b

      expect(cache.get('b'), isNull);
      expect(cache.get('a'), 1);
      expect(cache.get('c'), 3);
    });

    test('containsKey 不提权（探查不该改变淘汰顺序）', () {
      var now = DateTime(2026, 9, 11);
      final cache = TtlCache<String, int>(
        ttl: const Duration(minutes: 10),
        maxEntries: 2,
        clock: () => now,
      );

      cache.put('a', 1);
      cache.put('b', 2);
      expect(cache.containsKey('a'), isTrue); // 若提权，a 就会被留下
      cache.put('c', 3);

      expect(cache.containsKey('a'), isFalse, reason: 'a 仍是最久未用，应被淘汰');
    });

    test('覆盖写不涨容量；clear 清空', () {
      final cache = TtlCache<String, int>(ttl: const Duration(minutes: 1));
      cache.put('a', 1);
      cache.put('a', 2);
      expect(cache.length, 1);
      expect(cache.get('a'), 2);
      cache.clear();
      expect(cache.length, 0);
      expect(cache.get('a'), isNull);
    });
  });

  group('getWithRetry（分层超时 + 一次重试）', () {
    test('首次超时 → 重试一次成功', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts == 1) throw TimeoutException('模拟冷连接超时');
        return http.Response('{"docs":[]}', 200, headers: _utf8Json);
      });

      final resp = await getWithRetry(
        client,
        Uri.parse('https://openlibrary.org/search.json'),
        backoff: Duration.zero,
      );

      expect(attempts, 2, reason: '正是「首跳失败 + 重试命中复用连接」这条路径');
      expect(resp.statusCode, 200);
    });

    test('连续两次超时 → 原样抛出 TimeoutException（由调用方翻译文案）', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        throw TimeoutException('一直超时');
      });

      await expectLater(
        getWithRetry(client, Uri.parse('https://x.test/a'),
            backoff: Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
      expect(attempts, 2, reason: '最多两次，不做无限重试');
    });

    test('HTTP 错误状态不重试（服务端的明确回答，重试只会加重对方负担）', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        return http.Response('nope', 429);
      });

      final resp = await getWithRetry(client, Uri.parse('https://x.test/a'),
          backoff: Duration.zero);

      expect(attempts, 1);
      expect(resp.statusCode, 429);
    });

    test('网络连接异常重试一次', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts == 1) {
          throw const SocketException('Connection refused');
        }
        return http.Response('ok', 200);
      });

      final resp = await getWithRetry(client, Uri.parse('https://x.test/a'),
          backoff: Duration.zero);

      expect(attempts, 2);
      expect(resp.body, 'ok');
    });

    test('非「可重放失败」不重试（Error 直接冒泡，不浪费一次往返）', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        throw StateError('解析前的逻辑错误');
      });

      await expectLater(
        getWithRetry(client, Uri.parse('https://x.test/a'),
            backoff: Duration.zero),
        throwsA(isA<StateError>()),
      );
      expect(attempts, 1);
    });
  });

  group('OpenLibrary 可配置镜像地址', () {
    test('未配置 → 官方地址（开箱即用不能被破坏）', () async {
      Uri? captured;
      final ds = OpenLibraryDataSource(client: MockClient((r) async {
        captured = r.url;
        return http.Response('{"docs":[]}', 200, headers: _utf8Json);
      }));

      await ds.searchBooks('百年孤独', config: const {}, credentials: const {});

      expect(captured!.host, 'openlibrary.org');
      expect(captured!.path, '/search.json');
    });

    test('baseUrl 生效，且尾斜杠被归一（避免拼出 //search.json）', () async {
      Uri? captured;
      final ds = OpenLibraryDataSource(client: MockClient((r) async {
        captured = r.url;
        return http.Response('{"docs":[]}', 200, headers: _utf8Json);
      }));

      await ds.searchBooks(
        '百年孤独',
        config: const {'baseUrl': 'https://mirror.example.com/ol/'},
        credentials: const {},
      );

      expect(captured!.host, 'mirror.example.com');
      expect(captured!.path, '/ol/search.json');
    });

    test('coverBaseUrl 生效：封面也走镜像', () async {
      final ds = OpenLibraryDataSource(client: MockClient((r) async {
        return http.Response(
          '{"docs":[{"key":"/works/OL1W","title":"三体","cover_i":42}]}',
          200,
          headers: _utf8Json,
        );
      }));

      final results = await ds.searchBooks(
        '三体',
        config: const {'coverBaseUrl': 'https://img.example.com/b/id'},
        credentials: const {},
      );

      expect(results.single.coverUrl, 'https://img.example.com/b/id/42-M.jpg');
    });

    test('详情链路同样走镜像（work 与 editions 两跳都换host）', () async {
      final hosts = <String>[];
      final ds = OpenLibraryDataSource(client: MockClient((r) async {
        hosts.add(r.url.host);
        if (r.url.path.endsWith('/editions.json')) {
          return http.Response('{"entries":[]}', 200, headers: _utf8Json);
        }
        return http.Response(
          '{"title":"三体","subjects":["Science fiction"]}',
          200,
          headers: _utf8Json,
        );
      }));

      await ds.getBookDetail(
        '/works/OL1W',
        config: const {'baseUrl': 'https://mirror.example.com'},
        credentials: const {},
      );

      expect(hosts, isNotEmpty);
      expect(hosts.every((h) => h == 'mirror.example.com'), isTrue);
    });

    test('镜像字段全部选填（不破坏「免配置开箱即用」的定位）', () {
      final fields = OpenLibraryDataSource().configFields;
      expect(fields.map((f) => f.key), containsAll(['baseUrl', 'coverBaseUrl']));
      expect(fields.any((f) => f.required), isFalse);
    });
  });

  group('Google Books 可配置镜像地址', () {
    test('baseUrl 生效；未配置走官方地址', () async {
      final captured = <Uri>[];
      final ds = GoogleBooksDataSource(client: MockClient((r) async {
        captured.add(r.url);
        return http.Response('{"items":[]}', 200, headers: _utf8Json);
      }));

      await ds.searchBooks('三体', config: const {}, credentials: const {});
      await ds.searchBooks(
        '三体',
        config: const {'baseUrl': 'https://gb-mirror.example.com/books/v1'},
        credentials: const {},
      );

      expect(captured[0].host, 'www.googleapis.com');
      expect(captured[0].path, '/books/v1/volumes');
      expect(captured[1].host, 'gb-mirror.example.com');
      expect(captured[1].path, '/books/v1/volumes');
    });

    test('非 200 之外的状态码仍走原有分支（403 提示填国家代码）', () async {
      final ds = GoogleBooksDataSource(client: MockClient((r) async {
        return http.Response('{}', 403);
      }));

      await expectLater(
        ds.searchBooks('三体', config: const {}, credentials: const {}),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('国家代码'),
        )),
      );
    });
  });

  group('UTF-8 解码不回退 latin1（中文书名不能变乱码）', () {
    test('Google Books 响应头缺 charset 时仍正确解码', () async {
      final ds = GoogleBooksDataSource(client: MockClient((r) async {
        return http.Response.bytes(
          utf8.encode('{"items":[{"id":"1","volumeInfo":{"title":"三体"}}]}'),
          200,
          // 刻意不带 charset
          headers: const {'content-type': 'application/json'},
        );
      }));

      final results =
          await ds.searchBooks('三体', config: const {}, credentials: const {});
      expect(results.single.title, '三体');
    });
  });
}
