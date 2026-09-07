/// 记录级 LWW（Last-Write-Wins）合并引擎
///
/// WebDAV 双端同步的冲突解决核心：按 **id** 做并集，同 id 冲突时
/// **updatedAt 新者胜**。纯函数、无 IO，可直接单测。
///
/// 语义约定：
/// - 仅一端存在的记录 → 原样保留（新端新增 / 另一端未删）；
/// - 两端都存在 → updatedAt 较新者胜，相等时保留本地（确定性，避免抖动）；
/// - **不做删除传播**（无 tombstone）：A 端删除的记录会被 B 端同步回来，
///   这是记录级 union 的已知取舍，兜底依赖同步前的本地快照。
/// - 图片引用随记录整体取胜者：MediaRef.localFile 指向 images/ 下的
///   文件名，双端图片管理各自独立，同名文件内容可能不同——取胜者记录
///   引用的文件以「本端磁盘上是否存在」为准，缺失时 UI 走占位兜底，
///   不做跨端图片拉取（备份含图模式会把图片文件一并覆盖，见备份流程）。
library;

import '../models/actor.dart';
import '../models/book.dart';
import '../models/movie.dart';
import '../data/library_store.dart';

/// 一次合并的统计结果（供 UI 展示「本次同步：N 条来自云端 / M 条本地保留」）
class MergeResult {
  const MergeResult({
    required this.snapshot,
    required this.fromRemote,
    required this.localKept,
    required this.localOnly,
  });

  /// 合并后的三集合快照
  final LibrarySnapshot snapshot;

  /// 冲突中来自云端的记录数（remote.updatedAt > local.updatedAt）
  final int fromRemote;

  /// 冲突中保留本地的记录数（含相等的情况）
  final int localKept;

  /// 从云端并入的记录数（本地缺失；「本地有云端无」的记录天然保留，不计数）
  final int localOnly;

  /// 是否有实质差异（决定是否需要写盘 / 上传）
  bool get hasChanges => fromRemote > 0 || localOnly > 0;
}

/// 三集合记录级 LWW 合并（本地 × 云端）
MergeResult mergeSnapshot({
  required LibrarySnapshot local,
  required LibrarySnapshot remote,
}) {
  var fromRemote = 0;
  var localKept = 0;
  var localOnly = 0;

  final books = _mergeById<Book>(
    local.books,
    remote.books,
    () => fromRemote++,
    () => localKept++,
    () => localOnly++,
  );
  final movies = _mergeById<Movie>(
    local.movies,
    remote.movies,
    () => fromRemote++,
    () => localKept++,
    () => localOnly++,
  );
  final actors = _mergeById<Actor>(
    local.actors,
    remote.actors,
    () => fromRemote++,
    () => localKept++,
    () => localOnly++,
  );

  return MergeResult(
    snapshot: LibrarySnapshot(
      books: books,
      movies: movies,
      actors: actors,
    ),
    fromRemote: fromRemote,
    localKept: localKept,
    localOnly: localOnly,
  );
}

/// 单集合按 id 合并：union + updatedAt 新者胜（相等留本地）
List<T> _mergeById<T extends Object>(
  List<T> localItems,
  List<T> remoteItems,
  void Function() countRemote,
  void Function() countLocal,
  void Function() countOnly,
) {
  final localById = {for (final item in localItems) _idOf(item): item};
  final merged = Map<String, T>.of(localById);

  for (final item in remoteItems) {
    final id = _idOf(item);
    final existing = merged[id];
    if (existing == null) {
      merged[id] = item; // 仅云端有（本地缺失 / 已被删除的复活）
      countOnly();
    } else if (_updatedAtOf(item).isAfter(_updatedAtOf(existing))) {
      merged[id] = item; // 云端较新 → 云端胜
      countRemote();
    } else {
      countLocal(); // 本地较新或相等 → 保留本地
    }
  }
  return merged.values.toList();
}

// 反射替代方案的轻量实现：显式类型分派取 id / updatedAt
// （比 dynamic 调用安全，比引入公共基类侵入小）

String _idOf(Object item) => switch (item) {
      Book b => b.id,
      Movie m => m.id,
      Actor a => a.id,
      _ => throw ArgumentError('不支持合并的类型: ${item.runtimeType}'),
    };

DateTime _updatedAtOf(Object item) => switch (item) {
      Book b => b.updatedAt,
      // Movie.updatedAt 可空（未修改过 / 旧数据），null 视为最旧：
      // isAfter 比较中双 null 相等 → 保留本地，确定性不抖动
      Movie m => m.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      Actor a => a.updatedAt,
      _ => throw ArgumentError('不支持合并的类型: ${item.runtimeType}'),
    };
