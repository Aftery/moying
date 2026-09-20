import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'log_sink.dart';

/// 日志级别
enum LogLevel {
  info('INFO'),
  warning('WARN'),
  error('ERROR'),
  fatal('FATAL');

  const LogLevel(this.label);

  /// 落盘 / 展示用的定宽标签
  final String label;

  /// 是否属于「问题」（错误 / 崩溃）——用于统计与高亮
  bool get isProblem => this == LogLevel.error || this == LogLevel.fatal;

  static LogLevel? fromLabel(String s) {
    for (final l in LogLevel.values) {
      if (l.label == s) return l;
    }
    return null;
  }
}

/// 单条日志（时间 + 级别 + 标签 + 消息 + 结构化附加信息）
@immutable
class LogEntry {
  const LogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    this.meta = const <String, String>{},
  });

  final DateTime time;
  final LogLevel level;

  /// 来源标签（如 http / data-source / flutter）
  final String tag;

  /// 消息（可能含多行堆栈，落盘时转义成单行）
  final String message;

  /// 结构化附加信息（键值，如 url / type / source）
  final Map<String, String> meta;

  /// 落盘 / 导出用的一行文本
  String toLine() {
    final b = StringBuffer('[')
      ..write(formatLogTime(time))
      ..write('][')
      ..write(level.label)
      ..write('][')
      ..write(_escape(tag))
      ..write('] ')
      ..write(_escape(message));
    if (meta.isNotEmpty) {
      b.write(' {');
      b.write(meta.entries
          .map((e) => '${_escape(e.key)}=${_escape(e.value)}')
          .join(', '));
      b.write('}');
    }
    return b.toString();
  }

  /// 解析一行；格式不符返回 null（历史文件可能被外部改动，需容错）
  static LogEntry? parse(String line) {
    final m = _linePattern.firstMatch(line);
    if (m == null) return null;
    final time = DateTime.tryParse(m.group(1)!.replaceFirst(' ', 'T'));
    final level = LogLevel.fromLabel(m.group(2)!);
    if (time == null || level == null) return null;
    final tag = _unescape(m.group(3)!);
    var rest = m.group(4) ?? '';
    final meta = <String, String>{};
    if (rest.endsWith('}')) {
      final i = rest.lastIndexOf(' {');
      if (i >= 0) {
        final inside = rest.substring(i + 2, rest.length - 1);
        rest = rest.substring(0, i);
        for (final pair in inside.split(', ')) {
          final eq = pair.indexOf('=');
          if (eq > 0) {
            meta[_unescape(pair.substring(0, eq))] =
                _unescape(pair.substring(eq + 1));
          }
        }
      }
    }
    return LogEntry(
      time: time,
      level: level,
      tag: tag,
      message: _unescape(rest),
      meta: meta,
    );
  }
}

/// `[时间][级别][标签] 消息 {k=v}`
final RegExp _linePattern =
    RegExp(r'^\[([^\]]+)\]\[([^\]]+)\]\[([^\]]+)\]\s?([\s\S]*)$');

/// 时间格式化：`2026-09-12 11:36:56.123`
String formatLogTime(DateTime t) {
  String p2(int v) => v.toString().padLeft(2, '0');
  String p3(int v) => v.toString().padLeft(3, '0');
  return '${t.year}-${p2(t.month)}-${p2(t.day)} '
      '${p2(t.hour)}:${p2(t.minute)}:${p2(t.second)}.${p3(t.millisecond)}';
}

/// 转义：反斜杠 → `\\`，换行 → `\n`（保证「一条一行」，便于滚动与解析）
String _escape(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n')
    .replaceAll('\n', '\\n');

/// [_escape] 的逆操作（逐字符扫描，避免二次转义歧义）
String _unescape(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == '\\' && i + 1 < s.length) {
      final n = s[i + 1];
      if (n == 'n') {
        b.write('\n');
        i++;
        continue;
      }
      if (n == '\\') {
        b.write('\\');
        i++;
        continue;
      }
    }
    b.write(ch);
  }
  return b.toString();
}

/// 应用日志中枢（全局单例）
///
/// **定位**：把「应用崩溃 / 未捕获异常 / 数据源请求失败」这类用户看得见或看不见的
/// 问题记下来，供用户在「个人 → 错误日志」里查看、导出并反馈给开发者。它不是
/// 行为埋点（不记录页面浏览、按钮点击），也不上传任何数据——**只在本地**。
///
/// **隐私约束**：只写错误信息与排查所需的元数据（请求域名、异常类型、数据源 id），
/// **不写**书库内容、搜索关键词、账号凭据 / 密码。
///
/// **两层存储**：
/// - 内存环形缓冲（[maxBufferEntries]，供 UI 即时展示与导出）；
/// - 落盘（[LogSink]，默认按平台选文件 / no-op），启动时把历史读回缓冲，
///   这样「上次启动就崩溃」这类问题在下一次启动后仍能看到。
///
/// **可订阅**：继承 [ChangeNotifier]，UI 可用 [context.watch] 订阅自动刷新。
class AppLogger extends ChangeNotifier {
  AppLogger._();

  /// 全局单例
  static final AppLogger instance = AppLogger._();

  /// 内存中保留的最大条数（同时是导出文本的上界）
  static const int maxBufferEntries = 500;

  LogSink _sink = createLogSink();

  /// 按时间**正序**存放（末尾最新）
  final List<LogEntry> _buffer = <LogEntry>[];

  bool _initialized = false;

  // ---------- 增量维护的统计量（O(1) 查询 + notifyListeners）----------
  int _problemCount = 0;
  int _warningCount = 0;

  /// 全部条目（按时间正序，不可变视图）
  List<LogEntry> get entries => UnmodifiableListView(_buffer);

  /// 总条数
  int get totalCount => _buffer.length;

  /// 错误 / 崩溃条数（增量维护，O(1)）
  int get problemCount => _problemCount;

  /// 警告条数（增量维护，O(1)）
  int get warningCount => _warningCount;

  /// 运行环境描述（导出文本抬头；跨平台，不依赖 dart:io）
  String get environmentDescription {
    // 显式映射为可读名：defaultTargetPlatform.name 会输出 `android`/`fuchsia`
    // 这类对报障无意义的字符串。Web 下 defaultTargetPlatform 返回的是「宿主」
    // 平台，也不能如实反映运行环境，故一并走 kIsWeb 判定。
    final platform = kIsWeb
        ? 'Web'
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => 'Android',
            TargetPlatform.iOS => 'iOS',
            TargetPlatform.macOS => 'macOS',
            TargetPlatform.windows => 'Windows',
            TargetPlatform.linux => 'Linux',
            TargetPlatform.fuchsia => 'Fuchsia',
          };
    const mode =
        kReleaseMode ? 'release' : (kProfileMode ? 'profile' : 'debug');
    return '$platform · $mode';
  }

  /// 初始化（幂等）：定位落盘位置 + 把历史读回内存缓冲。
  ///
  /// 任何失败都退化为「仅内存」——日志系统本身绝不能成为启动失败的来源。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      await _sink.init();
      final raw = await _sink.readAll();
      if (raw.trim().isEmpty) return;
      final parsed = <LogEntry>[];
      for (final line in const LineSplitter().convert(raw)) {
        if (line.trim().isEmpty) continue;
        final entry = LogEntry.parse(line);
        if (entry != null) parsed.add(entry);
      }
      if (parsed.isEmpty) return;
      final tail = parsed.length > maxBufferEntries
          ? parsed.sublist(parsed.length - maxBufferEntries)
          : parsed;
      _buffer
        ..clear()
        ..addAll(tail);
      // 历史载入后必须重算计数——_append 的增量维护只覆盖运行期新增
      _recount();
    } on Object catch (e) {
      debugPrint('[AppLogger] 初始化失败，退化为内存模式: $e');
    }
  }

  /// 全量重算统计量（仅在批量载入历史 / 测试注入后调用；常规路径走 [_append] 增量）
  void _recount() {
    _problemCount = 0;
    _warningCount = 0;
    for (final e in _buffer) {
      if (e.level.isProblem) _problemCount++;
      if (e.level == LogLevel.warning) _warningCount++;
    }
  }

  // ---------- 记录入口 ----------

  void info(String tag, String message, {Map<String, String>? meta}) =>
      _record(LogLevel.info, tag, message, meta);

  void warn(String tag, String message, {Map<String, String>? meta}) =>
      _record(LogLevel.warning, tag, message, meta);

  /// 记录一个错误（可附异常对象与堆栈，二者会拼进消息体）
  void error(
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
    Map<String, String>? meta,
  }) =>
      _record(LogLevel.error, tag, _compose(message, error, stack), meta);

  /// 记录一个崩溃级问题（未捕获异常 / Flutter 框架错误）
  void fatal(
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
    Map<String, String>? meta,
  }) =>
      _record(LogLevel.fatal, tag, _compose(message, error, stack), meta);

  void _record(
    LogLevel level,
    String tag,
    String message,
    Map<String, String>? meta,
  ) {
    final entry = LogEntry(
      time: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      meta: meta ?? const <String, String>{},
    );
    _append(entry);
    // debugPrint 在 release 下**并非 no-op**（SDK 里它是顶层变量
    // debugPrintThrottled，无 kReleaseMode 守卫，仅 flutter_test 会替换）。
    // 生产环境每条日志都打一次控制台既无意义也刷屏，还带上节流丢弃逻辑，
    // 故显式按 kDebugMode 收口：开发看控制台，生产只落盘。
    if (kDebugMode) {
      debugPrint('[${level.label}][$tag] $message');
    }
    unawaited(_persist(entry));
  }

  /// 入缓冲 + 维护统计量 + 通知订阅方。
  ///
  /// 计数走增量而非每次 `where().length` 全遍历：[maxBufferEntries] 上限下
  /// 全遍历只是微秒级，但统计 getter 位于 build 路径，增量化后是 O(1)，
  /// 也顺带保证「计数与缓冲内容」不会因不同 getter 的调用时机而不一致。
  void _append(LogEntry entry) {
    _buffer.add(entry);
    if (entry.level.isProblem) _problemCount++;
    if (entry.level == LogLevel.warning) _warningCount++;
    if (_buffer.length > maxBufferEntries) {
      // 环形逐出：只可能逐出最旧的一条（每次至多新增一条）
      final dropped = _buffer.removeAt(0);
      if (dropped.level.isProblem) _problemCount--;
      if (dropped.level == LogLevel.warning) _warningCount--;
    }
    notifyListeners();
  }

  Future<void> _persist(LogEntry entry) async {
    try {
      await _sink.append(entry.toLine());
    } on Object catch (_) {
      // 落盘是旁路：失败不影响主流程
    }
  }

  String _compose(String message, Object? error, StackTrace? stack) {
    if (error == null && stack == null) return message;
    final b = StringBuffer(message);
    if (error != null) b.write('\n  异常: $error');
    if (stack != null) b.write('\n  堆栈: $stack');
    return b.toString();
  }

  // ---------- 导出 / 清空 ----------

  /// 导出为纯文本（供复制 / 分享给开发者）
  String exportText() {
    final b = StringBuffer()
      ..writeln('墨影 · 错误日志')
      ..writeln('导出时间: ${formatLogTime(DateTime.now())}')
      ..writeln('运行环境: $environmentDescription')
      ..writeln('条目统计: 共 ${_buffer.length} 条 '
          '（错误/崩溃 $problemCount，警告 $warningCount）')
      ..writeln('-' * 44);
    if (_buffer.isEmpty) {
      b.writeln('（暂无日志）');
    } else {
      for (final e in _buffer) {
        b.writeln(e.toLine());
      }
    }
    return b.toString();
  }

  /// 清空内存缓冲与落盘历史
  Future<void> clear() async {
    _buffer.clear();
    _problemCount = 0;
    _warningCount = 0;
    notifyListeners();
    try {
      await _sink.clear();
    } on Object catch (_) {
      // 忽略
    }
  }

  // ---------- 测试钩子 ----------

  @visibleForTesting
  Future<void> debugInitWith(LogSink sink) async {
    _sink = sink;
    _buffer.clear();
    _problemCount = 0;
    _warningCount = 0;
    _initialized = false;
    await init();
  }

  @visibleForTesting
  void debugReset() {
    _sink = createLogSink();
    _buffer.clear();
    _problemCount = 0;
    _warningCount = 0;
    _initialized = false;
  }
}
