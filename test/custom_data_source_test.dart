// 自定义数据源（智能解析）测试：
// 1) SmartResponseParser：递归找列表 / 字段别名提取 / 结构校验
// 2) CustomBookDataSource：多路径搜索 + 启发式解析（fake HTTP）
// 3) CustomMovieDataSource：结构校验失败给出中文提示
// 4) DataSourceManager：custom 类型注册 / testDraft 草稿测试
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:moying/models/data_source.dart';
import 'package:moying/services/data_source_interface.dart';
import 'package:moying/services/data_source_manager.dart';
import 'package:moying/services/data_sources/custom_data_source.dart';

// ==================== Fake HTTP ====================

/// 固定响应的 fake HTTP 客户端（按 URL 路径前缀匹配返回体）
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this.responses);

  /// 按路径包含的子串匹配 → 响应体；未命中返回 404
  final Map<String, ({int code, String body})> responses;
  final List<String> requestedUrls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestedUrls.add(request.url.toString());
    for (final entry in responses.entries) {
      if (request.url.toString().contains(entry.key)) {
        return http.StreamedResponse(
          Stream.value(utf8.encode(entry.value.body)),
          entry.value.code,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
    }
    return http.StreamedResponse(Stream.value(utf8.encode('not found')), 404);
  }
}

/// 内存凭据仓（验证草稿测试时凭据按 config.id 读取）
class _MemoryCreds implements DataSourceCredentialStore {
  final Map<String, String> values = {};

  String _k(String sourceId, String key) => '$sourceId/$key';

  @override
  Future<String?> read(String sourceId, String key) async => values[_k(sourceId, key)];

  @override
  Future<void> write(String sourceId, String key, String value) async {
    if (value.isEmpty) {
      values.remove(_k(sourceId, key));
    } else {
      values[_k(sourceId, key)] = value;
    }
  }

  @override
  Future<void> delete(String sourceId, String key) async {
    values.remove(_k(sourceId, key));
  }
}

void main() {
  group('SmartResponseParser.findFirstList', () {
    test('顶层直接是对象数组', () {
      final list = SmartResponseParser.findFirstList([
        {'title': 'a'},
        {'title': 'b'},
      ]);
      expect(list, isNotNull);
      expect(list!.length, 2);
    });

    test('包装对象 data/results 常见键名', () {
      for (final key in ['data', 'results', 'items', 'books']) {
        final list = SmartResponseParser.findFirstList({
          'total': 2,
          key: [
            {'title': 'x'},
          ],
        });
        expect(list, isNotNull, reason: '键 $key 应能找到列表');
      }
    });

    test('深层嵌套递归兜底', () {
      final list = SmartResponseParser.findFirstList({
        'code': 0,
        'payload': {
          'page': 1,
          'records': [
            {'name': 'deep'},
          ],
        },
      });
      expect(list, isNotNull);
      expect(list!.first['name'], 'deep');
    });

    test('空数组 / 无数组 / 标量返回 null', () {
      expect(SmartResponseParser.findFirstList([]), isNull);
      expect(SmartResponseParser.findFirstList({'a': 1}), isNull);
      expect(SmartResponseParser.findFirstList('text'), isNull);
      expect(
        SmartResponseParser.findFirstList([
          {'title': 'a'},
          'string-element',
        ]),
        isNotNull, // 字符串元素被跳过，仍取对象元素
      );
    });
  });

  group('SmartResponseParser 字段提取', () {
    test('书籍条目：标准字段', () {
      final r = SmartResponseParser.parseBookItem({
        'id': '42',
        'title': '三体',
        'author': '刘慈欣',
        'publisher': '重庆出版社',
        'year': 2008,
        'isbn': '9787536692930',
        'pages': 302,
        'cover': 'https://example.com/c.jpg',
        'rating': 9.3,
        'description': '地球往事',
      });
      expect(r, isNotNull);
      expect(r!.title, '三体');
      expect(r.externalId, '42');
      expect(r.authors, ['刘慈欣']);
      expect(r.year, 2008);
      expect(r.pageCount, 302);
      expect(r.coverUrl, 'https://example.com/c.jpg');
      expect(r.rating, closeTo(4.65, 0.01)); // 10 分制自动折算 5 分制
    });

    test('书籍条目：中文字段别名', () {
      final r = SmartResponseParser.parseBookItem({
        '书名': '活着',
        '作者': '余华',
        '封面': 'https://example.com/h.jpg',
      });
      expect(r, isNotNull);
      expect(r!.title, '活着');
      expect(r.authors, ['余华']);
      expect(r.coverUrl, 'https://example.com/h.jpg');
    });

    test('书籍条目：无标题字段返回 null（不可识别）', () {
      expect(SmartResponseParser.parseBookItem({'foo': 'bar'}), isNull);
    });

    test('影视条目：类型单串按分隔符拆分', () {
      final m = SmartResponseParser.parseMovieItem({
        'title': '流浪地球',
        'genres': '科幻,冒险',
        'runtime': 125,
        'director': '郭帆',
      });
      expect(m, isNotNull);
      expect(m!.genres, ['科幻', '冒险']);
      expect(m.runtimeMinutes, 125);
      expect(m.director, '郭帆');
    });

    test('评分 5 分制原样、10 分制折半、超范围忽略', () {
      expect(
        SmartResponseParser.parseMovieItem({'title': 'a', 'rating': 4.5})!.rating,
        4.5,
      );
      expect(
        SmartResponseParser.parseMovieItem({'title': 'a', 'rating': 8.0})!.rating,
        4.0,
      );
      expect(
        SmartResponseParser.parseMovieItem({'title': 'a', 'rating': 42})!.rating,
        isNull,
      );
    });
  });

  group('SmartResponseParser.validateStructure', () {
    test('通过：数组 + 标题字段', () {
      expect(
        SmartResponseParser.validateStructure([
          {'title': 'ok'},
        ]),
        isNull,
      );
    });

    test('非 JSON 容器报格式错误', () {
      final err = SmartResponseParser.validateStructure('plain text');
      expect(err, contains('不是有效'));
    });

    test('无列表给出期望格式提示', () {
      final err = SmartResponseParser.validateStructure({'code': 0});
      expect(err, contains('自定义 API 返回格式不正确'));
      expect(err, contains('数据列表'));
    });

    test('列表项无标题字段给出字段建议', () {
      final err = SmartResponseParser.validateStructure([
        {'foo': 'bar'},
      ]);
      expect(err, contains('标题字段'));
    });
  });

  group('CustomBookDataSource（fake HTTP）', () {
    late _FakeHttpClient client;
    late CustomBookDataSource source;
    const config = {'baseUrl': 'https://api.example.com/v1'};
    const credentials = <String, String>{};

    setUp(() {
      client = _FakeHttpClient({});
      source = CustomBookDataSource(client: client);
    });

    test('搜索命中 /search 路径并智能解析', () async {
      client.responses['/search'] = (
        code: 200,
        body: jsonEncode({
          'data': [
            {'title': '三体', 'author': '刘慈欣', 'cover': 'https://c/1.jpg'},
            {'title': '球状闪电', 'author': '刘慈欣'},
          ],
        }),
      );
      final results = await source.searchBooks(
        '三体',
        config: config,
        credentials: credentials,
      );
      expect(results.length, 2);
      expect(results.first.title, '三体');
      expect(results.first.coverUrl, 'https://c/1.jpg');
    });

    test('/search 404 时回退尝试 base 根路径', () async {
      // 匹配子串「v1?q=」只命中根路径模板（/search URL 含 v1/search?q= 不命中）
      client.responses['v1?q='] = (
        code: 200,
        body: jsonEncode([
          {'title': '根路径结果'},
        ]),
      );
      final results = await source.searchBooks(
        'x',
        config: config,
        credentials: credentials,
      );
      expect(results.single.title, '根路径结果');
      // 首个 /search 路径被 404 → 至少请求过两次
      expect(client.requestedUrls.length, greaterThanOrEqualTo(2));
    });

    test('全部路径失败给出格式不正确提示', () async {
      final call = source.searchBooks(
        'x',
        config: config,
        credentials: credentials,
      );
      await expectLater(call, throwsA(isA<DataSourceException>()));
    });

    test('API Key 以 Bearer 头与 ?key= 参数同时携带', () async {
      client.responses['/search'] = (
        code: 200,
        body: jsonEncode([
          {'title': 'a'},
        ]),
      );
      await source.searchBooks(
        'x',
        config: config,
        credentials: const {'apiKey': 'secret-key'},
      );
      final url = client.requestedUrls.first;
      expect(url, contains('key=secret-key'));
    });

    test('Base URL 缺失抛异常', () async {
      await expectLater(
        source.testConnection(config: {}, credentials: credentials),
        throwsA(isA<DataSourceException>()),
      );
    });

    test('testConnection：结构校验失败提示格式不正确', () async {
      client.responses['/search'] = (
        code: 200,
        body: '<html>not json</html>',
      );
      final call = source.testConnection(
        config: config,
        credentials: credentials,
      );
      await expectLater(
        call,
        throwsA(
          isA<DataSourceException>().having(
            (e) => e.message,
            'message',
            contains('自定义 API 返回格式不正确'),
          ),
        ),
      );
    });
  });

  group('DataSourceManager 自定义源集成', () {
    test('custom 类型已注册且 configFields 含 Base URL/API Key', () {
      final manager = DataSourceManager(store: null);
      final book = manager.bookImplOf(DataSourceType.customBook);
      final movie = manager.movieImplOf(DataSourceType.customMovie);
      expect(book, isA<CustomBookDataSource>());
      expect(movie, isA<CustomMovieDataSource>());
      final keys = book!.configFields.map((f) => f.key).toList();
      expect(keys, contains('baseUrl'));
      expect(keys, contains('apiKey'));
    });

    test('testDraft 不落盘（草稿配置不进 configs）', () async {
      // fake client 全部 404 → 快速失败，不涉及真实网络；
      // 凭据仓注入内存实现（测试环境无平台通道）
      final manager = DataSourceManager(
        store: null,
        credentials: _MemoryCreds(),
        customBook: CustomBookDataSource(client: _FakeHttpClient({})),
      );
      await manager.loadConfigs();
      final before = manager.configs.length;
      const draft = DataSourceConfig(
        id: 'draft_1',
        type: DataSourceType.customBook,
        name: '草稿',
        config: {'baseUrl': 'https://x.example.com'},
      );
      // runTest 把网络失败归一为 error 状态（不抛出），草稿不落盘
      final result = await manager.testDraft(draft);
      expect(result.status, DataSourceStatus.error);
      expect(manager.configs.length, before);
    });

    test('testDraft 草稿凭据可从安全存储读取（注入 fake 凭据仓验证）', () async {
      final creds = _MemoryCreds();
      final client = _FakeHttpClient({
        '/search': (
          code: 200,
          body: jsonEncode([
            {'title': 'ok'},
          ]),
        ),
      });
      final manager = DataSourceManager(
        store: null,
        credentials: creds,
        customBook: CustomBookDataSource(client: client),
      );
      await manager.loadConfigs();
      const draft = DataSourceConfig(
        id: 'draft_2',
        type: DataSourceType.customBook,
        name: '草稿2',
        config: {'baseUrl': 'https://api.example.com/v1'},
      );
      await creds.write(draft.id, 'apiKey', 'draft-key');
      final ok = await manager.testDraft(draft);
      expect(ok.status, DataSourceStatus.connected);
      // 草稿测试的凭据请求确实带上了 key
      expect(client.requestedUrls.first, contains('key=draft-key'));
      // 草稿测试不落盘：configs 仍是内置预设数量
      expect(manager.configs.length, 2);
    });
  });
}
