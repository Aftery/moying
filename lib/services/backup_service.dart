import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../data/library_store.dart';

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
      exportedAt:
          exported is String ? DateTime.tryParse(exported) ?? DateTime.now() : DateTime.now(),
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
    final imageNames = includeImages ? await store.listImageFiles() : const <String>[];
    final imageData = <String, Uint8List>{};
    for (final name in imageNames) {
      imageData[name] = await store.imageFileByName(name).readAsBytes();
    }

    final manifest = BackupManifest(
      schemaVersion: backupSchemaVersion,
      exportedAt: DateTime.now(),
      includeImages: includeImages,
      counts: {
        for (final name in _collectionFiles)
          name: _countItems(files[name]!),
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
      if (await f.exists()) {
        await f.copy('${preDir.path}${Platform.pathSeparator}$name');
      }
    }

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

    // 3) 图片：清空重建（备份为完整快照语义）
    final imgDir = store.imagesDir;
    if (await imgDir.exists()) {
      await imgDir.delete(recursive: true);
    }
    await imgDir.create(recursive: true);
    for (final entry in parsed.images.entries) {
      await store.imageFileByName(entry.key).writeAsBytes(entry.value);
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
      ArchiveFile? manifestFile;
      for (final f in archive.files) {
        if (f.isFile) {
          if (f.name == 'manifest.json') {
            manifestFile = f;
          } else if (f.name.startsWith('images/')) {
            images[f.name.substring('images/'.length)] =
                Uint8List.fromList(f.content as List<int>);
          } else {
            files[f.name] = Uint8List.fromList(f.content as List<int>);
          }
        }
      }
      if (manifestFile == null) {
        throw BackupException('备份包缺少 manifest.json');
      }
      return _ParsedBackup(
        manifest: _decodeManifest(utf8.decode(manifestFile.content as List<int>)),
        files: files,
        images: images,
      );
    }

    // 单 JSON（不含图）
    final Map<String, dynamic> root;
    try {
      root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
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
