// P1 抗慢 —— Provider 层缓存与「两跳压一跳」
//
// 这些用例锁住的是**「不做无谓网络请求」**这条边界：
// 国内访问 OpenLibrary / Google Books 常需 2–5s，自建代理还会撞冷启动，
// 任何一次多余的往返都是用户实打实多等的几秒。回归时最容易被改坏，所以单列。

import 'package:flutter_test/flutter_test.dart';
import 'package:moying/models/data_source.dart';
import 'package:moying/providers/data_source_provider.dart';
import 'package:moying/services/data_source_interface.dart';
import 'package:moying/services/data_source_manager.dart';

// ==================== Fake 实现 ====================

/// 无凭据的内存凭据仓（避免测试触碰真实安全存储）
class _NoCreds implements DataSourceCredentialStore {
  @override
  Future<String?> read(String sourceId, String key) async => null;

  @override
  Future<void> write(String sourceId, String key, String value) async {}

  @override
  Future<void> delete(String sourceId, String key) async {}
}

/// 记录调用的书籍源：搜索次数、详情次数都要能被断言
class _CountingBookSource implements BookDataSource {
  _CountingBookSource({
    this.results = const [],
    this.detail,
  });

  /// 每次 searchBooks 收到的查询词（长度即网络请求次数）
  final List<String> queries = [];

  /// getBookDetail 被调用次数
  int detailCalls = 0;

  List<BookSearchResult> results;
  BookSearchResult? detail;

  @override
  DataSourceType get type => DataSourceType.openLibrary;

  @override
  List<ConfigField> get configFields => const [];

  @override
  Future<bool> testConnection({
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async =>
      true;

  @override
  Future<List<BookSearchResult>> searchBooks(
    String query, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
    int limit = 10,
  }) async {
    queries.add(query);
    return results.take(limit).toList();
  }

  @override
  Future<BookSearchResult> getBookDetail(
    String externalId, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async {
    detailCalls++;
    final value = detail;
    if (value == null) {
      throw const DataSourceException('本用例未编排详情', silent: true);
    }
    return value;
  }
}

/// 默认源 = 注入的 fake（内置预设里只有 OpenLibrary 一个书籍源）
Future<DataSourceProvider> _providerWith(_CountingBookSource fake) async {
  final manager = DataSourceManager(
    credentials: _NoCreds(),
    openLibrary: fake,
  );
  final provider = DataSourceProvider(manager: manager);
  addTearDown(provider.dispose);
  await provider.init();
  return provider;
}

List<BookSearchResult> _filler(int n) => [
      for (var i = 0; i < n; i++)
        BookSearchResult(externalId: 'ol-$i', title: '测试书 $i'),
    ];

/// 字段全满的搜索结果——模拟豆瓣系自建代理的搜索响应
/// （它的服务端对每条结果又抓了一次详情页，所以搜索就带回了全部字段）
const BookSearchResult _completeResult = BookSearchResult(
  externalId: '/works/OL1W',
  title: '三体',
  authors: ['刘慈欣'],
  publisher: '重庆出版社',
  year: 2008,
  isbn: '9787536692930',
  pageCount: 302,
  coverUrl: 'https://img.example.com/x.jpg',
  rating: 4.5,
  description: '文化大革命期间……',
  categories: ['科幻'],
);

void main() {
  group('搜索结果缓存', () {
    test('同一关键词重复检索命中缓存：第二次不再打网络', () async {
      final fake = _CountingBookSource(results: _filler(10));
      final provider = await _providerWith(fake);

      await provider.searchBooks('三体');
      expect(fake.queries, ['三体']);

      await provider.searchBooks('三体');

      expect(fake.queries, ['三体'], reason: '缓存命中就该省掉整次往返');
      expect(provider.bookResults, hasLength(10));
      expect(provider.bookSearchSourceNames, ['Open Library'],
          reason: '来源标注要跟着缓存一起回放，否则标题栏会失真');
    });

    test('缓存探测早于 3s 节流：回头搜同一个词不会被判「请求过于频繁」', () async {
      final fake = _CountingBookSource(results: _filler(10));
      final provider = await _providerWith(fake);

      await provider.searchBooks('三体');

      // 换一个词，立刻搜——这才是节流该拦住的场景
      await provider.searchBooks('活着');
      expect(provider.searchError, '请求过于频繁，请稍后再试');
      expect(provider.bookResults, isNull);

      // 回到已缓存的词：没有产生网络流量，不该被节流拦下
      await provider.searchBooks('三体');
      expect(provider.searchError, isNull,
          reason: '缓存命中没有流量，不该消耗节流额度');
      expect(provider.bookResults, hasLength(10));
      expect(fake.queries, ['三体'], reason: '被节流那次也没真的发出去');
    });

    test('不同关键词不共享缓存（「活着」不会被「三体」的结果顶替）', () async {
      final fake = _CountingBookSource(
        results: const [BookSearchResult(externalId: 'ol-1', title: '三体')],
      );
      final provider = await _providerWith(fake);

      await provider.searchBooks('三体');
      expect(provider.bookResults!.single.title, '三体');

      // 紧接着换一个词：它会先探缓存（未命中），再撞上 3s 节流。
      // 撞节流这件事本身就说明它**没有**吃到「三体」的缓存——
      // 若缓存键不含查询词，这里会错误地回放《三体》。
      await provider.searchBooks('活着');
      expect(provider.searchError, '请求过于频繁，请稍后再试');
      expect(provider.bookResults, isNull);
      expect(fake.queries, ['三体']);
    });

    test('空结果也进缓存（避免反复打一个已知没有结果的词）', () async {
      final fake = _CountingBookSource(results: const []);
      final provider = await _providerWith(fake);

      await provider.searchBooks('不存在的书');
      expect(provider.searchError, '');
      await provider.searchBooks('不存在的书');

      expect(fake.queries, hasLength(1));
      expect(provider.searchError, '', reason: '缓存回放后「无结果」的语义要保持');
    });

    test('更新数据源配置 → 缓存失效（改镜像地址后不该再看到旧结果）', () async {
      final fake = _CountingBookSource(results: _filler(3));
      final provider = await _providerWith(fake);
      final config = provider.configs.firstWhere((c) => c.id == 'builtin_openlibrary');

      await provider.searchBooks('三体');
      await provider.searchBooks('三体');
      expect(fake.queries, hasLength(1));

      await provider.updateSource(
        config.copyWith(config: const {'baseUrl': 'https://mirror.example.com'}),
      );
      await provider.searchBooks('三体');

      expect(fake.queries, hasLength(2), reason: '换了地址，旧结果立刻作废');
    });

    test('切换默认源 → 缓存失效', () async {
      final fake = _CountingBookSource(results: _filler(3));
      final provider = await _providerWith(fake);

      await provider.searchBooks('三体');
      await provider.setDefault('builtin_openlibrary');
      await provider.searchBooks('三体');

      expect(fake.queries, hasLength(2), reason: '主源可能换了，缓存键含源 id');
    });

    test('clearResults 不清缓存（选完书回头再搜同一个词不该重新等网络）', () async {
      final fake = _CountingBookSource(results: _filler(3));
      final provider = await _providerWith(fake);

      await provider.searchBooks('三体');
      provider.clearResults();
      await provider.searchBooks('三体');

      expect(fake.queries, hasLength(1));
    });
  });

  group('两跳压一跳（详情补全已成冗余时跳过网络）', () {
    test('判定本身：字段全满才算冗余', () {
      expect(bookDetailIsRedundant(_completeResult), isTrue);
    });

    test('字段全满 → 不发详情请求，且不算失败', () async {
      final fake = _CountingBookSource(detail: _completeResult);
      final provider = await _providerWith(fake);

      final detail = await provider.fetchBookDetail(_completeResult);

      expect(detail, isNull, reason: '调用方按「无详情」处理，直接用搜索结果');
      expect(fake.detailCalls, 0, reason: '省掉这一次注定拿回同样对象的往返');
      expect(provider.lastDetailError, isNull,
          reason: '这是「不需要补全」，不是「补全失败」，不能弹提示');
    });

    // 反向边界：任何一项缺失都必须仍然发请求，
    // 否则就成了「为了省一次往返反而少回填字段」
    test('缺任一可补字段 → 仍然发详情请求', () async {
      final incomplete = <String, BookSearchResult>{
        '出版社': const BookSearchResult(
          externalId: 'OL1W',
          title: '三体',
          isbn: '9787536692930',
          pageCount: 302,
          rating: 4.5,
          description: '简介',
          categories: ['科幻'],
        ),
        'ISBN': const BookSearchResult(
            externalId: 'OL1W',
            title: '三体',
            publisher: '重庆出版社',
            pageCount: 302,
            rating: 4.5,
            description: '简介',
            categories: ['科幻']),
        '页数': const BookSearchResult(
            externalId: 'OL1W',
            title: '三体',
            publisher: '重庆出版社',
            isbn: '9787536692930',
            rating: 4.5,
            description: '简介',
            categories: ['科幻']),
        '简介': const BookSearchResult(
            externalId: 'OL1W',
            title: '三体',
            publisher: '重庆出版社',
            isbn: '9787536692930',
            pageCount: 302,
            rating: 4.5,
            categories: ['科幻']),
        '分类': const BookSearchResult(
            externalId: 'OL1W',
            title: '三体',
            publisher: '重庆出版社',
            isbn: '9787536692930',
            pageCount: 302,
            rating: 4.5,
            description: '简介'),
        '评分': const BookSearchResult(
            externalId: 'OL1W',
            title: '三体',
            publisher: '重庆出版社',
            isbn: '9787536692930',
            pageCount: 302,
            description: '简介',
            categories: ['科幻']),
      };

      for (final entry in incomplete.entries) {
        expect(bookDetailIsRedundant(entry.value), isFalse,
            reason: '缺「${entry.key}」不该判为冗余');

        final fake = _CountingBookSource(detail: _completeResult);
        final provider = await _providerWith(fake);
        await provider.fetchBookDetail(entry.value);

        expect(fake.detailCalls, 1,
            reason: '缺「${entry.key}」时必须仍然去打详情，不能为了省请求少回填');
      }
    });

    test('描述是空白串 → 仍视为缺失', () async {
      const blank = BookSearchResult(
        externalId: 'OL1W',
        title: '三体',
        publisher: '重庆出版社',
        isbn: '9787536692930',
        pageCount: 302,
        rating: 4.5,
        description: '   ',
        categories: ['科幻'],
      );
      expect(bookDetailIsRedundant(blank), isFalse);
    });
  });

  group('详情缓存', () {
    test('同一本书重复取详情命中缓存', () async {
      const searchOnly = BookSearchResult(
        externalId: '/works/OL1W',
        title: '三体',
        authors: ['刘慈欣'],
      );
      final fake = _CountingBookSource(detail: _completeResult);
      final provider = await _providerWith(fake);

      final first = await provider.fetchBookDetail(searchOnly);
      final second = await provider.fetchBookDetail(searchOnly);

      expect(fake.detailCalls, 1, reason: 'OpenLibrary 详情是 work + editions 两跳，缓存价值更高');
      expect(first, isNotNull);
      expect(second, first);
    });

    test('externalId 为空时不进缓存——不同条目不能互相污染', () async {
      const a = BookSearchResult(externalId: '', title: '甲');
      const b = BookSearchResult(externalId: '', title: '乙');
      final fake = _CountingBookSource(detail: _completeResult);
      final provider = await _providerWith(fake);

      await provider.fetchBookDetail(a);
      await provider.fetchBookDetail(b);

      expect(fake.detailCalls, 2,
          reason: '键会退化成「源 id + 空串」，两个条目会撞成同一个缓存位');
    });

    test('不同条目各自缓存', () async {
      const a = BookSearchResult(externalId: '/works/OL1W', title: '三体');
      const b = BookSearchResult(externalId: '/works/OL2W', title: '活着');
      final fake = _CountingBookSource(detail: _completeResult);
      final provider = await _providerWith(fake);

      await provider.fetchBookDetail(a);
      await provider.fetchBookDetail(b);
      await provider.fetchBookDetail(a);
      await provider.fetchBookDetail(b);

      expect(fake.detailCalls, 2);
    });
  });
}
