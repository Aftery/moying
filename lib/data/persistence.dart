import '../providers/library_provider.dart';
import 'library_store.dart';
import 'persistence_stub.dart' if (dart.library.io) 'persistence_io.dart'
    as impl;

/// 启动装配产物：书影库 Provider + 底层存储（Web 无存储 → null）
class AppBootstrap {
  const AppBootstrap({required this.library, required this.store});

  final LibraryProvider library;

  /// 持久化存储（Web = null；SyncProvider / 备份服务按 null 降级）
  final LibraryStore? store;
}

/// 启动接线门面：按平台装配 Provider 与存储。
///
/// 手机/桌面（有 dart:io）→ [persistence_io] 接本地 JSON 持久化；
/// Web（无 dart:io）→ [persistence_stub] 回退纯内存模式。
Future<AppBootstrap> bootstrapApp() => impl.bootstrapApp();
