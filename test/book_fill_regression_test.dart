// 书籍数据源回填回归测试
//
// 背景（2026-09-07 截图 bug）：
// 1. open_library getBookDetail 把 author.key（如 "OL12111758A"）当作者名回填
// 2. fetchBookDetail 成功后用详情「完全替换」搜索结果，导致详情接口不含
//    的字段（isbn/页数/出版社）被 null 覆盖
//
// 本测试覆盖三个修复点：
// - OpenLibrary author 解析改为 name
// - BookSearchResult.mergeWith 合并语义
// - onPick 调用方走 mergeWith 而非 ??

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moying/models/book.dart';
import 'package:moying/models/data_source.dart';
import 'package:moying/services/book_category_mapper.dart';
import 'package:moying/services/data_sources/custom_data_source.dart';
import 'package:moying/services/data_sources/open_library_data_source.dart';

/// 中文 mock 响应必须声明 UTF-8：`http.Response` 默认按 latin1 编码，
/// 直接返回含中文的 JSON 会抛 "Contains invalid characters"。
const Map<String, String> _utf8Json = {
  'content-type': 'application/json; charset=utf-8',
};

void main() {
  group('BookSearchResult.mergeWith', () {
    const base = BookSearchResult(
      externalId: '/works/OL262758W',
      title: 'The Old Man and the Sea',
      authors: ['Ernest Hemingway'],
      publisher: 'Charles Scribner\'s Sons',
      year: 1952,
      isbn: '9780684801223',
      pageCount: 127,
      coverUrl: 'https://covers.example/1.jpg',
      rating: 4.0,
      description: 'short desc',
      categories: ['Fiction'],
    );

    test('详情失败（null）时原样保留 base', () {
      // 调用方代码：`detailResult == null ? searchResult : searchResult.mergeWith(detailResult)`
      // 这条用例验证分支本身（mergeWith 内部不感知 null——由调用方决定）
      final detail = base.mergeWith(const BookSearchResult(
        externalId: '/works/OL262758W',
        title: '',
        authors: [],
        categories: [],
      ));
      // 全部为空的 detail 不会覆盖任何字段
      expect(detail.title, base.title);
      expect(detail.authors, base.authors);
      expect(detail.publisher, base.publisher);
      expect(detail.year, base.year);
      expect(detail.isbn, base.isbn);
      expect(detail.pageCount, base.pageCount);
      expect(detail.coverUrl, base.coverUrl);
      expect(detail.rating, base.rating);
      expect(detail.description, base.description);
      expect(detail.categories, base.categories);
    });

    test('详情非空字段覆盖 base（categories / description）', () {
      const detail = BookSearchResult(
        externalId: '/works/OL262758W',
        title: 'The Old Man and the Sea',
        authors: [],
        // 其他字段缺失
        description: '很长很长很长的真实内容简介……',
        categories: ['Fiction', 'Classic Literature', 'Adventure'],
      );
      final merged = base.mergeWith(detail);
      // detail 非空 → 覆盖
      expect(merged.description, '很长很长很长的真实内容简介……');
      expect(merged.categories, ['Fiction', 'Classic Literature', 'Adventure']);
      // detail 空 → 保留 base
      expect(merged.authors, base.authors);
      expect(merged.publisher, base.publisher);
      expect(merged.isbn, base.isbn);
      expect(merged.pageCount, base.pageCount);
      expect(merged.coverUrl, base.coverUrl);
      expect(merged.rating, base.rating);
    });

    test('详情缺失字段（isbn/pageCount/publisher）保留 base（修复 bug2）', () {
      // 关键场景：OpenLibrary getBookDetail 不返回 isbn/pageCount/publisher
      const detail = BookSearchResult(
        externalId: '/works/OL262758W',
        title: 'The Old Man and the Sea',
        authors: ['海明威'],
        // publisher / isbn / pageCount / coverUrl 全部为 null
        description: '真实简介',
        categories: ['Fiction'],
      );
      final merged = base.mergeWith(detail);
      // 详情有 → 用详情
      expect(merged.authors, ['海明威']);
      expect(merged.description, '真实简介');
      expect(merged.categories, ['Fiction']);
      // 详情缺失 → 保留搜索结果（这是 bug 修复的核心断言）
      expect(merged.publisher, 'Charles Scribner\'s Sons',
          reason: 'publisher 详情缺失时必须保留搜索结果');
      expect(merged.isbn, '9780684801223',
          reason: 'isbn 详情缺失时必须保留搜索结果（这就是用户看到的「ISBN 没写入」bug 的根因）');
      expect(merged.pageCount, 127, reason: 'pageCount 详情缺失时必须保留搜索结果');
      expect(merged.coverUrl, 'https://covers.example/1.jpg',
          reason: 'coverUrl 详情缺失时必须保留搜索结果');
    });

    test('详情空字符串按缺失处理', () {
      const detail = BookSearchResult(
        externalId: '/works/OL262758W',
        title: '',
        authors: [],
        publisher: '',
        isbn: '',
        description: '',
        categories: [],
      );
      final merged = base.mergeWith(detail);
      // 空字符串不覆盖
      expect(merged.title, base.title);
      expect(merged.publisher, base.publisher);
      expect(merged.isbn, base.isbn);
      expect(merged.description, base.description);
    });

    test('title 缺失/相同时保留 base（避免 setText 抖动）', () {
      const sameTitle = BookSearchResult(
        externalId: '/works/OL262758W',
        title: 'The Old Man and the Sea', // 与 base 一致
      );
      final mergedSame = base.mergeWith(sameTitle);
      expect(mergedSame.title, base.title);

      const emptyTitle = BookSearchResult(
        externalId: '/works/OL262758W',
        title: '', // 空 → 视为缺失
      );
      expect(base.mergeWith(emptyTitle).title, base.title);

      const differentTitle = BookSearchResult(
        externalId: '/works/OL262758W',
        title: 'Different Title',
      );
      expect(base.mergeWith(differentTitle).title, 'Different Title');
    });
  });

  group('OpenLibraryDataSource.getBookDetail', () {
    test('authors 取 name 而非 key（修复 bug1：不再回填 OL12111758A）', () async {
      // 模拟 OpenLibrary work 详情接口的 authors 嵌套结构
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/works/OL262758W.json');
        return http.Response('''
        {
          "title": "The Old Man and the Sea",
          "authors": [
            {"author": {"key": "/authors/OL12111758A", "name": "Ernest Hemingway"}}
          ],
          "subjects": ["Fiction", "Classic Literature"],
          "first_publish_date": "1952",
          "covers": [12345]
        }
        ''', 200);
      });

      final ds = OpenLibraryDataSource(client: mockClient);
      final result = await ds.getBookDetail(
        '/works/OL262758W',
        config: const {},
        credentials: const {},
      );

      // 关键断言：取到的是名字，不是 OL id
      expect(result.authors, ['Ernest Hemingway'],
          reason: '必须取 author.name，而不是 author.key');
      expect(result.authors, isNot(contains('OL12111758A')),
          reason: '不应回填 OpenLibrary author key');
      expect(result.categories, ['Fiction', 'Classic Literature']);
      expect(result.title, 'The Old Man and the Sea');
      expect(result.year, 1952);
      expect(
          result.coverUrl, 'https://covers.openlibrary.org/b/id/12345-M.jpg');
    });

    test('description 对象格式能取 value，不因类型转换崩溃', () async {
      final mockClient = MockClient((request) async {
        return http.Response(r'''
        {
          "title": "Test Book",
          "description": {"type": "/type/text", "value": "object description"}
        }
        ''', 200);
      });

      final ds = OpenLibraryDataSource(client: mockClient);
      final result = await ds.getBookDetail(
        '/works/OLTestW',
        config: const {},
        credentials: const {},
      );

      expect(result.description, 'object description');
    });

    test('多作者都能正确取 name', () async {
      final mockClient = MockClient((request) async {
        return http.Response('''
        {
          "title": "Test Book",
          "authors": [
            {"author": {"key": "/authors/OL1A", "name": "Alice"}},
            {"author": {"key": "/authors/OL2B", "name": "Bob"}},
            {"author": {"key": "/authors/OL3C", "name": "Carol"}}
          ]
        }
        ''', 200);
      });

      final ds = OpenLibraryDataSource(client: mockClient);
      final result = await ds.getBookDetail(
        '/works/OLTestW',
        config: const {},
        credentials: const {},
      );

      expect(result.authors, ['Alice', 'Bob', 'Carol']);
    });

    test('非 OL…W 格式 ID 抛 DataSourceException', () async {
      final ds = OpenLibraryDataSource();
      expect(
        () => ds.getBookDetail(
          '/books/OL456M',
          config: const {},
          credentials: const {},
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('合并链路回归', () {
    test('搜索结果 + 详情 → 全部字段正确回填（截图复现场景）', () async {
      final mockClient = MockClient((request) async {
        return http.Response('''
        {
          "title": "The Old Man and the Sea",
          "authors": [{"author": {"key": "/authors/OL12111758A", "name": "Ernest Hemingway"}}],
          "subjects": ["Fiction"],
          "first_publish_date": "1952"
        }
        ''', 200);
      });

      final ds = OpenLibraryDataSource(client: mockClient);
      // 模拟搜索结果（来自 _parseDoc）
      const searchResult = BookSearchResult(
        externalId: '/works/OL262758W',
        title: 'The Old Man and the Sea',
        authors: ['Ernest Hemingway'],
        publisher: 'Charles Scribner\'s Sons',
        year: 1952,
        isbn: '9780684801223',
        pageCount: 127,
        coverUrl: 'https://covers.example/1.jpg',
      );

      // 模拟 fetchBookDetail 行为
      final detail = await ds.getBookDetail(
        searchResult.externalId,
        config: const {},
        credentials: const {},
      );

      // 模拟 onPick 中的 merge 逻辑
      final merged = searchResult.mergeWith(detail);

      // 用户截图看到的 5 个字段全部正确：
      expect(merged.authors.first, 'Ernest Hemingway', reason: '作者名（不是 OL id）');
      expect(merged.publisher, 'Charles Scribner\'s Sons', reason: '出版社');
      expect(merged.year, 1952, reason: '出版年份');
      expect(merged.isbn, '9780684801223', reason: 'ISBN');
      expect(merged.pageCount, 127, reason: '页数');
      expect(merged.categories, ['Fiction'], reason: '分类（详情补全）');
    });
  });

  group('搜索结果补全（subject 映射 / 作者清洗）', () {
    test('搜索即带分类：subject → categories，作者去「著」与店铺名', () async {
      final mockClient = MockClient((request) async {
        // B：搜索显式声明 fields，保证 subject 不被省略
        expect(request.url.queryParameters['fields'], isNotNull);
        return http.Response('''
        {
          "docs": [
            {
              "key": "/works/OL262758W",
              "title": "百年孤独(精)",
              "author_name": ["新华书店北美网 加西亚·马尔克斯 著"],
              "first_publish_year": 2017,
              "cover_i": 12345,
              "subject": ["Fiction", "Classic Literature", "Magic realism"]
            }
          ]
        }
        ''', 200, headers: _utf8Json);
      });

      final ds = OpenLibraryDataSource(client: mockClient);
      final results = await ds.searchBooks(
        '百年孤独',
        config: const {},
        credentials: const {},
      );

      final r = results.single;
      expect(r.categories, ['Fiction', 'Classic Literature', 'Magic realism'],
          reason: '分类不该等到详情才有——搜索接口已返回 subject');
      expect(r.authors, ['加西亚·马尔克斯'], reason: '店铺名与「著」后缀需清洗');
      expect(r.year, 2017);
    });
  });

  group('详情补全（work + edition 两级串联）', () {
    test('版本接口补全出版社 / ISBN / 页数，不覆盖作品级字段', () async {
      final requested = <String>[];
      final mockClient = MockClient((request) async {
        requested.add(request.url.path);
        if (request.url.path.endsWith('/editions.json')) {
          return http.Response('''
          {"entries": [
            {"title": "百年孤独", "publishers": [], "isbn_13": [], "number_of_pages": null},
            {"title": "百年孤独(精)",
             "publishers": ["南海出版公司"],
             "isbn_13": ["9787544253994"],
             "number_of_pages": 360}
          ]}
          ''', 200, headers: _utf8Json);
        }
        return http.Response('''
        {
          "title": "百年孤独",
          "authors": [{"author": {"key": "/authors/OL1A", "name": "加西亚·马尔克斯 著"}}],
          "subjects": ["Fiction", "Magic realism"],
          "first_publish_date": "1967",
          "description": "布恩迪亚家族的故事",
          "covers": [12345]
        }
        ''', 200, headers: _utf8Json);
      });

      final ds = OpenLibraryDataSource(client: mockClient);
      final detail = await ds.getBookDetail(
        '/works/OL262758W',
        config: const {},
        credentials: const {},
      );

      expect(requested,
          ['/works/OL262758W.json', '/works/OL262758W/editions.json']);
      // 版本级（作品详情没有的字段）
      expect(detail.publisher, '南海出版公司');
      expect(detail.isbn, '9787544253994');
      expect(detail.pageCount, 360);
      // 作品级字段不被版本覆盖
      expect(detail.title, '百年孤独', reason: '版本标题带副标题，不能覆盖作品标题');
      expect(detail.year, 1967);
      expect(detail.description, '布恩迪亚家族的故事');
      expect(detail.categories, ['Fiction', 'Magic realism']);
      expect(detail.authors, ['加西亚·马尔克斯']);
    });

    test('版本接口失败时作品级字段仍可用（静默降级）', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/editions.json')) {
          return http.Response('Not Found', 404);
        }
        return http.Response(
          '{"title":"T","subjects":["Fiction"],"description":"d"}',
          200,
        );
      });

      final ds = OpenLibraryDataSource(client: mockClient);
      final detail = await ds.getBookDetail(
        '/works/OL1W',
        config: const {},
        credentials: const {},
      );

      expect(detail.description, 'd');
      expect(detail.categories, ['Fiction']);
      expect(detail.publisher, isNull);
      expect(detail.pageCount, isNull);
    });
  });

  group('BookCategoryMapper 中文分类映射', () {
    test('具体主题优先于兜底「文学」', () {
      expect(BookCategoryMapper.map(['Science fiction']), '科幻');
      expect(BookCategoryMapper.map(['Fiction', 'Science fiction']), '科幻',
          reason: '同时有 Fiction 与 Science fiction 时必须命中更具体的');
      expect(BookCategoryMapper.map(['Biography & autobiography']), '传记');
      expect(BookCategoryMapper.map(['Dystopias']), '反乌托邦');
      expect(BookCategoryMapper.map(['Magic realism']), '魔幻现实主义');
      expect(BookCategoryMapper.map(['Fantasy fiction']), '奇幻');
      expect(BookCategoryMapper.map(['Historical fiction']), '历史');
      expect(BookCategoryMapper.map(['Classic Literature']), '经典');
      expect(BookCategoryMapper.map(['Detective and mystery stories']), '悬疑');
    });

    test('泛化主题与高频无对应项主题兜底为「文学」', () {
      expect(BookCategoryMapper.map(['Fiction']), '文学');
      expect(BookCategoryMapper.map(['Adventure fiction']), '文学');
      expect(BookCategoryMapper.map(['Young adult fiction']), '文学');
      expect(BookCategoryMapper.map(['Love stories']), '文学');
    });

    test('未命中保留原文，空列表返回 null', () {
      expect(BookCategoryMapper.map(['Astrophysics']), 'Astrophysics');
      expect(BookCategoryMapper.map([]), isNull);
    });

    test('映射结果均属于 kBookCategories（分类筛选可用）', () {
      const samples = [
        'Science fiction',
        'Fiction',
        'Biography',
        'Mystery',
        'Romance',
        'History',
        'Classic',
        'Fantasy',
        'Dystopia',
      ];
      for (final s in samples) {
        expect(kBookCategories, contains(BookCategoryMapper.map([s])),
            reason: '$s 映射结果必须是本地分类体系的成员');
      }
    });
  });

  group('OpenLibrary 短查询兜底（新版后端 q ≥3 字符）', () {
    test('两字中文书名改走 title= 参数（不再被 400 拒绝）', () async {
      final requests = <Uri>[];
      final mockClient = MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          '{"docs":[{"key":"/works/OL1W","title":"三体"}]}',
          200,
          headers: _utf8Json,
        );
      });

      final ds = OpenLibraryDataSource(client: mockClient);
      final results =
          await ds.searchBooks('三体', config: const {}, credentials: const {});

      final params = requests.single.queryParameters;
      expect(params.containsKey('q'), isFalse,
          reason: '短查询必须改用字段查询，否则服务端直接 400');
      expect(params['title'], '三体');
      expect(params['fields'], isNotNull, reason: 'fields 显式声明不能丢');
      expect(results.single.title, '三体');
    });

    test('≥3 字符查询仍走 q=（不改变原有语义）', () async {
      Uri? captured;
      final mockClient = MockClient((request) async {
        captured = request.url;
        return http.Response('{"docs":[]}', 200, headers: _utf8Json);
      });

      final ds = OpenLibraryDataSource(client: mockClient);
      await ds.searchBooks('百年孤独', config: const {}, credentials: const {});

      final params = captured!.queryParameters;
      expect(params['q'], '百年孤独');
      expect(params.containsKey('title'), isFalse);
    });

    test('两字作者名：书名无命中时回退按 author 查（莫言 → 生死疲劳）', () async {
      final requests = <Uri>[];
      final mockClient = MockClient((request) async {
        requests.add(request.url);
        // 第一跳（title=莫言）无命中，第二跳（author=莫言）命中
        if (request.url.queryParameters.containsKey('author')) {
          return http.Response(
            '{"docs":[{"key":"/works/OL5820617W","title":"生死疲劳",'
            '"author_name":["莫言"],"first_publish_year":2006}]}',
            200,
            headers: _utf8Json,
          );
        }
        return http.Response('{"docs":[]}', 200, headers: _utf8Json);
      });

      final ds = OpenLibraryDataSource(client: mockClient);
      final results =
          await ds.searchBooks('莫言', config: const {}, credentials: const {});

      expect(requests, hasLength(2), reason: '书名未命中才发起作者查询');
      expect(requests.first.queryParameters['title'], '莫言');
      expect(requests.last.queryParameters['author'], '莫言');
      expect(results.single.title, '生死疲劳');
      expect(results.single.authors, ['莫言']);
    });

    test('短查询书名命中时不再补作者请求（省一次往返）', () async {
      var count = 0;
      final mockClient = MockClient((request) async {
        count++;
        return http.Response(
          '{"docs":[{"key":"/works/OL1W","title":"三体","author_name":["刘慈欣"]}]}',
          200,
          headers: _utf8Json,
        );
      });

      final ds = OpenLibraryDataSource(client: mockClient);
      final results =
          await ds.searchBooks('三体', config: const {}, credentials: const {});

      expect(count, 1, reason: '命中就不该再打第二个请求（国内弱网下很关键）');
      expect(results.single.title, '三体');
    });

    test('空白查询直接返回空，不发网络请求', () async {
      var called = false;
      final mockClient = MockClient((request) async {
        called = true;
        return http.Response('{"docs":[]}', 200, headers: _utf8Json);
      });

      final ds = OpenLibraryDataSource(client: mockClient);
      final results =
          await ds.searchBooks('   ', config: const {}, credentials: const {});

      expect(results, isEmpty);
      expect(called, isFalse, reason: '空查询不该产生请求');
    });
  });

  group('OpenLibrary 错误文案化', () {
    test('4xx 解析 detail[].msg 并中文化（不再裸露 HTTP 400）', () async {
      final mockClient = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode('{"detail":[{"type":"value_error","loc":["query","q"],'
              '"msg":"Value error, Query too short, must be at least 3 characters"}]}'),
          400,
          headers: _utf8Json,
        );
      });

      final ds = OpenLibraryDataSource(client: mockClient);
      await expectLater(
        ds.searchBooks('百年孤独', config: const {}, credentials: const {}),
        throwsA(isA<DataSourceException>().having(
          (e) => e.message,
          'message',
          allOf(contains('至少 3 个字符'), isNot(contains('HTTP 400'))),
        )),
      );
    });

    test('非 JSON 错误页回退通用文案（保留状态码便于排查）', () async {
      final mockClient = MockClient(
        (request) async => http.Response('<html>502 Bad Gateway</html>', 502),
      );

      final ds = OpenLibraryDataSource(client: mockClient);
      await expectLater(
        ds.searchBooks('百年孤独', config: const {}, credentials: const {}),
        throwsA(isA<DataSourceException>().having(
          (e) => e.message,
          'message',
          contains('HTTP 502'),
        )),
      );
    });

    test('响应缺 charset 时仍按 UTF-8 解码（中文不乱码）', () async {
      final mockClient = MockClient((request) async {
        // 关键：content-type 不带 charset —— http 包的 body getter 会按 latin1 解
        return http.Response.bytes(
          utf8.encode('{"docs":[{"key":"/works/OL1W","title":"百年孤独(精)"}]}'),
          200,
          headers: const {'content-type': 'application/json'},
        );
      });

      final ds = OpenLibraryDataSource(client: mockClient);
      final results =
          await ds.searchBooks('百年孤独', config: const {}, credentials: const {});

      // 夹具书名带「(精)」装帧后缀：中文没乱码 + 后缀被清洗，一次断言覆盖两件事
      expect(results.single.title, '百年孤独',
          reason: '必须显式 utf8.decode(bodyBytes)，否则中文变乱码');
    });
  });

  group('自定义源缺口修复', () {
    test('parseBookItem 映射 categories（tags / category 别名）', () {
      final byTags = SmartResponseParser.parseBookItem(
        {'title': '三体', 'tags': ['科幻', '中国文学']},
      );
      expect(byTags!.categories, ['科幻', '中国文学']);

      final byCategory = SmartResponseParser.parseBookItem(
        {'title': '活着', 'category': '文学,当代'},
      );
      expect(byCategory!.categories, ['文学', '当代']);

      final none = SmartResponseParser.parseBookItem({'title': '无分类'});
      expect(none!.categories, isEmpty);
    });

    test('自定义书籍源声明 detailUrlTemplate 配置项（UI 可填）', () {
      final ds = CustomBookDataSource();
      final field = ds.configFields
          .where((f) => f.key == 'detailUrlTemplate')
          .toList(growable: false);
      expect(field, hasLength(1),
          reason: 'getBookDetail 会读取该配置，UI 必须有入口，否则详情永远拿不到');
      expect(field.single.required, isFalse,
          reason: '非必填：不填只跳过详情补全，不该阻止保存');
    });

    test('未配置详情模板时给出可读提示（而非变量名）', () async {
      final ds = CustomBookDataSource();
      await expectLater(
        ds.getBookDetail(
          '1',
          config: const {'baseUrl': 'https://api.example.com'},
          credentials: const {},
        ),
        throwsA(isA<DataSourceException>().having(
          (e) => e.message,
          'message',
          allOf(contains('详情接口模板'), isNot(contains('detailUrlTemplate'))),
        )),
      );
    });
  });

  // P2 数据质量：把 OpenLibrary 返回的脏字段在「进入应用」前洗一遍。
  // 这些脏数据直接回填会让用户看到「Nanhai Publishing House」「Protected DAISY」
  // 之类的值，或让同一本书因书名带括号而无法在多源聚合时去重。
  group('OpenLibrary 字段清洗（P2 数据质量）', () {
    Future<List<BookSearchResult>> searchWith(
      String docsJson, {
      String query = '百年孤独',
    }) async {
      final mockClient = MockClient(
        (request) async => http.Response('{"docs":$docsJson}', 200,
            headers: _utf8Json),
      );
      final ds = OpenLibraryDataSource(client: mockClient);
      return ds.searchBooks(query, config: const {}, credentials: const {});
    }

    test('出版社中英混排时优先取中文条目', () async {
      final results = await searchWith(
        '[{"key":"/works/OL1W","title":"三体",'
        '"publisher":["Chongqing Publishing House","重庆出版社"]}]',
      );
      expect(results.single.publisher, '重庆出版社',
          reason: '中文书回填英文出版社，用户在表单里对不上');
    });

    test('无中文条目时回退第一条非空出版社（不返回 null）', () async {
      final results = await searchWith(
        '[{"key":"/works/OL1W","title":"The Old Man and the Sea",'
        '"publisher":["  ","Charles Scribner\'s Sons"]}]',
      );
      expect(results.single.publisher, 'Charles Scribner\'s Sons');
    });

    test('subject 过滤噪音并去重（控制号 / 层级词 / 平台占位词）', () async {
      final results = await searchWith(
        '[{"key":"/works/OL1W","title":"百年孤独","subject":['
        '"Fiction","Fiction: general","(OCoLC)123456","=Series=",'
        '"Protected DAISY","Fiction","Large type books","Magic realism"]}]',
      );
      expect(results.single.categories, ['Fiction', 'Magic realism'],
          reason: '噪音会冲乱分类字段，重复项也会让映射结果不稳定');
    });

    test('作者按「，、；」拆分，机构片段整段丢弃', () async {
      final results = await searchWith(
        '[{"key":"/works/OL1W","title":"百年孤独","author_name":['
        '"新华书店北美网 加西亚·马尔克斯 著、新经典文化",'
        '"刘慈欣、三体工作室出品"]}]',
      );
      expect(results.single.authors, ['加西亚·马尔克斯', '刘慈欣'],
          reason: '「新经典文化」「三体工作室出品」是机构，不是作者；'
              '前导店铺名与「著」后缀同样要去掉');
    });

    test('书名剥离装帧后缀，叠加写法也能剥干净', () async {
      final results = await searchWith(
        '[{"key":"/works/OL1W","title":"百年孤独(精)"},'
        '{"key":"/works/OL2W","title":"活着（平装）"},'
        '{"key":"/works/OL3W","title":"百年孤独(精)[精装]"},'
        '{"key":"/works/OL4W","title":"三体"},'
        '{"key":"/works/OL5W","title":"微积分（上册）"}]',
      );
      expect(
        results.map((r) => r.title).toList(),
        ['百年孤独', '活着', '百年孤独', '三体', '微积分（上册）'],
        reason: '装帧后缀要去掉，但「（上册）」这类真实副标题不能被误伤',
      );
    });
  });
}
