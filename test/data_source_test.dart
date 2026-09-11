// P6 联网信息补全测试：
// 1) DataSourceConfig 序列化/复制 + Book.isbn
// 2) SourceConfigCheck 配置完整性校验
// 3) DataSourceManager：预设落盘 / 设默认互斥 / 移除兜底 / 凭据清理 / 测试连接
// 4) DataSourceProvider：fake 源搜索 / 详情回退 / 缺凭据检测
// 5) 备份包含 data_sources.json、恢复还原（不含凭据）
// 6) Widget：管理页渲染与设默认、书籍/电影编辑页快速检索回填端到端
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:moying/data/library_store.dart';
import 'package:moying/models/book.dart';
import 'package:moying/models/data_source.dart';
import 'package:moying/providers/data_source_provider.dart';
import 'package:moying/providers/library_provider.dart';
import 'package:moying/screens/book_edit_screen.dart';
import 'package:moying/screens/data_source_screen.dart';
import 'package:moying/screens/movie_edit_screen.dart';
import 'package:moying/services/backup_service.dart';
import 'package:moying/services/data_source_interface.dart';
import 'package:moying/services/data_source_manager.dart';

// ==================== Fake 实现 ====================

/// 内存凭据仓（记录删除，验证 removeConfig 清理）
class _FakeCreds implements DataSourceCredentialStore {
  final Map<String, String> values = {};
  final List<String> deleted = [];

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
    deleted.add(_k(sourceId, key));
    values.remove(_k(sourceId, key));
  }
}

class _FakeBookSource implements BookDataSource {
  @override
  DataSourceType get type => DataSourceType.openLibrary;

  @override
  List<ConfigField> get configFields => const [];

  final List<String> queries = [];

  /// 详情抛出的异常（null = 正常返回）；用于验证 silent 与非 silent 两条路径
  DataSourceException? detailError;

  /// getBookDetail 实际被调用次数。
  /// 断言它 > 0 才能证明用例真的走到了详情通道——否则一旦 Provider 侧
  /// 加了「跳过冗余详情」这类闸门，用例会「静默地」不再覆盖目标分支。
  int detailCalls = 0;

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
    // 形态刻意对齐真实搜索接口：只带列表页会展示的字段（书名/作者/出版社/年份/
    // ISBN/封面），页数 / 简介 / 分类 / 评分留给详情补全。
    //
    // 「字段全满」会踩到 Provider 的「两跳压一跳」判定（见 bookDetailIsRedundant）
    // ——那时详情请求会被整条跳过，下面验证 silent / 非 silent 的用例就跑不到
    // getBookDetail 了；所以这里必须保留至少一项待补字段。
    return const [
      BookSearchResult(
        externalId: 'gb-1',
        title: '三体',
        authors: ['刘慈欣'],
        publisher: '重庆出版社',
        year: 2008,
        isbn: '9787536692930',
        coverUrl: 'https://example.com/cover.jpg',
      ),
    ];
  }

  @override
  Future<BookSearchResult> getBookDetail(
    String externalId, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async {
    detailCalls++;
    final err = detailError;
    if (err != null) throw err;
    return const BookSearchResult(
      externalId: 'gb-1',
      title: '三体',
      authors: ['刘慈欣'],
      pageCount: 302,
      description: '文化大革命期间……',
      categories: ['科幻', '小说'],
    );
  }
}

class _FakeMovieSource implements MovieDataSource {
  _FakeMovieSource({this.detailShouldFail = false});

  /// 模拟详情接口异常（验证搜索结果回退路径）
  bool detailShouldFail;

  @override
  DataSourceType get type => DataSourceType.tmdb;

  @override
  List<ConfigField> get configFields => const [
        ConfigField(key: 'apiKey', label: 'API Key', isSecret: true, required: true),
      ];

  @override
  Future<bool> testConnection({
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async =>
      credentials['apiKey']?.isNotEmpty ?? false;

  @override
  Future<List<MovieSearchResult>> searchMovies(
    String query, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
    int limit = 10,
  }) async =>
      const [
        MovieSearchResult(
          externalId: '42',
          title: '星际穿越',
          originalTitle: 'Interstellar',
          year: 2014,
        ),
      ];

  @override
  Future<MovieSearchResult> getMovieDetail(
    String externalId, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
  }) async {
    if (detailShouldFail) {
      throw const DataSourceException('详情接口异常');
    }
    return MovieSearchResult(
      externalId: externalId,
      title: '星际穿越',
      originalTitle: 'Interstellar',
      year: 2014,
      director: '克里斯托弗·诺兰',
      genres: const ['科幻', '冒险'],
      posterUrl: 'https://example.com/poster.jpg',
      rating: 4.5,
      runtimeMinutes: 169,
      cast: const [
        CastMember(name: '马修·麦康纳'),
        CastMember(name: '安妮·海瑟薇'),
      ],
    );
  }
}

// ==================== 测试 ====================

LibrarySnapshot _seed() => const LibrarySnapshot(books: [], movies: [], actors: []);

/// 四集合文件齐全的 store（备份必需）
Future<LibraryStore> _makeStore(Directory root, String name) async {
  final dir = Directory('${root.path}${Platform.pathSeparator}$name');
  final store = LibraryStore(dir, seed: _seed());
  await store.load();
  await store.loadProfile();
  return store;
}

DataSourceManager _managerWithFakes({
  LibraryStore? store,
  _FakeCreds? creds,
  _FakeMovieSource? movie,
  _FakeBookSource? book,
}) =>
    DataSourceManager(
      store: store,
      credentials: creds ?? _FakeCreds(),
      tmdb: movie ?? _FakeMovieSource(),
      openLibrary: book ?? _FakeBookSource(),
    );

void main() {
  late Directory tmpDir;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('moying_ds_test');
  });

  tearDown(() async {
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
  });

  group('数据模型', () {
    test('DataSourceConfig toJson/fromJson 往返一致', () {
      const config = DataSourceConfig(
        id: 'builtin_tmdb',
        type: DataSourceType.tmdb,
        name: 'TMDB',
        isDefault: true,
        config: {'language': 'zh-CN'},
        status: DataSourceStatus.connected,
        summary: '连接成功',
      );
      final restored = DataSourceConfig.fromJson(config.toJson());
      expect(restored, config);
      expect(restored.config['language'], 'zh-CN');
      expect(restored.category, DataSourceCategory.movie);
    });

    test('copyWith 保留未指定字段 / clearSummary 清空摘要', () {
      const config = DataSourceConfig(
        id: 'a',
        type: DataSourceType.googleBooks,
        name: 'GB',
        summary: '旧摘要',
      );
      final updated = config.copyWith(name: 'GB2', isDefault: true);
      expect(updated.name, 'GB2');
      expect(updated.isDefault, isTrue);
      expect(updated.summary, '旧摘要');

      final cleared = config.copyWith(clearSummary: true);
      expect(cleared.summary, isNull);
      expect(cleared.id, 'a');
    });

    test('Book.isbn 序列化往返 + copyWith 保留', () {
      final book = Book(
        id: 'b1',
        title: '三体',
        author: '刘慈欣',
        totalPages: 302,
        currentPage: 0,
        status: BookStatus.planToRead,
        isbn: '9787536692930',
        createdAt: DateTime(2026, 1, 1),
      );
      final restored = Book.fromJson(book.toJson());
      expect(restored.isbn, '9787536692930');
      expect(restored.copyWith(title: '三体Ⅱ').isbn, '9787536692930');
    });

    test('isConfigured：required 项凭据或 config 任一有值即通过', () {
      const fields = [
        ConfigField(key: 'apiKey', label: 'API Key', isSecret: true, required: true),
        ConfigField(key: 'language', label: '语言'),
      ];
      // secret 凭据命中
      expect(
        fields.isConfigured(config: const {}, credentials: const {'apiKey': 'v3_xx'}),
        isTrue,
      );
      // 非 secret config 命中
      expect(
        fields.isConfigured(
            config: const {'apiKey': 'in-config'}, credentials: const {}),
        isTrue,
      );
      // 都缺 → 不通过
      expect(
        fields.isConfigured(config: const {}, credentials: const {}),
        isFalse,
      );
    });
  });

  group('DataSourceManager', () {
    test('首次加载写入内置预设（TMDB + Open Library，各自类别默认）', () async {
      final store = await _makeStore(tmpDir, 'presets');
      final manager = _managerWithFakes(store: store);
      final configs = await manager.loadConfigs();

      expect(configs.length, 2);
      expect(manager.defaultSourceOf(DataSourceCategory.movie)!.type,
          DataSourceType.tmdb);
      expect(manager.defaultSourceOf(DataSourceCategory.book)!.type,
          DataSourceType.openLibrary);

      // 已落盘
      final persisted = await store.loadDataSourceConfigs();
      expect(persisted, isNotNull);
      expect(persisted!.length, 2);
    });

    test('旧版 builtin_googlebooks 默认源自动迁移为 OpenLibrary', () async {
      final store = await _makeStore(tmpDir, 'legacy');
      await store.saveDataSourceConfigs(const [
        DataSourceConfig(
          id: 'builtin_tmdb',
          type: DataSourceType.tmdb,
          name: 'TMDB (The Movie Database)',
          isDefault: true,
        ),
        DataSourceConfig(
          id: 'builtin_googlebooks',
          type: DataSourceType.googleBooks,
          name: 'Google Books',
          isDefault: true,
          status: DataSourceStatus.connected,
        ),
      ]);

      final manager = _managerWithFakes(store: store);
      final configs = await manager.loadConfigs();
      // Google Books 默认项被替换为 OpenLibrary；TMDB 不受影响
      expect(configs.any((c) => c.id == 'builtin_googlebooks'), isFalse);
      expect(configs.any((c) => c.id == 'builtin_openlibrary'), isTrue);
      expect(manager.defaultSourceOf(DataSourceCategory.book)!.type,
          DataSourceType.openLibrary);
      // 迁移结果已落盘
      final persisted = await store.loadDataSourceConfigs();
      expect(
        persisted!.any((c) => c.id == 'builtin_openlibrary' && c.isDefault),
        isTrue,
      );
    });

    test('用户已手动改默认（非内置 Google Books）时不做迁移', () async {
      final store = await _makeStore(tmpDir, 'manual');
      await store.saveDataSourceConfigs(const [
        DataSourceConfig(
          id: 'user_gb',
          type: DataSourceType.googleBooks,
          name: '自建谷歌源',
          isDefault: true,
        ),
      ]);

      final manager = _managerWithFakes(store: store);
      final configs = await manager.loadConfigs();
      expect(configs.single.id, 'user_gb');
      expect(configs.single.type, DataSourceType.googleBooks);
    });

    test('已有配置文件时直接读取（不覆盖用户配置）', () async {
      final store = await _makeStore(tmpDir, 'existing');
      await store.saveDataSourceConfigs(const [
        DataSourceConfig(
          id: 'user_gb',
          type: DataSourceType.googleBooks,
          name: '自定义书源',
          isDefault: true,
        ),
      ]);

      final manager = _managerWithFakes(store: store);
      final configs = await manager.loadConfigs();
      expect(configs.length, 1);
      expect(configs.first.name, '自定义书源');
    });

    test('设默认同类互斥', () async {
      final manager = _managerWithFakes();
      await manager.loadConfigs();
      await manager.addConfig(const DataSourceConfig(
        id: 'user_tmdb2',
        type: DataSourceType.tmdb,
        name: 'TMDB 代理',
      ));

      await manager.setDefault('user_tmdb2');
      expect(
        manager.defaultSourceOf(DataSourceCategory.movie)!.id,
        'user_tmdb2',
      );
      // 书籍默认不受影响
      expect(manager.defaultSourceOf(DataSourceCategory.book)!.id,
          'builtin_openlibrary');
    });

    test('移除默认源后同类剩余第一个顶上，凭据一并清理', () async {
      final creds = _FakeCreds();
      final manager = _managerWithFakes(creds: creds);
      await manager.loadConfigs();
      await manager.saveCredential(
        manager.configs.firstWhere((c) => c.id == 'builtin_tmdb'),
        'apiKey',
        'v3_secret',
      );

      await manager.removeConfig('builtin_tmdb');
      expect(manager.configs.any((c) => c.id == 'builtin_tmdb'), isFalse);
      // 影视默认兜底：无剩余影视源 → null；书籍不受影响
      expect(manager.defaultSourceOf(DataSourceCategory.movie), isNull);
      expect(creds.deleted, contains('builtin_tmdb/apiKey'));
    });

    test('测试连接：成功置 connected，超时消息置 timeout', () async {
      final manager = _managerWithFakes();
      await manager.loadConfigs();
      final tmdb =
          manager.configs.firstWhere((c) => c.id == 'builtin_tmdb');

      // fake 源要求 apiKey 才算成功——未配置 → error
      final failed = await manager.testConnection(tmdb);
      expect(failed.status, DataSourceStatus.error);

      await manager.saveCredential(tmdb, 'apiKey', 'v3_ok');
      final ok = await manager.testConnection(tmdb);
      expect(ok.status, DataSourceStatus.connected);
      expect(ok.summary, '连接成功');
    });
  });

  group('DataSourceProvider 搜索', () {
    test('searchBooks 走默认书籍源，结果写入 bookResults', () async {
      final book = _FakeBookSource();
      final provider = DataSourceProvider(
        manager: _managerWithFakes(book: book),
      );
      await provider.init();

      await provider.searchBooks('三体');
      expect(book.queries, ['三体']);
      expect(provider.bookResults, isNotNull);
      expect(provider.bookResults!.first.title, '三体');
      expect(provider.isSearching, isFalse);
      expect(provider.searchError, isNull);
    });

    test('空结果不算错误（searchError 置空串）', () async {
      final book = _EmptyBookSource();
      final provider = DataSourceProvider(
        manager: _managerWithFakes(book: book),
      );
      await provider.init();

      await provider.searchBooks('不存在');
      expect(provider.bookResults, isEmpty);
      expect(provider.searchError, '');
    });

    test('电影详情失败回退搜索结果回填', () async {
      final provider = DataSourceProvider(
        manager: _managerWithFakes(
          movie: _FakeMovieSource(detailShouldFail: true),
        ),
      );
      await provider.init();

      await provider.searchMovies('星际穿越');
      final detail = await provider.fetchMovieDetail(
        provider.movieResults!.first,
      );
      // 详情失败返回 null，调用方用搜索结果回填
      expect(detail, isNull);
      expect(provider.searchError, isNull);
    });

    test('详情仅能力缺失（silent）→ 不写 lastDetailError，不误报', () async {
      final book = _FakeBookSource()
        ..detailError = const DataSourceException(
          '该数据源未配置「详情接口模板」',
          silent: true,
        );
      final provider = DataSourceProvider(
        manager: _managerWithFakes(book: book),
      );
      await provider.init();

      await provider.searchBooks('三体');
      final detail =
          await provider.fetchBookDetail(provider.bookResults!.first);

      expect(detail, isNull, reason: '仍然回退搜索结果');
      expect(book.detailCalls, 1,
          reason: '必须真的走到详情通道，否则这个用例什么也没验证');
      expect(provider.lastDetailError, isNull,
          reason: '能力缺失不是失败——详情拿不到也不该弹「补全失败」');
    });

    test('详情真实失败（非 silent）→ 写入 lastDetailError，必须提示', () async {
      final book = _FakeBookSource()
        ..detailError = const DataSourceException('详情接口超时，请稍后重试');
      final provider = DataSourceProvider(
        manager: _managerWithFakes(book: book),
      );
      await provider.init();

      await provider.searchBooks('三体');
      final detail =
          await provider.fetchBookDetail(provider.bookResults!.first);

      expect(detail, isNull);
      expect(book.detailCalls, 1,
          reason: '必须真的走到详情通道，否则这个用例什么也没验证');
      expect(provider.lastDetailError, '详情接口超时，请稍后重试');
    });

    test('缺凭据检测：填了凭据后不再命中', () async {
      final provider = DataSourceProvider(
        manager: _managerWithFakes(),
      );
      await provider.init();

      var missing = await provider.sourcesMissingCredentials();
      expect(missing, contains('TMDB (The Movie Database)'));
      // Open Library 免配置不命中
      expect(missing, isNot(contains('Open Library')));

      final tmdb = provider.configs.firstWhere((c) => c.id == 'builtin_tmdb');
      await provider.saveCredential(tmdb, 'apiKey', 'v3_ok');
      missing = await provider.sourcesMissingCredentials();
      expect(missing, isEmpty);
    });
  });

  group('备份恢复纳入数据源配置', () {
    test('备份包含 data_sources.json（计数入 manifest），恢复后还原', () async {
      final src = await _makeStore(tmpDir, 'src');
      await src.saveDataSourceConfigs(const [
        DataSourceConfig(
          id: 'builtin_tmdb',
          type: DataSourceType.tmdb,
          name: 'TMDB',
          isDefault: true,
          status: DataSourceStatus.connected,
          summary: '连接成功',
        ),
      ]);

      final bytes =
          await BackupService(store: src).buildBackup(includeImages: false);
      final manifest = await BackupService(store: src).peekBackup(bytes);
      expect(manifest.counts['data_sources.json'], 1);

      final dst = await _makeStore(tmpDir, 'dst');
      await BackupService(store: dst).restoreBackup(bytes);

      final restored = await dst.loadDataSourceConfigs();
      expect(restored, isNotNull);
      expect(restored!.length, 1);
      expect(restored.first.id, 'builtin_tmdb');
      expect(restored.first.summary, '连接成功');
    });

    test('备份无数据源文件（旧版本）→ 恢复保留本地配置', () async {
      final src = await _makeStore(tmpDir, 'src'); // 无 data_sources.json
      final bytes =
          await BackupService(store: src).buildBackup(includeImages: false);

      final dst = await _makeStore(tmpDir, 'dst');
      await dst.saveDataSourceConfigs(const [
        DataSourceConfig(
          id: 'user_local',
          type: DataSourceType.googleBooks,
          name: '本地已有',
          isDefault: true,
        ),
      ]);
      await BackupService(store: dst).restoreBackup(bytes);

      final restored = await dst.loadDataSourceConfigs();
      expect(restored!.first.id, 'user_local');
    });

    test('ZIP 备份同样包含数据源配置', () async {
      final src = await _makeStore(tmpDir, 'src');
      await src.saveDataSourceConfigs(const [
        DataSourceConfig(
          id: 'builtin_googlebooks',
          type: DataSourceType.googleBooks,
          name: 'Google Books',
          isDefault: true,
        ),
      ]);
      final bytes =
          await BackupService(store: src).buildBackup(includeImages: true);
      expect(bytes[0] == 0x50 && bytes[1] == 0x4B, isTrue);

      final dst = await _makeStore(tmpDir, 'dst');
      await BackupService(store: dst).restoreBackup(bytes);
      final restored = await dst.loadDataSourceConfigs();
      expect(restored!.first.id, 'builtin_googlebooks');
    });
  });

  group('数据源管理页', () {
    testWidgets('渲染两区预设与默认徽标', (tester) async {
      final provider = DataSourceProvider(manager: _managerWithFakes());
      await provider.init();

      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider.value(value: provider)],
        child: const MaterialApp(home: DataSourceScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('影视数据源'), findsOneWidget);
      expect(find.text('书籍数据源'), findsOneWidget);
      expect(find.text('TMDB (The Movie Database)'), findsOneWidget);
      expect(find.text('Open Library'), findsOneWidget);
      expect(find.text('默认'), findsNWidgets(2));
      expect(find.text('添加影视数据源'), findsOneWidget);
      expect(find.text('添加书籍数据源'), findsOneWidget);
    });

    testWidgets('点击单选设为默认（同类互斥）', (tester) async {
      final provider = DataSourceProvider(manager: _managerWithFakes());
      await provider.init();
      await provider.addSource(const DataSourceConfig(
        id: 'user_tmdb2',
        type: DataSourceType.tmdb,
        name: 'TMDB 代理',
      ));

      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider.value(value: provider)],
        child: const MaterialApp(home: DataSourceScreen()),
      ));
      await tester.pumpAndSettle();

      // 代理行的单选（第一个 radio 是 builtin_tmdb 的）
      await tester.tap(find.byType(Radio<String>).at(1));
      await tester.pump(); // setDefault 异步落盘
      await tester.pump();

      expect(
        provider.defaultMovieSource!.id,
        'user_tmdb2',
      );
    });
  });

  group('书籍编辑页快速检索', () {
    testWidgets('搜索 → 点击结果回填 → 保存写入 isbn 与溯源', (tester) async {
      final library = LibraryProvider();
      final provider = DataSourceProvider(
        manager: _managerWithFakes(book: _FakeBookSource()),
      );
      await provider.init();

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: library),
          ChangeNotifierProvider.value(value: provider),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute(builder: (_) => const BookEditScreen()),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ));

      // 进入添加图书页
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('快速检索'), findsOneWidget);

      // 输入关键词 → debounce 500ms → 搜索
      final searchField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '输入书名 / 作者，联网搜索并回填',
      );
      await tester.enterText(searchField, '三体');
      await tester.pump(const Duration(milliseconds: 900)); // > 800ms debounce
      await tester.pump();
      await tester.pump();

      // 结果列表出现
      expect(find.text('刘慈欣 · 重庆出版社 (2008)'), findsOneWidget);

      // 点击结果 → 回填 + 结果列表收起（输入框与结果条目都含「三体」，精确匹配结果条目）
      await tester.tap(find.byWidgetPredicate(
        (w) => w is Text && w.data == '三体',
      ));
      await tester.pump();

      // 回填后结果列表收起，展示「已填充《三体》，修改关键词可重新搜索」
      expect(find.textContaining('已填充《三体》'), findsOneWidget);
      // v2 布局：ISBN 不再是 TextField，回填值展示在「ISBN / 标识」行
      expect(find.text('9787536692930'), findsOneWidget);
      final titleField = tester.widget<TextField>(find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '输入书名',
      ));
      expect(titleField.controller!.text, '三体');

      final baseBooks = library.books.length;
      // 顶栏保存胶囊（Material+InkWell 包裹）
      final saveBtn = find.ancestor(
        of: find.text('保存'),
        matching: find.byType(InkWell),
      );
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump();

      // 内存模式自带演示种子，按唯一 ISBN 定位新保存的条目（addBook 头部插入）
      expect(library.books.length, baseBooks + 1);
      final saved = library.books.firstWhere(
        (b) => b.isbn == '9787536692930',
      );
      expect(saved.title, '三体');
      expect(saved.source, 'openLibrary:gb-1');
      expect(saved.author, '刘慈欣');
    });
  });

  group('电影编辑页快速检索', () {
    testWidgets('详情回填：导演/片长/类型/主演/溯源，保存落库', (tester) async {
      final library = LibraryProvider();
      final provider = DataSourceProvider(
        manager: _managerWithFakes(),
      );
      await provider.init();

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: library),
          ChangeNotifierProvider.value(value: provider),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).push(
                    MaterialPageRoute(builder: (_) => const MovieEditScreen()),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(find.text('快速检索'), findsOneWidget);

      final searchField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '输入片名，联网搜索并回填',
      );
      await tester.enterText(searchField, '星际穿越');
      await tester.pump(const Duration(milliseconds: 900)); // > 800ms debounce
      await tester.pump();
      await tester.pump();

      expect(find.text('Interstellar · 2014'), findsOneWidget);
      // 输入框与结果条目都含「星际穿越」，精确匹配结果条目的 Text widget
      await tester.tap(find.byWidgetPredicate(
        (w) => w is Text && w.data == '星际穿越',
      ));
      // 详情接口异步 → 轮询推进（SnackBar 动画一并收敛）
      await tester.pumpAndSettle();

      // 回填后结果列表收起，展示「已填充《星际穿越》，修改关键词可重新搜索」
      expect(find.textContaining('已填充《星际穿越》'), findsOneWidget);
      final directorField = tester.widget<TextField>(find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '导演',
      ));
      expect(directorField.controller!.text, '克里斯托弗·诺兰');
      final englishField = tester.widget<TextField>(find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '英文名（可选）',
      ));
      expect(englishField.controller!.text, 'Interstellar');
      // 类型标签回填
      expect(find.text('科幻'), findsOneWidget);
      expect(find.text('冒险'), findsOneWidget);

      final baseMovies = library.movieList.length;
      // 保存（新增模式按钮文案「保存」；按钮在长表单底部，先滚到可见）
      final saveBtn = find.ancestor(
        of: find.text('保存'),
        matching: find.byType(InkWell),
      ).last;
      await tester.ensureVisible(saveBtn);
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pump();
      await tester.pump();

      // 内存模式自带演示种子，按唯一溯源 source 定位新保存的条目（不依赖插入位置）
      expect(library.movieList.length, baseMovies + 1);
      final movie = library.movieList.firstWhere(
        (m) => m.source == 'tmdb:42',
      );
      expect(movie.title, '星际穿越');
      expect(movie.source, 'tmdb:42');
      expect(movie.director, '克里斯托弗·诺兰');
      expect(movie.duration, 169);
      expect(movie.year, 2014);
      expect(movie.genres, containsAll(['科幻', '冒险']));
      // 主演落成演员实体（导演自动槽 + 2 主演）
      final actorNames = library.actors.map((a) => a.name).toSet();
      expect(actorNames, containsAll(['马修·麦康纳', '安妮·海瑟薇']));
      expect(movie.actorIds!.length, 3);
    });
  });
}

/// 恒返回空结果的书籍源
class _EmptyBookSource extends _FakeBookSource {
  @override
  Future<List<BookSearchResult>> searchBooks(
    String query, {
    required Map<String, dynamic> config,
    required Map<String, String> credentials,
    int limit = 10,
  }) async =>
      const [];
}
