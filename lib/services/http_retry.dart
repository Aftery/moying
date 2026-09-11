import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 数据源网络请求的**分层超时 + 一次重试**
///
/// **为什么不是简单地把超时调长**：慢源（OpenLibrary / Google Books /
/// 自建代理）在弱网下最耗时的其实是**首跳建连**——DNS 解析 + TCP 握手 +
/// TLS 协商，而不是数据传输。单次 15s 超时意味着一次冷连接失败就整条检索失败，
/// 用户只能手动重试。
///
/// 拆成「首跳 [kFirstAttemptTimeout] + 重试 [kRetryAttemptTimeout]」：
/// - **最坏耗时与原来基本持平**（6 + 9 + 0.3 ≈ 15.3s vs 原来的 15s），
///   不会让真正的死链拖得更久；
/// - 但重试那一跳能命中**已经建好的连接**（连接池复用），
///   冷启动 / 瞬时抖动导致的超时因此有了一次自救机会。
///
/// 只对**可安全重放的失败**重试：超时、连接被拒/重置。HTTP 4xx/5xx 不重试——
/// 那是服务端的明确回答，重试只会加重对方负担（如 429 限流）。

/// 首跳超时（快速失败，把预算留给重试）
const Duration kFirstAttemptTimeout = Duration(seconds: 6);

/// 重试跳超时
const Duration kRetryAttemptTimeout = Duration(seconds: 9);

/// 两次尝试之间的停顿（给对端一点喘息，也给连接池复用留出窗口）
const Duration kRetryBackoff = Duration(milliseconds: 300);

/// 总尝试次数（1 次首跳 + 1 次重试）
const int _kMaxAttempts = 2;

/// 发起 GET，按 [firstTimeout] / [retryTimeout] 分层超时，失败重试一次。
///
/// 超时或网络异常在**最后一次尝试后原样抛出**（`TimeoutException` /
/// `SocketException` / `ClientException`），由调用方翻译成面向用户的中文文案——
/// 本层不感知 [DataSourceException]。
///
/// 参数可注入是为了测试：用例把 [backoff] 设为 [Duration.zero] 就不必真的等待。
Future<http.Response> getWithRetry(
  http.Client client,
  Uri uri, {
  Map<String, String>? headers,
  Duration firstTimeout = kFirstAttemptTimeout,
  Duration retryTimeout = kRetryAttemptTimeout,
  Duration backoff = kRetryBackoff,
}) async {
  for (var attempt = 1;; attempt++) {
    final timeout = attempt == 1 ? firstTimeout : retryTimeout;
    try {
      return await client.get(uri, headers: headers).timeout(timeout);
    } on TimeoutException {
      if (attempt >= _kMaxAttempts) rethrow;
    } on SocketException {
      if (attempt >= _kMaxAttempts) rethrow;
    } on http.ClientException {
      if (attempt >= _kMaxAttempts) rethrow;
    }
    if (backoff > Duration.zero) await Future<void>.delayed(backoff);
  }
}
