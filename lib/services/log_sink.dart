import 'log_sink_stub.dart' if (dart.library.io) 'log_sink_io.dart' as impl;

/// 日志落盘后端（按平台接线，见 [createLogSink]）
///
/// 手机/桌面（有 dart:io）→ [FileLogSink] 写入应用支持目录的 logs/；
/// Web（无 dart:io）→ no-op，日志只留在内存缓冲里。
///
/// 之所以抽成接口而不是让 [AppLogger] 直接 `import 'dart:io'`：
/// Web 构建下 `dart:io` 不存在，直接引用会让整个应用编译失败。
/// 与 `data/persistence.dart` 的 `_stub` / `_io` 条件导入同构。
abstract interface class LogSink {
  /// 定位落盘位置（幂等；失败时应退化为不落盘而不是抛出）
  Future<void> init();

  /// 追加一行（条内可含换行——多行堆栈由 [AppLogger] 负责转义成单次 append）
  Future<void> append(String line);

  /// 读取全部历史文本（不存在 / 失败返回空串）
  Future<String> readAll();

  /// 清空历史
  Future<void> clear();
}

/// 按平台创建落盘后端
LogSink createLogSink() => impl.createLogSink();
