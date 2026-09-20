import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moying/services/app_logger.dart';
import 'package:moying/services/log_sink.dart';
import 'package:moying/services/log_sink_io.dart';

/// 内存 sink：只收行、不落盘，便于验证缓冲 / 导出 / 清空
class _MemorySink implements LogSink {
  final List<String> lines = <String>[];

  @override
  Future<void> init() async {}

  @override
  Future<void> append(String line) async => lines.add(line);

  @override
  Future<String> readAll() async => lines.join('\n');

  @override
  Future<void> clear() async => lines.clear();
}

/// 让 [_record] 里 `unawaited(_persist(...))` 的微任务跑完再断言
Future<void> _pump() => Future<void>.delayed(Duration.zero);

void main() {
  late _MemorySink sink;

  setUp(() async {
    sink = _MemorySink();
    await AppLogger.instance.debugInitWith(sink);
  });

  tearDown(() {
    AppLogger.instance.debugReset();
  });

  group('AppLogger · 记录与统计', () {
    test('按级别记录，entries 保持时间正序', () async {
      AppLogger.instance.info('t', 'hello');
      AppLogger.instance.warn('t', 'careful');
      AppLogger.instance.error('t', 'boom');
      AppLogger.instance.fatal('t', 'dead');
      await _pump();

      final entries = AppLogger.instance.entries;
      expect(entries.length, 4);
      expect(entries.first.level, LogLevel.info);
      expect(entries.last.level, LogLevel.fatal);
      expect(AppLogger.instance.totalCount, 4);
      expect(AppLogger.instance.problemCount, 2, reason: 'error + fatal');
      expect(AppLogger.instance.warningCount, 1);
    });

    test('error 会把异常与堆栈拼进消息体', () async {
      AppLogger.instance.error(
        't',
        '请求失败',
        error: 'E1',
        stack: StackTrace.fromString('S1'),
      );
      await _pump();

      final msg = AppLogger.instance.entries.single.message;
      expect(msg, contains('请求失败'));
      expect(msg, contains('异常: E1'));
      expect(msg, contains('堆栈: S1'));
    });

    test('内存缓冲不超过上限，且保留最新条目', () async {
      for (var i = 0; i < AppLogger.maxBufferEntries + 20; i++) {
        AppLogger.instance.info('t', 'n$i');
      }
      await _pump();

      expect(AppLogger.instance.totalCount, AppLogger.maxBufferEntries);
      expect(
        AppLogger.instance.entries.last.message,
        'n${AppLogger.maxBufferEntries + 19}',
      );
      expect(AppLogger.instance.entries.first.message, 'n20');
    });

    test('meta 与消息一并写入落盘行', () async {
      AppLogger.instance.error(
        'http',
        '请求超时',
        meta: {'host': 'example.com', 'type': 'TimeoutException'},
      );
      await _pump();

      expect(sink.lines.single, contains('[ERROR][http] 请求超时'));
      expect(sink.lines.single, contains('host=example.com'));
      expect(sink.lines.single, contains('type=TimeoutException'));
    });
  });

  group('AppLogger · 导出与清空', () {
    test('exportText 含抬头、环境、统计与条目', () async {
      AppLogger.instance.error('http', '请求超时', meta: {'host': 'a.com'});
      await _pump();

      final text = AppLogger.instance.exportText();
      expect(text, contains('墨影 · 错误日志'));
      expect(text, contains('运行环境:'));
      expect(text, contains('条目统计:'));
      expect(text, contains('[ERROR][http] 请求超时'));
      expect(text, contains('host=a.com'));
    });

    test('无日志时 exportText 给出「暂无日志」', () {
      expect(AppLogger.instance.exportText(), contains('（暂无日志）'));
    });

    test('clear 同时清空内存缓冲与落盘', () async {
      AppLogger.instance.info('t', 'x');
      await _pump();
      expect(sink.lines, isNotEmpty);

      await AppLogger.instance.clear();
      expect(AppLogger.instance.totalCount, 0);
      expect(sink.lines, isEmpty);
    });
  });

  group('LogEntry · 行格式往返', () {
    test('含换行的消息落盘为单行，解析后可还原', () {
      final entry = LogEntry(
        time: DateTime(2026, 9, 12, 10, 30, 5, 123),
        level: LogLevel.error,
        tag: 'http',
        message: '失败\n  异常: X',
        meta: const {'host': 'a.com', 'type': 'TimeoutException'},
      );

      final line = entry.toLine();
      expect(line.contains('\n'), isFalse, reason: '落盘必须一条一行');

      final parsed = LogEntry.parse(line);
      expect(parsed, isNotNull);
      expect(parsed!.time, entry.time);
      expect(parsed.level, LogLevel.error);
      expect(parsed.tag, 'http');
      expect(parsed.message, '失败\n  异常: X');
      expect(parsed.meta['host'], 'a.com');
      expect(parsed.meta['type'], 'TimeoutException');
    });

    test('格式不符的行解析为 null（历史文件容错）', () {
      expect(LogEntry.parse('随便一行垃圾'), isNull);
      expect(LogEntry.parse('[bad-level][X][t] m'), isNull);
    });
  });

  group('AppLogger · 历史加载', () {
    test('init 会把落盘历史读回内存缓冲', () async {
      final history = _MemorySink()
        ..lines.add(
          LogEntry(
            time: DateTime(2026, 1, 1, 8, 0),
            level: LogLevel.warning,
            tag: 'old',
            message: '上次运行的错误',
          ).toLine(),
        );

      await AppLogger.instance.debugInitWith(history);

      expect(AppLogger.instance.totalCount, 1);
      expect(AppLogger.instance.entries.single.message, '上次运行的错误');
      expect(AppLogger.instance.entries.single.level, LogLevel.warning);
    });
  });

  group('FileLogSink · 真实落盘', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('moying-log-test');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('追加写入后可读回，clear 后文件被删除', () async {
      final file = File('${dir.path}${Platform.pathSeparator}moying.log');
      final sink = FileLogSink.forFile(file);

      await sink.append('line-1');
      await sink.append('line-2');
      expect(await sink.readAll(), 'line-1\nline-2\n');

      await sink.clear();
      expect(await file.exists(), isFalse);
      expect(await sink.readAll(), '');
    });

    test('超过上限时滚动：丢弃最旧部分、保留最新', () async {
      final file = File('${dir.path}${Platform.pathSeparator}moying.log');
      // 小阈值即可验证滚动逻辑，无需真写 2MB
      final sink = FileLogSink.forFile(file, maxBytes: 100);

      await sink.append('a' * 40);
      await sink.append('b' * 40);
      await sink.append('c' * 40); // 累计 123 字节，已越过 100 阈值
      // 滚动检查发生在「写入前」：此时文件 123 > 100，先丢弃最旧 1/3 再追加
      await sink.append('d' * 40);

      final content = await sink.readAll();
      expect(content, endsWith('${'d' * 40}\n'), reason: '最新一条必须保留');
      expect(content.contains('a' * 40), isFalse, reason: '最旧部分应被丢弃');
      expect(
        content.length,
        lessThanOrEqualTo(100 + 41),
        reason: '滚动后文件被限制在「上限 + 单行」量级，不再无限增长',
      );
    });
  });
}
