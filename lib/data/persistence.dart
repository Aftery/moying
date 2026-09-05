import '../providers/library_provider.dart';
import 'persistence_stub.dart' if (dart.library.io) 'persistence_io.dart'
    as impl;

/// 启动接线门面：按平台选择 Provider 构造方式。
///
/// 手机/桌面（有 dart:io）→ [persistence_io] 接本地 JSON 持久化；
/// Web（无 dart:io）→ [persistence_stub] 回退纯内存模式。
Future<LibraryProvider> createAppProvider() => impl.createAppProvider();
