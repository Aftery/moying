import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/actor.dart';
import '../models/book.dart';
import '../models/data_source.dart';
import '../models/movie.dart';
import '../models/sync_settings.dart';
import '../models/user_profile.dart';

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

  /// 单个集合 JSON 文件（books.json / movies.json / actors.json /
  /// profile.json / settings / data_sources）的**存储格式**版本（M16）。
  ///
  /// 与 BackupService.backupSchemaVersion（=2，备份包外层协议版本）是
  /// 两套互不相同的版本号，勿混用：本常量在每个集合文件写入
  /// `schemaVersion` 字段并在 [_loadList] 严格校验；备份恢复时集合文件
  /// 原样字节拷贝、不经过本校验链。
  static const int schemaVersion = 2;

  /// 仍可读取的历史版本（v1：updatedAt 引入前的集合文件）。
  ///
  /// 版本校验用「可读列表」而非严格相等：v2 新增的 updatedAt 是可选字段、
  /// fromJson 已兜底，若严格校验会把老用户的 v1 文件整文件隔离（丢数据）。
  static const List<int> _readableVersions = [1, 2];

  static const String _booksFile = 'books.json';
  static const String _moviesFile = 'movies.json';
  static const String _actorsFile = 'actors.json';
  static const String _profileFile = 'profile.json';
  static const String _settingsFile = 'settings.json';

  /// images 子目录（上传图片复制目标，MediaRef.localFile 相对此目录）
  Directory get imagesDir => Directory(_join('images'));

  // ==================== 备份辅助（BackupService 用） ====================

  /// 数据目录下的文件（集合 JSON / settings.json 等，[name] 为裸文件名）
  File fileInDataDir(String name) => File(_join(name));

  /// 列出 images/ 下的图片文件名（目录不存在返回空）
  Future<List<String>> listImageFiles() async {
    final dir = imagesDir;
    if (!await dir.exists()) return const [];
    return dir
        .list()
        .where((e) => e is File)
        .map((e) => e.uri.pathSegments.last)
        .toList();
  }

  /// images/ 下指定文件名的文件
  File imageFileByName(String name) => File(_join('images', name));

  /// 原子覆盖写数据目录下的 JSON 文件（tmp + rename，与集合写同契约）
  Future<void> writeFileAtomic(String name, List<int> bytes) async {
    await dataDir.create(recursive: true);
    final tmp = File(_join('$name.tmp'));
    await tmp.writeAsBytes(bytes);
    await tmp.rename(_join(name));
  }

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

  /// 加载用户档案（单例集合：profile.json items 恒 0/1 元素）
  ///
  /// 缺文件 → 默认档案写盘（与其他集合的 seed 语义一致）。
  Future<UserProfile> loadProfile() async {
    await dataDir.create(recursive: true);
    final items = await _loadList<UserProfile>(
      _profileFile,
      const [UserProfile()],
      (p) => p.toJson(),
      UserProfile.fromJson,
    );
    return items.isEmpty ? const UserProfile() : items.first;
  }

  /// 保存用户档案（合并写 + 原子写；返回后该次数据已落盘）
  Future<void> saveProfile(UserProfile profile) =>
      _enqueueSave(_profileFile, [profile.toJson()]);

  // ==================== 同步配置（settings.json，单对象） ====================

  /// 加载同步配置（缺文件 → 默认配置写盘；损坏 → 默认配置，不阻断启动）
  ///
  /// 与集合文件不同：settings 丢失/损坏只影响体验不丢数据，
  /// 因此**不抛异常**，回退默认值并覆写修复。
  Future<SyncSettings> loadSettings() async {
    await dataDir.create(recursive: true);
    final file = File(_join(_settingsFile));
    if (!await file.exists()) {
      const defaults = SyncSettings();
      await _writeSettings(defaults);
      return defaults;
    }
    try {
      final content = await file.readAsString();
      final root = jsonDecode(content);
      if (root is! Map<String, dynamic>) {
        throw const FormatException('顶层必须是对象');
      }
      return SyncSettings.fromJson(root);
    } on Object catch (e) {
      debugPrint('[Store] settings.json 损坏：$e');
      await _quarantine(file);
      const defaults = SyncSettings();
      await _writeSettings(defaults);
      return defaults;
    }
  }

  Future<void> _settingsTail = Future.value();

  /// 串行队列：避免固定 .tmp 文件并发 rename 冲突（H3-M4）
  Future<void> _enqueueSettings(Future<void> Function() write) {
    final previous = _settingsTail;
    final next = previous.then((_) => write());
    _settingsTail = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// 保存同步配置（串行队列 + 原子写）
  Future<void> saveSettings(SyncSettings settings) =>
      _enqueueSettings(() => _writeSettings(settings));

  // ==================== 数据源配置（data_sources.json，单对象） ====================

  static const String _dataSourcesFile = 'data_sources.json';

  /// 加载数据源配置列表（书籍 + 影视平铺，按 [DataSourceConfig.category] 区分）。
  ///
  /// 返回 null 表示**文件尚不存在**（首次启动）——调用方（DataSourceManager）
  /// 据此写入内置默认预设；损坏时同样视为未初始化（回退默认，不阻断启动）。
  Future<List<DataSourceConfig>?> loadDataSourceConfigs() async {
    await dataDir.create(recursive: true);
    final file = File(_join(_dataSourcesFile));
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      final root = jsonDecode(content);
      if (root is! Map<String, dynamic>) {
        throw const FormatException('顶层必须是对象');
      }
      final sources = root['sources'] as List? ?? const [];
      return sources
          .whereType<Map<String, dynamic>>()
          .map(DataSourceConfig.fromJson)
          .toList();
    } on Object catch (e) {
      debugPrint('[Store] data_sources.json 损坏：$e');
      await _quarantine(file);
      return null;
    }
  }

  /// 保存数据源配置（串行队列 + 原子写；敏感凭据不在配置内，存安全存储）
  Future<void> saveDataSourceConfigs(List<DataSourceConfig> configs) =>
      _enqueueSettings(() => _writeDataSourceConfigs(configs));

  Future<void> _writeDataSourceConfigs(List<DataSourceConfig> configs) async {
    await dataDir.create(recursive: true);
    final tmp = File(_join('$_dataSourcesFile.tmp'));
    const encoder = JsonEncoder.withIndent('  ');
    await tmp.writeAsString(encoder.convert({
      'schemaVersion': schemaVersion,
      'sources': configs.map((c) => c.toJson()).toList(),
    }));
    await tmp.rename(_join(_dataSourcesFile));
  }

  /// settings 原子写（单对象形态，schemaVersion 校验与集合文件共用常量）
  Future<void> _writeSettings(SyncSettings settings) async {
    await dataDir.create(recursive: true);
    final tmp = File(_join('$_settingsFile.tmp'));
    const encoder = JsonEncoder.withIndent('  ');
    await tmp.writeAsString(encoder.convert({
      'schemaVersion': schemaVersion,
      ...settings.toJson(),
    }));
    await tmp.rename(_join(_settingsFile));
  }

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
    final batch = Map<String, List<Map<String, dynamic>>>.from(_pendingWrites);
    _pendingWrites.clear();
    try {
      for (final entry in batch.entries) {
        await _writeFile(entry.key, entry.value);
      }
    } catch (_) {
      // 写入失败时保留未成功落盘的批次；新提交的同文件数据优先保留。
      for (final entry in batch.entries) {
        _pendingWrites.putIfAbsent(entry.key, () => entry.value);
      }
      _dirty = true;
      rethrow;
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
    _ensureSafeRelativePath(entryId); // ponytail: path traversal guard
    final ext = _extensionOf(source.path);
    final name = '$entryId$ext';
    await imagesDir.create(recursive: true);
    final dest = File(_join('images', name));
    // 临时文件 copy 再 rename：拷贝失败不丢旧图
    final tmp = File(_join('images', '$name.tmp'));
    await source.copy(tmp.path);
    await tmp.rename(dest.path);
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

  /// 将图片字节流保存至 images/ 目录，返回相对文件名。
  /// [prefix] 区分图片类型（如 book_cover / movie_poster），
  /// [ext] 扩展名（.jpg/.png/.webp）。文件名含微秒时间戳，天然不重名；
  /// 临时文件写完再 rename，与 [copyImage] 同样的原子写契约。
  Future<String> saveImageBytes(
    Uint8List bytes,
    String prefix,
    String ext,
  ) async {
    await imagesDir.create(recursive: true);
    final name = '${prefix}_${DateTime.now().microsecondsSinceEpoch}$ext';
    _ensureSafeRelativePath(name);
    final dest = File(_join('images', name));
    final tmp = File(_join('images', '$name.tmp'));
    await tmp.writeAsBytes(bytes);
    await tmp.rename(dest.path);
    return name;
  }

  /// 指定文件名原子写图片字节（entryId 命名覆盖语义，M9 attachImage 用）
  Future<void> putImageBytes(String name, Uint8List bytes) async {
    _ensureSafeRelativePath(name);
    final dest = File(_join('images', name));
    final tmp = File(_join('images', '$name.tmp'));
    await imagesDir.create(recursive: true);
    await tmp.writeAsBytes(bytes);
    await tmp.rename(dest.path);
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

  // L4：改用 package:path 拼接，替代手写 Platform.pathSeparator
  // （桌面端路径分隔符/规范化差异交给成熟库处理）
  String _join(String a, [String? b]) =>
      b == null ? p.join(dataDir.path, a) : p.join(dataDir.path, a, b);

  /// 将损坏文件改名隔离（保留证据），后缀加时间戳避免覆盖
  Future<void> _quarantine(File file) async {
    if (!await file.exists()) return;
    final bad = File(
      '${file.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}',
    );
    await file.rename(bad.path);
    debugPrint('[Store] 已隔离损坏文件：${file.path} → ${bad.path}');
  }

  /// 逐文件加载：缺 → seed + 写盘；存在 → 解析校验（任何异常均隔离并回落空列表，保证 App 启动）
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
    final file = File(_join(fileName));
    try {
      final content = await file.readAsString();
      final root = jsonDecode(content);
      if (root is! Map<String, dynamic>) {
        throw StoreException('$fileName 格式错误：顶层必须是对象');
      }
      final version = root['schemaVersion'];
      if (version is! int || !_readableVersions.contains(version)) {
        throw StoreException(
          '$fileName schemaVersion 不符：期望 $_readableVersions，实际 $version',
        );
      }
      final items = root['items'];
      if (items is! List) {
        throw StoreException('$fileName 格式错误：items 必须是数组');
      }
      final result = <T>[];
      for (final e in items) {
        try {
          result.add(fromJson(e as Map<String, dynamic>));
        } on Object catch (e) {
          // 逐条隔离：单条损坏不影响同文件其他正常条目
          debugPrint('[Store] $fileName 中一条记录解析失败($e)，已跳过');
        }
      }
      return result;
    } on Object catch (e) {
      // 关键防御：捕获所有异常（CastError、ArgumentError、FormatException 等）
      // 隔离损坏文件，回落空列表（上层会以空列表或默认数据启动，绝不白屏崩溃）
      await _quarantine(file);
      debugPrint('[Store] $fileName 解析失败($e)，已隔离并回退空列表');
      return <T>[];
    }
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
