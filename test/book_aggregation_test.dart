// P3 多源聚合检索测试
//
// 设计语义（见 DataSourceProvider._searchBooksAggregated）：
// - 默认源优先，累计结果不足上限时按优先级补备用源；
// - 合并后按 ISBN / 「书名+首位作者」去重，重复项只用来补空缺字段；
// - 单源失败不打断整体，全部无结果才抛首个异常。
//
// 这些用例同时锁住「不做无谓网络请求」的边界（结果够用就不打备用源），
// 因为国内访问 OpenLibrary / Google Books 都慢，回归时最容易被改坏。

import 'package:flutter_test/flutter_test.dart';
import 'package:moying/models/data_source.dart';
import 'package:moying/providers/data_source_provider.dart';
import 'package:moying/services/book_result_merger.dart';
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

/// 可编排的书籍源：类型 / 结果 / 异常都由用例注入
class _FakeBookSource implements BookDataSource {
  _FakeBookSource({required this.type, this.results = const [], this.error});

  @override
  final DataSourceType type;

  List<BookSearchResult> results;
  DataSourceException? error;

  /// 记录收到的查询词，用来断言「备用源有没有被惊动」
  final List<String> queries = [];

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
    final failure = error;
    if (failure != null) throw failure;
    return results.take(limit).toList();
  }

  @override
  Future<BookSearchResult> getBookDetail(
    String externalId, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async =>
      throw const DataSourceException('本用例不涉及详情补全');
}

/// 生成 [n] 条互不相同的书（用来把主源撑到上限）
List<BookSearchResult> _filler(int n) => [
      for (var i = 0; i < n; i++)
        BookSearchResult(externalId: 'ol-$i', title: '测试书 $i'),
    ];

/// 默认源 = OpenLibrary fake，备用源 = Google Books fake。
/// 备用源需要额外挂一条配置才会进入候选列表（内置预设只有 OpenLibrary）。
Future<DataSourceProvider> _providerWith({
  required _FakeBookSource primary,
  required _FakeBookSource backup,
}) async {
  final manager = DataSourceManager(
    credentials: _NoCreds(),
    openLibrary: primary,
    googleBooks: backup,
  );
  final provider = DataSourceProvider(manager: manager);
  addTearDown(provider.dispose);
  await provider.init();
  await manager.addConfig(const DataSourceConfig(
    id: 'gb',
    type: DataSourceType.googleBooks,
    name: 'Google Books',
    status: DataSourceStatus.connected,
  ));
  return provider;
}

void main() {
  group('BookResultMerger 去重键与归一化', () {
    test('ISBN 归一化：去连字符，非法长度/字符返回 null', () {
      expect(BookResultMerger.normalizeIsbn('978-7-5366-9293-0'), '9787536692930');
      expect(BookResultMerger.normalizeIsbn('9787536692930'), '9787536692930');
      expect(BookResultMerger.normalizeIsbn('080442957X'), isNotNull,
          reason: 'ISBN-10 校验符 X 合法');
      expect(BookResultMerger.normalizeIsbn('12345'), isNull);
      expect(BookResultMerger.normalizeIsbn('三体'), isNull);
      expect(BookResultMerger.normalizeIsbn(null), isNull);
    });

    test('书名归一化：去括号与标点，但不合并同系列的不同卷', () {
      expect(BookResultMerger.normalizeTitle('三体 (The Three-Body Problem)'),
          BookResultMerger.normalizeTitle('三体'));
      expect(BookResultMerger.normalizeTitle('哈利·波特与魔法石'),
          BookResultMerger.normalizeTitle('哈利 波特 与 魔法石'));
      expect(BookResultMerger.normalizeTitle('三体Ⅱ'),
          isNot(BookResultMerger.normalizeTitle('三体')),
          reason: '第二卷不能被并进第一卷');
    });

    test('mergeAll 保留来源优先级，重复项只补空缺字段', () {
      final merged = BookResultMerger.mergeAll([
        const [
          BookSearchResult(externalId: 'ol-1', title: '三体', year: 2008),
        ],
        const [
          BookSearchResult(
            externalId: 'gb-1',
            title: '三体',
            publisher: '重庆出版社',
            pageCount: 302,
            categories: ['科幻'],
          ),
        ],
      ]);

      expect(merged, hasLength(1));
      expect(merged.single.externalId, 'ol-1', reason: '高优先级源的条目胜出');
      expect(merged.single.year, 2008);
      expect(merged.single.publisher, '重庆出版社');
      expect(merged.single.pageCount, 302);
      expect(merged.single.categories, ['科幻']);
    });

    test('标题为空的条目不去重（避免被并成一条）', () {
      final merged = BookResultMerger.mergeAll([
        const [BookSearchResult(externalId: 'a', title: '')],
        const [BookSearchResult(externalId: 'b', title: '')],
      ]);
      expect(merged, hasLength(2));
    });
  });

  group('DataSourceProvider 多源聚合检索', () {
    test('主源结果已达上限 → 不再请求备用源', () async {
      final primary = _FakeBookSource(
        type: DataSourceType.openLibrary,
        results: _filler(10),
      );
      final backup = _FakeBookSource(type: DataSourceType.googleBooks);
      final provider = await _providerWith(primary: primary, backup: backup);

      await provider.searchBooks('三体');

      expect(primary.queries, ['三体']);
      expect(backup.queries, isEmpty, reason: '结果够用就不该多打一次网络');
      expect(provider.bookResults, hasLength(10));
      expect(provider.bookSearchSourceNames, ['Open Library']);
    });

    test('主源不足 → 补备用源，并按 ISBN 去重合并互补字段', () async {
      final primary = _FakeBookSource(
        type: DataSourceType.openLibrary,
        results: const [
          BookSearchResult(
            externalId: '/works/OL1W',
            title: '三体',
            authors: ['刘慈欣'],
            isbn: '9787536692930',
            year: 2008,
          ),
        ],
      );
      final backup = _FakeBookSource(
        type: DataSourceType.googleBooks,
        results: const [
          BookSearchResult(
            externalId: 'gb-1',
            title: '三体',
            authors: ['刘慈欣'],
            // 同一个 ISBN，写法不同（带连字符）——归一化后必须能对上
            isbn: '978-7-5366-9293-0',
            publisher: '重庆出版社',
            pageCount: 302,
            description: '文化大革命期间……',
            categories: ['科幻'],
          ),
          BookSearchResult(
            externalId: 'gb-2',
            title: '三体Ⅱ 黑暗森林',
            authors: ['刘慈欣'],
            isbn: '9787536693968',
          ),
        ],
      );
      final provider = await _providerWith(primary: primary, backup: backup);

      await provider.searchBooks('三体');

      final results = provider.bookResults!;
      expect(results, hasLength(2), reason: '同 ISBN 的两条要合并成一条');
      expect(results.first.externalId, '/works/OL1W',
          reason: '保留主源条目（优先级更高）');
      expect(results.first.year, 2008, reason: '主源已有的值不被备用源覆盖');
      expect(results.first.publisher, '重庆出版社', reason: '备用源补上主源缺的出版社');
      expect(results.first.pageCount, 302);
      expect(results.first.description, '文化大革命期间……');
      expect(results.first.categories, ['科幻']);
      expect(results[1].title, '三体Ⅱ 黑暗森林', reason: '不同书不能被误并');
      expect(provider.bookSearchSourceNames, ['Open Library', 'Google Books']);
    });

    test('无 ISBN 时按「书名 + 首位作者」去重（括号副标题视为同名）', () async {
      final primary = _FakeBookSource(
        type: DataSourceType.openLibrary,
        results: const [
          BookSearchResult(externalId: 'ol-1', title: '活着', authors: ['余华']),
        ],
      );
      final backup = _FakeBookSource(
        type: DataSourceType.googleBooks,
        results: const [
          BookSearchResult(
            externalId: 'gb-1',
            title: '活着（精装）',
            authors: ['余华'],
            publisher: '作家出版社',
            pageCount: 191,
          ),
        ],
      );
      final provider = await _providerWith(primary: primary, backup: backup);

      await provider.searchBooks('活着');

      final results = provider.bookResults!;
      expect(results, hasLength(1), reason: '《活着》与《活着（精装）》是同一本');
      expect(results.single.title, '活着', reason: '保留主源书名');
      expect(results.single.publisher, '作家出版社');
      expect(results.single.pageCount, 191);
    });

    test('主源为空结果 → 用备用源顶上', () async {
      final primary = _FakeBookSource(type: DataSourceType.openLibrary);
      final backup = _FakeBookSource(
        type: DataSourceType.googleBooks,
        results: const [
          BookSearchResult(externalId: 'gb-1', title: '活着', authors: ['余华']),
        ],
      );
      final provider = await _providerWith(primary: primary, backup: backup);

      await provider.searchBooks('活着');

      expect(provider.bookResults, hasLength(1));
      expect(provider.bookResults!.single.externalId, 'gb-1');
      expect(provider.searchError, isNull);
      expect(provider.bookSearchSourceNames, ['Google Books'],
          reason: '只有备用源出了结果，标题就该只标它');
    });

    test('主源报错 → 静默降级到备用源，不把错误抛给用户', () async {
      final primary = _FakeBookSource(
        type: DataSourceType.openLibrary,
        error: const DataSourceException('网络请求失败，请检查网络连接'),
      );
      final backup = _FakeBookSource(
        type: DataSourceType.googleBooks,
        results: const [
          BookSearchResult(externalId: 'gb-1', title: '活着', authors: ['余华']),
        ],
      );
      final provider = await _providerWith(primary: primary, backup: backup);

      await provider.searchBooks('活着');

      expect(provider.bookResults, hasLength(1));
      expect(provider.searchError, isNull, reason: '一个源坏掉不该让整条检索失败');
      expect(provider.bookSearchSourceNames, ['Google Books']);
    });

    test('全部源失败 → 抛出首个异常（保留用户可读文案）', () async {
      final primary = _FakeBookSource(
        type: DataSourceType.openLibrary,
        error: const DataSourceException('OpenLibrary 接口异常：boom'),
      );
      final backup = _FakeBookSource(
        type: DataSourceType.googleBooks,
        error: const DataSourceException('Google Books 请求过于频繁（HTTP 429）'),
      );
      final provider = await _providerWith(primary: primary, backup: backup);

      await provider.searchBooks('活着');

      expect(provider.bookResults, isNull);
      expect(provider.searchError, 'OpenLibrary 接口异常：boom',
          reason: '报主源（用户当前选的源）的原因，而不是最后尝试的那个');
    });

    test('清空检索结果时同步清掉来源标注', () async {
      final primary = _FakeBookSource(
        type: DataSourceType.openLibrary,
        results: const [BookSearchResult(externalId: 'ol-1', title: '三体')],
      );
      final backup = _FakeBookSource(type: DataSourceType.googleBooks);
      final provider = await _providerWith(primary: primary, backup: backup);

      await provider.searchBooks('三体');
      expect(provider.bookSearchSourceNames, isNotEmpty);

      provider.clearResults();
      expect(provider.bookResults, isNull);
      expect(provider.bookSearchSourceNames, isEmpty);
    });
  });
}
