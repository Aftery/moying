import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/library_store.dart';
import '../models/actor.dart';
import '../models/book.dart';
import '../models/movie.dart';

/// 备份清单（恢复确认弹窗展示条目数；schemaVersion 校验入口）
class BackupManifest {
  const BackupManifest({
    required this.schemaVersion,
    required this.exportedAt,
    required this.includeImages,
    required this.counts,
    required this.imageCount,
  });

  final int schemaVersion;
  final DateTime exportedAt;
  final bool includeImages;

  /// 四集合条目数（books / movies / actors / profile）
  final Map<String, int> counts;

  /// 随包图片张数（不含图片时为 0）
  final int imageCount;

  static BackupManifest fromJson(Map<String, dynamic> json) {
    final exported = json['exportedAt'];
    return BackupManifest(
      schemaVersion: json['schemaVersion'] as int? ?? 0,
      exportedAt: exported is String
          ? DateTime.tryParse(exported) ?? DateTime.now()
          : DateTime.now(),
      includeImages: json['includeImages'] as bool? ?? false,
      counts: (json['counts'] as Map<String, dynamic>? ?? const {})
          .map((k, v) => MapEntry(k, v is int ? v : 0)),
      imageCount: json['imageCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'exportedAt': exportedAt.toIso8601String(),
        'includeImages': includeImages,
        'counts': counts,
        'imageCount': imageCount,
      };
}

/// 备份文件格式 / 结构异常
class BackupException implements Exception {
  BackupException(this.message);

  final String message;

  @override
  String toString() => 'BackupException: $message';
}

/// 备份打包 / 还原服务
///
/// 备份策略：**四集合 JSON 文件原样字节 + images/ 目录**——不重新序列化
/// 模型，保证 100% 保真（原生文件自带 schemaVersion 校验链）。
///
/// - 不含图：单 JSON 文件（`{manifest, data:{books,movies,actors,profile}}`）
/// - 含图：ZIP（`manifest.json` + 四集合 JSON + `images/<name>`）
/// - 文件名：`moying-yyyyMMdd-HHmmss`（`-` 分隔，冒号跨平台非法）
///
/// 还原流程：解析 → 校验 → 现状快照到 `backup-pre-restore/` → 覆盖写。
class BackupService {
  BackupService({required this.store});

  final LibraryStore store;

  /// 备份包 ZIP/JSON **外层协议**版本（M16）。
  ///
  /// 与 [LibraryStore.schemaVersion]（=1）是两套互不相同的版本号，勿混用：
  /// - 本常量：manifest.json 里的备份协议版本，校验逻辑在 [_ensureCompatible]
  ///   （双向严格相等：过高拒绝 = 需升级 App；过低拒绝 = 需迁移器）；
  /// - LibraryStore.schemaVersion：单个集合 JSON 文件（books.json 等）的
  ///   存储格式版本，随集合文件原样字节进备份、恢复时不重新校验。
  /// 升级任一侧时须同步检查另一方是否受影响。
  static const int backupSchemaVersion = 2;
  static const List<String> _collectionFiles = [
    'books.json',
    'movies.json',
    'actors.json',
    'profile.json',
  ];

  /// 数据源配置（可选第 5 文件：未进过管理页时不存在；敏感凭据不在内，
  /// 存系统安全存储。旧版本应用恢复本备份会静默忽略该文件，向后兼容）
  static const String _dataSourceFile = 'data_sources.json';
  static const String _preRestoreDir = 'backup-pre-restore';

  /// M9：ZIP 解压后累计内容字节上限（200 MB），含四集合 JSON + images。
  /// 恶意 / 异常超大备份在解压读取阶段即中断，避免 OOM。
  static const int _maxUnpackedBytes = 200 * 1024 * 1024;

  /// 打包备份字节（调用前请 `store.flush()` 保证磁盘为最新）
  Future<Uint8List> buildBackup({required bool includeImages}) async {
    final files = <String, Uint8List>{};
    for (final name in _collectionFiles) {
      final f = store.fileInDataDir(name);
      if (!await f.exists()) {
        throw BackupException('本地数据文件缺失：$name');
      }
      files[name] = await f.readAsBytes();
    }
    Uint8List? dataSourceBytes;
    final dsFile = store.fileInDataDir(_dataSourceFile);
    if (await dsFile.exists()) {
      dataSourceBytes = await dsFile.readAsBytes();
    }
    final imageNames =
        includeImages ? await store.listImageFiles() : const <String>[];
    final imageData = <String, Uint8List>{};
    for (final name in imageNames) {
      try {
        final f = store.imageFileByName(name);
        if (await f.exists()) {
          imageData[name] = await f.readAsBytes();
        }
      } catch (e) {
        // ponytail: 单张图片读取失败容错，跳过不中断全量备份
        debugPrint('[BackupService] 读取图片失败跳过: $name, error: $e');
      }
    }

    final manifest = BackupManifest(
      schemaVersion: backupSchemaVersion,
      exportedAt: DateTime.now(),
      includeImages: includeImages,
      counts: {
        for (final name in _collectionFiles) name: _countItems(files[name]!),
        if (dataSourceBytes != null)
          _dataSourceFile: _countSourceItems(dataSourceBytes),
      },
      imageCount: imageData.length,
    );

    if (!includeImages) {
      final merged = jsonEncode({
        'manifest': manifest.toJson(),
        'data': {
          for (final name in _collectionFiles)
            name: jsonDecode(utf8.decode(files[name]!)),
          if (dataSourceBytes != null)
            _dataSourceFile: jsonDecode(utf8.decode(dataSourceBytes)),
        },
      });
      return Uint8List.fromList(utf8.encode(merged));
    }

    final archive = Archive()
      ..addFile(_textFile('manifest.json', jsonEncode(manifest.toJson())));
    for (final entry in files.entries) {
      archive.addFile(_bytesFile(entry.key, entry.value));
    }
    if (dataSourceBytes != null) {
      archive.addFile(_bytesFile(_dataSourceFile, dataSourceBytes));
    }
    for (final entry in imageData.entries) {
      archive.addFile(_bytesFile('images/${entry.key}', entry.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  /// 读取备份清单（不落盘；恢复确认弹窗展示条目数用）
  Future<BackupManifest> peekBackup(Uint8List bytes) async {
    final parsed = await _parse(bytes);
    return parsed.manifest;
  }

  /// 从备份字节解析出三集合快照（LWW 合并用，**不落盘**）
  ///
  /// 与 [restoreBackup] 的区别：只读取模型，不触碰本地任何文件。
  /// 集合 JSON 沿用 store 的 schemaVersion 校验语义（v1/v2 均可读，
  /// 单条损坏跳过——与 [LibraryStore._readFile] 行为一致）。
  Future<LibrarySnapshot> extractSnapshot(Uint8List bytes) async {
    final parsed = await _parse(bytes);
    _ensureCompatible(parsed.manifest);
    return LibrarySnapshot(
      books: _decodeCollection(
        parsed.files['books.json'],
        Book.fromJson,
        'books.json',
      ),
      movies: _decodeCollection(
        parsed.files['movies.json'],
        Movie.fromJson,
        'movies.json',
      ),
      actors: _decodeCollection(
        parsed.files['actors.json'],
        Actor.fromJson,
        'actors.json',
      ),
    );
  }

  /// 解析单个集合 JSON 字节（顶层 schemaVersion 校验 + 逐条容错）
  List<T> _decodeCollection<T>(
    Uint8List? fileBytes,
    T Function(Map<String, dynamic>) fromJson,
    String fileName,
  ) {
    if (fileBytes == null) {
      throw BackupException('备份缺少必需文件：$fileName');
    }
    final root = jsonDecode(utf8.decode(fileBytes)) as Map<String, dynamic>;
    final version = root['schemaVersion'];
    if (version is! int || !const [1, 2].contains(version)) {
      throw BackupException('$fileName schemaVersion 不符：$version');
    }
    final items = root['items'];
    if (items is! List) {
      throw BackupException('$fileName 格式错误：items 必须是数组');
    }
    final result = <T>[];
    for (final e in items) {
      try {
        result.add(fromJson(e as Map<String, dynamic>));
      } on Object catch (_) {
        // 单条损坏跳过（与 LibraryStore 逐条隔离策略一致）
      }
    }
    return result;
  }

  /// 还原备份：覆盖四集合 JSON 与 images/（调用方负责通知 Provider reload）
  ///
  /// 覆盖前把当前文件快照到 `backup-pre-restore/`，失败可手动找回。
  Future<void> restoreBackup(Uint8List bytes) async {
    final parsed = await _parse(bytes);
    _ensureCompatible(parsed.manifest);

    // 1) 现状快照（可容忍部分文件缺失——首次启动后必然齐全，防御外部删改）
    final preDir = Directory(
      '${store.dataDir.path}${Platform.pathSeparator}$_preRestoreDir',
    );
    await preDir.create(recursive: true);
    for (final name in [..._collectionFiles, _dataSourceFile]) {
      final f = store.fileInDataDir(name);
      final snapshot = File(
        '${preDir.path}${Platform.pathSeparator}$name',
      );
      if (await f.exists()) {
        await f.copy(snapshot.path);
      } else if (await snapshot.exists()) {
        await snapshot.delete();
      }
    }
    // images 也纳入快照（恢复中途失败时的最后一道防线）
    final preImgDir =
        Directory('${preDir.path}${Platform.pathSeparator}images');
    try {
      if (await store.imagesDir.exists()) {
        if (await preImgDir.exists()) {
          await preImgDir.delete(recursive: true);
        }
        await preImgDir.create(recursive: true);
        await _copyDir(store.imagesDir, preImgDir);
      } else if (await preImgDir.exists()) {
        await preImgDir.delete(recursive: true);
      }
    } catch (e) {
      // 无法保留回滚快照时拒绝继续，避免恢复失败后无法找回现状。
      throw BackupException('恢复前图片快照失败：$e');
    }

    // 先完整校验集合，避免写入部分文件后才发现备份损坏。
    _decodeCollection(parsed.files['books.json'], Book.fromJson, 'books.json');
    _decodeCollection(
        parsed.files['movies.json'], Movie.fromJson, 'movies.json');
    _decodeCollection(
        parsed.files['actors.json'], Actor.fromJson, 'actors.json');

    try {
      // 2) 覆盖四集合 JSON（原子写）
      for (final name in _collectionFiles) {
        final data = parsed.files[name];
        if (data == null) {
          throw BackupException('备份缺少必需文件：$name');
        }
        await store.writeFileAtomic(name, data);
      }

      // 2.5) 数据源配置（可选：备份里没有则保留本地现状）
      final dsData = parsed.files[_dataSourceFile];
      if (dsData != null) {
        await store.writeFileAtomic(_dataSourceFile, dsData);
      }

      // 不含图片的备份只恢复数据，必须保留设备上的现有图片。
      if (!parsed.manifest.includeImages) return;

      // 3) 图片：原子替换（先写临时目录，全部成功后再重命名，避免中途失败丢失现有图片）
      final imgDir = store.imagesDir;
      final tmpDir = Directory(
          '${imgDir.path}-new-${DateTime.now().millisecondsSinceEpoch}');
      final oldDir = Directory(
          '${imgDir.path}-old-${DateTime.now().millisecondsSinceEpoch}');
      await tmpDir.create(recursive: true);

      try {
        // 写入全部新图片到临时目录
        for (final entry in parsed.images.entries) {
          final targetFile =
              File('${tmpDir.path}${Platform.pathSeparator}${entry.key}');
          await targetFile.writeAsBytes(entry.value);
        }

        // 全部新图写成功，执行原子替换
        if (await imgDir.exists()) {
          await imgDir.rename(oldDir.path); // 旧图改名保命
        }
        await tmpDir.rename(imgDir.path); // 新图上位

        // 替换成功，清理旧图
        if (await oldDir.exists()) {
          await oldDir.delete(recursive: true);
        }
      } catch (e) {
        // 恢复中途失败：清理临时目录，如果旧图被挪走了则还原旧图
        if (await tmpDir.exists()) {
          await tmpDir.delete(recursive: true);
        }
        if (await oldDir.exists()) {
          if (await imgDir.exists()) {
            await imgDir.delete(recursive: true);
          }
          await oldDir.rename(imgDir.path);
        }
        rethrow;
      }
    } catch (e) {
      // 集合写入或图片替换失败时，回滚已写入的集合，避免留下混合版本。
      await _rollbackDataFiles(preDir);
      rethrow;
    }
  }

  /// 生成备份文件名（不含扩展名；调用方按格式补 .json/.zip）
  String backupFileStamp(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'moying-'
        '${time.year}${two(time.month)}${two(time.day)}-'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }

  // ==================== 内部实现 ====================

  Future<_ParsedBackup> _parse(Uint8List bytes) async {
    try {
      return await _parseUnchecked(bytes);
    } on BackupException {
      rethrow;
    } on Object catch (e) {
      // 边界兜底：f.content as List<int>、jsonDecode(...) as Map、
      // 集合条目 e as Map 等可能抛 TypeError/ArgumentError，未归一化前
      // 会直接抛出非 BackupException，导致 uploadNow 的 catch(BackupException)
      // 漏网、中断上传链路。统一包装成 BackupException，保留原始异常供日志。
      debugPrint('[BackupService] 解析备份失败：$e');
      throw BackupException('备份格式异常，无法读取');
    }
  }

  Future<_ParsedBackup> _parseUnchecked(Uint8List bytes) async {
    // ZIP 魔数 PK\x03\x04
    if (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      final Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } on ArchiveException {
        throw BackupException('备份包损坏，无法解压');
      }
      final files = <String, Uint8List>{};
      final images = <String, Uint8List>{};
      Uint8List? manifestBytes;
      var unpackedBytes = 0;
      for (final f in archive.files) {
        if (f.isFile) {
          final content = Uint8List.fromList(f.content as List<int>);
          // M9：解压累计超 200 MB 中止
          unpackedBytes += content.length;
          if (unpackedBytes > _maxUnpackedBytes) {
            throw BackupException('备份包解压后超过 200 MB，无法解析');
          }
          if (f.name == 'manifest.json') {
            manifestBytes = content;
          } else if (f.name.startsWith('images/')) {
            final imageName = f.name.substring('images/'.length);
            _ensureSafeArchiveImageName(imageName);
            if (images.containsKey(imageName)) {
              throw BackupException('备份包包含重复图片：$imageName');
            }
            images[imageName] = content;
          } else {
            files[f.name] = content;
          }
        }
      }
      if (manifestBytes == null) {
        throw BackupException('备份包缺少 manifest.json');
      }
      return _ParsedBackup(
        manifest: _decodeManifest(utf8.decode(manifestBytes)),
        files: files,
        images: images,
      );
    }

    // 单 JSON（不含图）
    final Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw BackupException('备份文件不是有效的墨影备份');
      }
      root = decoded;
    } on FormatException {
      throw BackupException('备份文件不是有效的墨影备份');
    }
    final data = root['data'];
    if (data is! Map<String, dynamic>) {
      throw BackupException('备份文件缺少 data 区');
    }
    return _ParsedBackup(
      manifest: _decodeManifest(jsonEncode(root['manifest'])),
      files: {
        for (final entry in data.entries)
          entry.key: Uint8List.fromList(utf8.encode(jsonEncode(entry.value))),
      },
      images: const {},
    );
  }

  void _ensureSafeArchiveImageName(String name) {
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains('\\') ||
        name.contains('..') ||
        name.contains(':')) {
      throw BackupException('备份包包含非法图片路径：$name');
    }
  }

  BackupManifest _decodeManifest(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        throw BackupException('manifest.json 格式错误');
      }
      return BackupManifest.fromJson(json);
    } on FormatException {
      throw BackupException('manifest.json 不是有效 JSON');
    }
  }

  void _ensureCompatible(BackupManifest manifest) {
    if (manifest.schemaVersion > backupSchemaVersion) {
      throw BackupException(
        '备份版本过高（v${manifest.schemaVersion}），请升级应用后再恢复',
      );
    }
    if (manifest.schemaVersion < backupSchemaVersion) {
      throw BackupException(
        '备份版本过低（v${manifest.schemaVersion}），暂不支持恢复',
      );
    }
  }

  /// 从恢复前快照回滚已经写入的集合文件。
  Future<void> _rollbackDataFiles(Directory preDir) async {
    for (final name in [..._collectionFiles, _dataSourceFile]) {
      final backup = File(
        '${preDir.path}${Platform.pathSeparator}$name',
      );
      final target = store.fileInDataDir(name);
      try {
        if (await backup.exists()) {
          await backup.copy(target.path);
        } else if (await target.exists()) {
          await target.delete();
        }
      } catch (e) {
        // 保留原始恢复异常，同时记录回滚失败，便于人工从快照找回。
        debugPrint('[BackupService] 回滚 $name 失败：$e');
      }
    }
  }

  /// 递归复制目录（排除以 . 开头的隐藏文件/子目录）
  /// M6：异步流避免 UI 阻塞；path 包统一拼接
  Future<void> _copyDir(Directory src, Directory dst) async {
    if (!await dst.exists()) await dst.create(recursive: true);
    await for (final entry in src.list()) {
      final name = p.basename(entry.path);
      if (name.startsWith('.')) continue;
      if (entry is Directory) {
        await _copyDir(entry, Directory(p.join(dst.path, name)));
      } else if (entry is File) {
        await entry.copy(p.join(dst.path, name));
      }
    }
  }

  /// 统计集合 JSON 的 items 条数（容错：损坏按 0）
  int _countItems(Uint8List collectionJson) {
    try {
      final root = jsonDecode(utf8.decode(collectionJson));
      final items = root is Map<String, dynamic> ? root['items'] : null;
      return items is List ? items.length : 0;
    } on FormatException {
      return 0;
    }
  }

  /// 统计 data_sources.json 的 sources 条数（容错：损坏按 0）
  int _countSourceItems(Uint8List bytes) {
    try {
      final root = jsonDecode(utf8.decode(bytes));
      final items = root is Map<String, dynamic> ? root['sources'] : null;
      return items is List ? items.length : 0;
    } on FormatException {
      return 0;
    }
  }

  ArchiveFile _textFile(String name, String content) =>
      _bytesFile(name, Uint8List.fromList(utf8.encode(content)));

  ArchiveFile _bytesFile(String name, Uint8List bytes) {
    final f = ArchiveFile(name, bytes.length, bytes);
    return f;
  }
}

class _ParsedBackup {
  const _ParsedBackup({
    required this.manifest,
    required this.files,
    required this.images,
  });

  final BackupManifest manifest;
  final Map<String, Uint8List> files;
  final Map<String, Uint8List> images;
}
