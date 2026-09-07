/// 同步前本地快照兜底
///
/// 记录级 LWW 合并虽然避免了整端覆盖，但合并逻辑本身若有缺陷
/// （或 tombstone 缺失导致删除被复活），用户需要一条回退路径。
/// 本服务在每次 merge / 恢复前把当前本地数据打包存入
/// `data/snapshots/`，滚动保留最近 [maxSnapshots] 份。
///
/// 复用 [BackupService.buildBackup] 打包（JSON 单文件，不含图片——
/// 快照针对集合数据，图片本身不受 merge 影响、体积也大）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/library_store.dart';
import 'backup_service.dart';

class SnapshotService {
  SnapshotService({required this.store});

  final LibraryStore store;

  /// 快照目录（data/snapshots/，与集合文件同层隔离）
  static const String _dirName = 'snapshots';

  /// 滚动保留份数
  static const int maxSnapshots = 10;

  Directory get _snapshotsDir =>
      Directory('${store.dataDir.path}${Platform.pathSeparator}$_dirName');

  /// 保存一份当前本地数据的快照
  ///
  /// 打包或写盘失败只记日志不抛出——快照是兜底手段，
  /// 不能因为它阻断正常同步流程。
  Future<void> capture({String tag = 'merge'}) async {
    try {
      final bytes = await BackupService(store: store)
          .buildBackup(includeImages: false);
      final stamp = BackupService(store: store)
          .backupFileStamp(DateTime.now())
          .replaceAll(':', '-');
      await _snapshotsDir.create(recursive: true);
      final file = File(
          '${_snapshotsDir.path}${Platform.pathSeparator}$tag-$stamp.json');
      await file.writeAsBytes(bytes, flush: true);
      await _prune();
    } on Object catch (e) {
      debugPrint('[Snapshot] 快照保存失败（不影响同步流程）: $e');
    }
  }

  /// 列出快照文件（旧→新）
  Future<List<File>> list() async {
    if (!await _snapshotsDir.exists()) return const [];
    final files = await _snapshotsDir
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  /// 滚动清理：超出 [maxSnapshots] 的最旧快照删除
  Future<void> _prune() async {
    final files = await list();
    final overflow = files.length - maxSnapshots;
    for (var i = 0; i < overflow; i++) {
      try {
        await files[i].delete();
      } on FileSystemException catch (e) {
        debugPrint('[Snapshot] 清理旧快照失败: $e');
      }
    }
  }
}
