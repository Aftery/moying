import 'dart:convert';
import 'dart:io';

import '../models/actor.dart';
import '../models/book.dart';
import '../models/movie.dart';

/// 三集合数据快照（内存形态与磁盘形态之间的统一载体）
///
/// - 首次启动：磁盘无文件，`load()` 用注入的 seed 初始化并立即写盘；
/// - 后续启动：磁盘有文件，`load()` 逐文件读盘还原；
/// - `Provider` 持有快照中的列表进行状态管理（P2b 接线）。
class LibrarySnapshot {
  const LibrarySnapshot({
    required this.books,
    required this.movies,
    required this.actors,
  });

  final List<Book> books;
  final List<Movie> movies;
  final List<Actor> actors;
}

/// 存储层异常（文件损坏 / schemaVersion 不符 / 非法图片路径）
class StoreException implements Exception {
  StoreException(this.message);

  final String message;

  @override
  String toString() => 'StoreException: $message';
}

/// 本地持久化存储（JSON 三集合 + images 目录）
///
/// 设计契约（P2a 与用户对齐的三个决定）：
/// 1. **逐文件探测**：`load()` 对三个集合文件分别探测，缺哪个用 seed 补哪个
///    并立即写盘——部分文件缺失（如上次写盘被杀）不会整体退回 seed；
/// 2. **写操作返回前保证落盘**：saveXxx 返回 Future，await 完成即文件已更新，
///    调用方不需要任何 flush 语义；
/// 3. **原子写**：先写 `.tmp` 再 rename——文件系统层面 rename 原子，
///    任何时刻磁盘上只有完整旧文件或完整新文件，不存在"半个 JSON"。
///
/// [dataDir] 由构造注入：生产环境传 path_provider 目录，测试传临时目录。
/// 本类不依赖 mock_data（层级倒置），seed 数据由调用方构造后传入。
class LibraryStore {
  LibraryStore(this.dataDir, {required this.seed});

  /// 数据根目录（内含三个 JSON 与 images/）
  final Directory dataDir;

  /// 首次启动（文件缺失）时的初始数据
  final LibrarySnapshot seed;

  static const int schemaVersion = 1;
  static const String _booksFile = 'books.json';
  static const String _moviesFile = 'movies.json';
  static const String _actorsFile = 'actors.json';

  /// images 子目录（上传图片复制目标，MediaRef.localFile 相对此目录）
  Directory get imagesDir => Directory(_join('images'));

  /// 加载全部数据（或首启 seed）
  ///
  /// 每个集合独立处理：文件缺失 → 用 seed 该集合初始化并写盘；
  /// 文件存在 → 读盘解析，version 不符或 JSON 损坏抛 [StoreException]。
  Future<LibrarySnapshot> load() async {
    await dataDir.create(recursive: true);
    final books = await _loadList<Book>(
      _booksFile,
      seed.books,
      (b) => b.toJson(),
      Book.fromJson,
    );
    final movies = await _loadList<Movie>(
      _moviesFile,
      seed.movies,
      (m) => m.toJson(),
      Movie.fromJson,
    );
    final actors = await _loadList<Actor>(
      _actorsFile,
      seed.actors,
      (a) => a.toJson(),
      Actor.fromJson,
    );
    return LibrarySnapshot(
      books: books,
      movies: movies,
      actors: actors,
    );
  }

  // ==================== 合并写（saveXxx → 队列 → 单次 flush） ====================
  //
  // 用户快速连续操作（连点删除、Slider 拖动实时保存）时，同一事件循环内
  // 多次 saveXxx 会合并为一次落盘（同集合 last-write-wins）。契约不变：
  // `await saveXxx()` 返回时，该次及之前所有修改均已原子落盘。

  /// 待冲刷的集合载荷（文件名 → items）
  final Map<String, List<Map<String, dynamic>>> _pendingWrites = {};

  /// 是否有待冲刷内容
  bool _dirty = false;

  /// 写链：新请求排在上一次冲刷之后，天然串行不交错
  Future<void> _writeChain = Future.value();

  /// 保存书籍集合（合并写 + 原子写；返回后该次数据已落盘）
  Future<void> saveBooks(List<Book> books) =>
      _enqueueSave(_booksFile, books.map((b) => b.toJson()).toList());

  /// 保存电影集合（合并写 + 原子写；返回后该次数据已落盘）
  Future<void> saveMovies(List<Movie> movies) =>
      _enqueueSave(_moviesFile, movies.map((m) => m.toJson()).toList());

  /// 保存演员集合（合并写 + 原子写；返回后该次数据已落盘）
  Future<void> saveActors(List<Actor> actors) =>
      _enqueueSave(_actorsFile, actors.map((a) => a.toJson()).toList());

  /// 立即冲刷未落盘的合并写（App 生命周期挂起/退出、测试断言前调用）
  ///
  /// 无待写内容时也走一次空冲刷（保证链上所有历史写都已完成）。
  Future<void> flush() {
    _dirty = true;
    final done = _writeChain.then((_) => _flushPending());
    _writeChain = done.then((_) {}, onError: (_) {});
    return done;
  }

  /// 入队一次写：记录载荷、标记 dirty，冲刷排到写链尾部
  Future<void> _enqueueSave(
    String fileName,
    List<Map<String, dynamic>> items,
  ) {
    _pendingWrites[fileName] = items; // 同集合后写覆盖前写
    _dirty = true;
    final done = _writeChain.then((_) => _flushPending());
    _writeChain = done.then((_) {}, onError: (_) {});
    return done;
  }

  /// 冲刷全部待写内容（逐个集合原子写）
  Future<void> _flushPending() async {
    if (!_dirty) return;
    _dirty = false;
    final batch =
        Map<String, List<Map<String, dynamic>>>.from(_pendingWrites);
    _pendingWrites.clear();
    for (final entry in batch.entries) {
      await _writeFile(entry.key, entry.value);
    }
  }

  // ==================== 图片目录操作 ====================

  /// 复制图片进 images/ 目录，返回 [MediaRef.localFile] 用的相对文件名。
  ///
  /// 命名 `<entryId><原扩展名>`，同 id 重传覆盖旧图（封面更新语义）。
  /// [source] 必须存在，否则抛 [StoreException]。
  Future<String> copyImage(File source, String entryId) async {
    if (!await source.exists()) {
      throw StoreException('源图片不存在：${source.path}');
    }
    final ext = _extensionOf(source.path);
    final name = '$entryId$ext';
    await imagesDir.create(recursive: true);
    final dest = File(_join('images', name));
    if (await dest.exists()) await dest.delete();
    await source.copy(dest.path);
    return name;
  }

  /// 删除 images/ 下的图片（条目删除时的孤儿回收）。
  ///
  /// 静默容忍不存在的文件（删库重建等场景无副作用）；拒绝目录穿越路径。
  Future<void> deleteImage(String localFile) async {
    _ensureSafeRelativePath(localFile);
    final f = File(_join('images', localFile));
    if (await f.exists()) await f.delete();
  }

  /// 解析 images/ 目录下的文件（展示层 `Image.file` 用）。
  ///
  /// 不做存在性校验——文件可能已被外部清理，渲染层以 errorBuilder 兜底。
  /// 非法相对路径（目录穿越）抛 [StoreException]。
  File resolveImageFile(String localFile) {
    _ensureSafeRelativePath(localFile);
    return File(_join('images', localFile));
  }

  // ==================== 内部实现 ====================

  String _join(String a, [String? b]) => b == null
      ? '${dataDir.path}${Platform.pathSeparator}$a'
      : '${dataDir.path}${Platform.pathSeparator}$a${Platform.pathSeparator}$b';

  /// 逐文件加载：缺 → seed + 写盘；存在 → 解析校验
  Future<List<T>> _loadList<T>(
    String fileName,
    List<T> seedItems,
    Map<String, dynamic> Function(T) toJson,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final file = File(_join(fileName));
    if (!await file.exists()) {
      final items = List.of(seedItems);
      await _writeFile(fileName, items.map(toJson).toList());
      return items;
    }
    return _readFile<T>(fileName, fromJson);
  }

  Future<List<T>> _readFile<T>(
    String fileName,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final content = await File(_join(fileName)).readAsString();
    dynamic root;
    try {
      root = jsonDecode(content);
    } on FormatException catch (e) {
      throw StoreException('$fileName JSON 损坏：${e.message}');
    }
    if (root is! Map<String, dynamic>) {
      throw StoreException('$fileName 格式错误：顶层必须是对象');
    }
    final version = root['schemaVersion'];
    if (version is! int || version != schemaVersion) {
      throw StoreException(
        '$fileName schemaVersion 不符：期望 $schemaVersion，实际 $version',
      );
    }
    final items = root['items'];
    if (items is! List) {
      throw StoreException('$fileName 格式错误：items 必须是数组');
    }
    return items
        .map((e) => fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 原子写：写 `.tmp` → rename 到目标
  Future<void> _writeFile(
    String fileName,
    List<Map<String, dynamic>> items,
  ) async {
    await dataDir.create(recursive: true);
    final tmp = File(_join('$fileName.tmp'));
    const encoder = JsonEncoder.withIndent('  ');
    await tmp.writeAsString(encoder.convert({
      'schemaVersion': schemaVersion,
      'items': items,
    }));
    await tmp.rename(_join(fileName));
  }

  String _extensionOf(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(dot) : '';
  }

  /// 拒绝目录穿越（`..`、路径分隔符）——localFile 是从盘上 JSON 反序列化来的
  /// 外部输入（含恢复的备份文件），不能直接拼接进路径
  void _ensureSafeRelativePath(String name) {
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains(Platform.pathSeparator) ||
        name.contains('..')) {
      throw StoreException('非法图片相对路径：$name');
    }
  }
}
