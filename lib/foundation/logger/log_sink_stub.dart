import 'log_sink.dart';

/// Web 版落盘后端：`dart:io` 不可用，全部 no-op（日志仅存内存缓冲）。
LogSink createLogSink() => const _NoopLogSink();

class _NoopLogSink implements LogSink {
  const _NoopLogSink();

  @override
  Future<void> init() async {}

  @override
  Future<void> append(String line) async {}

  @override
  Future<String> readAll() async => '';

  @override
  Future<void> clear() async {}
}
