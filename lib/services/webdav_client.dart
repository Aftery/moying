import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// WebDAV 操作异常（状态码 + 归一化文案，UI 直接展示）
class WebDavException implements Exception {
  WebDavException(this.statusCode, this.message);

  final int? statusCode;
  final String message;

  @override
  String toString() => 'WebDavException($statusCode): $message';
}

/// WebDAV 客户端抽象（可注入 fake 供测试）
///
/// 只封装本项目需要的最小操作面：连接测试、上传、下载、列备份。
/// 目录 URL 由 [remoteDirUrl] 提供（`SyncSettings.remoteDirUrl` 拼接结果，
/// 以 / 结尾），文件名只传裸文件名。
abstract class WebDavClient {
  /// 测试连接：PROPFIND base 目录验证凭据 + MKCOL 远程目录确保存在。
  /// 成功返回 true；凭据错误抛 401、网络不可达抛 [WebDavException]。
  Future<bool> testConnection();

  /// 上传备份文件（覆盖同名）
  Future<void> upload(String fileName, Uint8List bytes);

  /// 下载备份文件
  Future<Uint8List> download(String fileName);

  /// 列出云端备份文件（moying-*.zip，按文件名倒序 = 时间倒序）
  Future<List<String>> listBackups();

  /// 释放底层 HTTP 连接池与客户端资源
  void close();
}

/// HTTP 实现（dart http + Basic Auth）
class WebDavClientHttp implements WebDavClient {
  WebDavClientHttp({
    required this.remoteDirUrl,
    required this.username,
    required this.password,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// 以 / 结尾的完整远程目录 URL
  final String remoteDirUrl;
  final String username;
  final String password;
  final http.Client _http;

  Map<String, String> get _authHeaders => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      };

  /// 普通请求超时（H3：不设超时会让同步按钮永久转圈，无任何恢复路径）
  static const Duration _kTimeout = Duration(seconds: 15);

  /// 备份包可能几 MB，上传/下载单独放宽
  static const Duration _kTransferTimeout = Duration(seconds: 60);

  Never _timeout(String action) =>
      throw WebDavException(null, '$action：请求超时，请检查网络或服务器地址');

  Uri _uri(String? fileName) =>
      Uri.parse(fileName == null ? remoteDirUrl : '$remoteDirUrl$fileName');

  /// 归一化 HTTP 错误 → 用户可读文案
  Never _fail(http.Response resp, String action, {bool isPropfind = false}) {
    final code = resp.statusCode;
    String reason;
    if (code == 401 || code == 403) {
      reason = isPropfind
          ? '连接测试通过，但服务器禁止目录列表（PROPFIND 受限），不影响备份上传'
          : '账号或密码（应用授权码）错误';
    } else if (code == 404) {
      reason = '云端目录不存在';
    } else if (code >= 500) {
      reason = '服务器错误（$code），请稍后重试';
    } else {
      reason = '请求失败（HTTP $code）';
    }
    throw WebDavException(code, '$action：$reason');
  }

  @override
  Future<bool> testConnection() async {
    // 1) PROPFIND base 目录：验证 URL 与凭据（PROPFIND 失败不视为配置错误）
    final probe = await _http
        .get(
          _uri(null),
          headers: {..._authHeaders, 'Depth': '0'},
        )
        .timeout(_kTimeout, onTimeout: () => _timeout('连接测试'));
    if (probe.statusCode >= 400) _fail(probe, '连接测试', isPropfind: true);

    // 2) MKCOL 远程目录：不存在则创建；405=已存在视为成功
    final req = http.Request('MKCOL', _uri(null))..headers.addAll(_authHeaders);
    final streamed = await _http
        .send(req)
        .timeout(_kTimeout, onTimeout: () => _timeout('创建云端目录'));
    final mkdir = await http.Response.fromStream(streamed);
    if (mkdir.statusCode >= 400 && mkdir.statusCode != 405) {
      _fail(mkdir, '创建云端目录');
    }
    return true;
  }

  @override
  Future<void> upload(String fileName, Uint8List bytes) async {
    // 确保远程目录存在（幂等：已存在则 MKCOL 返回 405 视为成功）
    try {
      final req = http.Request('MKCOL', _uri(null))..headers.addAll(_authHeaders);
      final streamed = await _http
          .send(req)
          .timeout(_kTimeout, onTimeout: () => _timeout('创建云端目录'));
      final mkdir = await http.Response.fromStream(streamed);
      if (mkdir.statusCode >= 400 && mkdir.statusCode != 405) {
        _fail(mkdir, '创建云端目录');
      }
    } catch (_) {
      // 容错：MKCOL 失败不阻断上传，后续 PUT 会有明确错误
    }

    final resp = await _http
        .put(
          _uri(fileName),
          headers: _authHeaders,
          body: bytes,
        )
        .timeout(_kTransferTimeout, onTimeout: () => _timeout('上传备份'));
    if (resp.statusCode >= 400) _fail(resp, '上传备份');
  }

  @override
  Future<Uint8List> download(String fileName) async {
    final resp = await _http
        .get(_uri(fileName), headers: _authHeaders)
        .timeout(_kTransferTimeout, onTimeout: () => _timeout('下载备份'));
    if (resp.statusCode >= 400) _fail(resp, '下载备份');
    return resp.bodyBytes;
  }

  @override
  Future<List<String>> listBackups() async {
    final resp = await _http
        .get(
          _uri(null),
          headers: {..._authHeaders, 'Depth': '1'},
        )
        .timeout(_kTimeout, onTimeout: () => _timeout('读取云端备份列表'));
    if (resp.statusCode >= 400) _fail(resp, '读取云端备份列表');
    // 轻量解析：WebDAV PROPFIND 的 XML 里提取 moying-*.zip 文件名。
    // 备份文件名由本应用生成（无特殊字符），正则足够，不值得引 xml 依赖。
    final names = RegExp(r'>(moying-[^<>\s/]+\.zip)<')
        .allMatches(resp.body)
        .map((m) => m.group(1)!)
        .toSet()
        .toList();
    names.sort((a, b) => b.compareTo(a)); // 名字含时间戳，倒序即最新在前
    return names;
  }

  @override
  void close() {
    _http.close();
  }
}
