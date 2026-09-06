import '../providers/library_provider.dart';
import 'persistence.dart';

/// Web / 无本地文件系统平台回退：纯内存模式（数据不落盘）。
///
/// Web 预览定位为演示，不接持久化，也不支持数据同步/备份（store=null，
/// 个人页「数据同步」入口在 Web 隐藏）；手机/桌面由 persistence_io.dart 接管。
Future<AppBootstrap> bootstrapApp() async =>
    AppBootstrap(library: LibraryProvider(), store: null);
