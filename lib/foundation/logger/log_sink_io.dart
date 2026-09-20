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
/// - 读写清全部串行（见 [FileLogSink._tail]）：日志是并发写入的旁路能力，
///   非串行会丢行、丢批、甚至把已清空的文件写回来。
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

  /// 写链：append / readAll / clear 依次排队，天然串行。
  ///
  /// 与 `LibraryStore._writeChain` 同一模式。**必须串行**，因为写入方是
  /// `AppLogger` 里的 `unawaited(_persist(entry))`——每条日志都并发触发一次，
  /// 而 [_appendNow] 内含「查大小 → 读全文 → 截断重写 → 追加」四步，并发时：
  ///   1. A 读到全文、B 同时追加，A 随后截断重写 → **B 那行被抹掉**；
  ///   2. 两条同时判定超限 → 各自读全文各自重写 → 后写者覆盖先写者，**丢一批**；
  ///   3. [clear] 与在飞的 append 并发 → 文件删掉后又被写回来。
  Future<void> _tail = Future.value();

  /// 同上：读也排队，避免读到「已截断但尚未补齐」的中间态
  Future<T> _enqueue<T>(Future<T> Function() task) {
    final next = _tail.then((_) => task());
    _tail = next.then((_) {}, onError: (_) {}); // 吞异常，避免一次失败断链
    return next;
  }

  @override
  Future<void> append(String line) => _enqueue(() => _appendNow(line));

  Future<void> _appendNow(String line) async {
    final f = _file;
    if (f == null) return;
    try {
      if (await f.exists() && await f.length() > maxBytes) {
        // 滚动：读全文 → 丢最旧 1/3 → 重写（保留近端，报障关心的是刚刚发生的事）
        final content = await f.readAsString();
        // 切点右移到下一行行首再截断：按 UTF-16 码元硬切会切断代理对
        // （emoji / 生僻字）与半行，重写后表现为孤立代理项与残缺记录。
        final cut = _alignToLineStart(content, content.length ~/ 3);
        await f.writeAsString(content.substring(cut), flush: true);
      }
      await f.writeAsString('$line\n', mode: FileMode.append, flush: false);
    } on Object catch (_) {
      // 落盘失败不影响主流程
    }
  }

  /// 把截断点右移到下一个换行**之后**。
  ///
  /// 找不到换行（异常文件 / 单行即超上限）时返回 0：宁可这次不清理，
  /// 也不产出一个以半条记录开头的日志文件。
  static int _alignToLineStart(String content, int at) {
    final nl = content.indexOf('\n', at);
    return nl == -1 ? 0 : nl + 1;
  }

  @override
  Future<String> readAll() => _enqueue(_readAllNow);

  Future<String> _readAllNow() async {
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
  Future<void> clear() => _enqueue(_clearNow);

  Future<void> _clearNow() async {
    final f = _file;
    if (f == null) return;
    try {
      if (await f.exists()) await f.delete();
    } on Object catch (_) {
      // 忽略
    }
  }
}
