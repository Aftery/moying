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

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moying/models/data_source.dart';
import 'package:moying/services/data_sources/open_library_data_source.dart';

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
}
