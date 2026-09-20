import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'log_sink.dart';

/// 手机 / 桌面落盘后端：写入应用支持目录下的 `logs/moying.log`。
///
/// - 目录：`getApplicationSupportDirectory()/logs`（macOS 为
///   `~/Library/Application Support/<bundle>/logs`；Android 为应用私有目录）。
///   **不用**临时目录——系统可随时清理临时目录，用户报障时日志可能已经没了。
/// - 追加写：每条一行，超 [maxBytes] 时丢弃最旧 1/3 后重写（滚动，不无限增长）。
/// - **一切 io 异常都吞掉**：落盘是旁路能力，任何失败都不应影响主流程；
///   无插件环境（`flutter test`）拿不到目录时 `_file` 保持 null，退化为不落盘。
LogSink createLogSink() => FileLogSink();

class FileLogSink implements LogSink {
  /// 默认单文件大小上限（2MB ≈ 一万余条，足够覆盖报障场景）
  static const int defaultMaxBytes = 2 * 1024 * 1024;

  static const String dirName = 'logs';
  static const String fileName = 'moying.log';

  /// 单文件大小上限（可注入——测试用小阈值即可验证滚动，无需真写 2MB）
  final int maxBytes;

  File? _file;

  FileLogSink({this.maxBytes = defaultMaxBytes});

  /// 测试用：直接指定目标文件，跳过 path_provider
  FileLogSink.forFile(File file, {this.maxBytes = defaultMaxBytes})
      : _file = file;

  @override
  Future<void> init() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}$dirName');
      if (!await dir.exists()) await dir.create(recursive: true);
      _file = File('${dir.path}${Platform.pathSeparator}$fileName');
    } on Object catch (_) {
      // 无插件环境（测试 / 受限宿主）：保持 _file = null，仅内存模式
      _file = null;
    }
  }

  @override
  Future<void> append(String line) async {
    final f = _file;
    if (f == null) return;
    try {
      if (await f.exists() && await f.length() > maxBytes) {
        // 滚动：读全文 → 丢最旧 1/3 → 重写（保留近端，报障关心的是刚刚发生的事）
        final content = await f.readAsString();
        await f.writeAsString(content.substring(content.length ~/ 3));
      }
      await f.writeAsString('$line\n', mode: FileMode.append, flush: false);
    } on Object catch (_) {
      // 落盘失败不影响主流程
    }
  }

  @override
  Future<String> readAll() async {
    final f = _file;
    if (f == null) return '';
    try {
      if (!await f.exists()) return '';
      return await f.readAsString();
    } on Object catch (_) {
      return '';
    }
  }

  @override
  Future<void> clear() async {
    final f = _file;
    if (f == null) return;
    try {
      if (await f.exists()) await f.delete();
    } on Object catch (_) {
      // 忽略
    }
  }
}
