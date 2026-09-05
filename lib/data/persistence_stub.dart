import '../providers/library_provider.dart';

/// Web / 无本地文件系统平台回退：纯内存模式（数据不落盘）。
///
/// Web 预览定位为演示，不接持久化；手机/桌面由 persistence_io.dart 接管。
Future<LibraryProvider> createAppProvider() async => LibraryProvider();
