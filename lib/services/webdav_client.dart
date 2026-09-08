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

  /// 列出云端备份文件（moying-*.zip / moying-*.json，按文件名倒序 = 时间倒序）
  Future<List<String>> listBackups();

  /// 释放底层 HTTP 连接池与客户端资源
  void close();
}

/// HTTP 实现（dart http + Basic Auth + RFC 4918 PROPFIND）
///
/// 历史变更：早先用 `GET + Depth:1` 列目录，部分标准 WebDAV 服务
/// （坚果云 / Nextcloud）要求真正的 `PROPFIND` 才能列目录，否则 405；
/// 现统一走 PROPFIND，207 Multi-Status 解析 `<d:href>` 提取裸文件名。
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

  /// 普通请求超时（不设超时会让同步按钮永久转圈，无任何恢复路径）
  static const Duration _kTimeout = Duration(seconds: 15);

  /// 备份包可能几 MB，上传/下载单独放宽
  static const Duration _kTransferTimeout = Duration(seconds: 60);

  /// M9：备份包下载上限 200 MB（与 BackupService 解压上限一致）。
  /// 先看 Content-Length 预检，超限立即拒绝，避免整包进内存。
  static const int _maxBackupBytes = 200 * 1024 * 1024;

  /// PROPFIND body：只取 displayname / href；Depth 由调用方传入。
  /// 服务端按规范只返回该 Depth 内的资源状态。
  static const String _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:">'
      '<d:prop><d:displayname/></d:prop>'
      '</d:propfind>';

  /// 匹配 moying-*.{zip,json} 的裸文件名（取 d:href 末段）。
  /// 备份文件名由本应用生成（无特殊字符），正则足够，不引 xml 依赖。
  static final RegExp _backupFileNameRe =
      RegExp(r'^moying-[^<>\s/\\:]+\.(?:zip|json)$');

  Never _timeout(String action) =>
      throw WebDavException(null, '$action：请求超时，请检查网络或服务器地址');

  Uri _uri(String? fileName) => Uri.parse(
        fileName == null ? _normalizedDir : '$_normalizedDir$fileName',
      );

  /// 规范化目录 URL：强制以 / 结尾。PROPFIND 不接受 301 重定向到无斜杠
  /// 的父目录（部分服务器会把 /dir 跳到 /dir/），前置补齐避免不必要的重定向。
  String get _normalizedDir {
    var d = remoteDirUrl.trim();
    if (d.isEmpty) return d;
    return d.endsWith('/') ? d : '$d/';
  }

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
    } else if (code == 405) {
      // 405 仅在 PROPFIND 上有意义（GET 上 405 是别的语义）
      reason = isPropfind
          ? '服务器不支持 PROPFIND，请确认这是标准 WebDAV 服务（坚果云 / Nextcloud）'
          : '请求方法不被允许（HTTP 405）';
    } else if (code >= 500) {
      reason = '服务器错误（$code），请稍后重试';
    } else {
      reason = '请求失败（HTTP $code）';
    }
    throw WebDavException(code, '$action：$reason');
  }

  /// 发送 PROPFIND（XML body + Depth 头）。
  /// Depth=0 仅查目录自身属性；Depth=1 含直接子节点，列备份用。
  Future<http.Response> _propfind(String action, String depth) async {
    final req = http.Request('PROPFIND', _uri(null))
      ..headers.addAll({
        ..._authHeaders,
        'Depth': depth,
        'Content-Type': 'application/xml; charset=utf-8',
      })
      ..body = _propfindBody;
    final streamed = await _http
        .send(req)
        .timeout(_kTimeout, onTimeout: () => _timeout(action));
    return http.Response.fromStream(streamed).timeout(
      _kTimeout,
      onTimeout: () => _timeout('$action：读取响应'),
    );
  }

  @override
  Future<bool> testConnection() async {
    // 1) PROPFIND base 目录 Depth=0：验证 URL 与凭据
    final probe = await _propfind('连接测试', '0');
    // 207 Multi-Status / 200 / 204 均视为连接成功（部分服务器 204 No Content）
    if (probe.statusCode != 207 &&
        probe.statusCode != 200 &&
        probe.statusCode != 204) {
      _fail(probe, '连接测试', isPropfind: true);
    }

    // 2) MKCOL 远程目录：不存在则创建；405=已存在视为成功
    final req = http.Request('MKCOL', _uri(null))..headers.addAll(_authHeaders);
    final streamed = await _http
        .send(req)
        .timeout(_kTimeout, onTimeout: () => _timeout('创建云端目录'));
    final mkdir = await http.Response.fromStream(streamed).timeout(
      _kTimeout,
      onTimeout: () => _timeout('读取云端目录响应'),
    );
    if (mkdir.statusCode >= 400 && mkdir.statusCode != 405) {
      _fail(mkdir, '创建云端目录');
    }
    return true;
  }

  @override
  Future<void> upload(String fileName, Uint8List bytes) async {
    // 确保远程目录存在（幂等：已存在则 MKCOL 返回 405 视为成功）
    try {
      final req = http.Request('MKCOL', _uri(null))
        ..headers.addAll(_authHeaders);
      final streamed = await _http
          .send(req)
          .timeout(_kTimeout, onTimeout: () => _timeout('创建云端目录'));
      final mkdir = await http.Response.fromStream(streamed).timeout(
        _kTimeout,
        onTimeout: () => _timeout('读取云端目录响应'),
      );
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
    // M9：先看 Content-Length 预检，超限立即拒绝，避免整包进内存
    final lenHeader = resp.headers['content-length'];
    if (lenHeader != null) {
      final len = int.tryParse(lenHeader);
      if (len != null && len > _maxBackupBytes) {
        throw WebDavException(
          null,
          '备份文件超过 200 MB，无法下载',
        );
      }
    }
    return resp.bodyBytes;
  }

  @override
  Future<List<String>> listBackups() async {
    final resp = await _propfind('读取云端备份列表', '1');
    // 207 Multi-Status：每个子资源一个 <response> 块；200/204 视为无子文件
    if (resp.statusCode == 200 || resp.statusCode == 204) return const [];
    if (resp.statusCode != 207) _fail(resp, '读取云端备份列表', isPropfind: true);

    final names = _extractBackupFileNames(resp.body);
    names.sort((a, b) => b.compareTo(a)); // 名字含时间戳，倒序即最新在前
    return names;
  }

  /// 从 207 Multi-Status 响应 XML 提取符合 moying-*.{zip,json} 的裸文件名。
  ///
  /// 策略：
  /// - 优先取 `<d:href>` 的最后一段 pathSegment（路径可能含 /dav/xxx/前缀）；
  /// - href 缺失或未匹配时回退 `<d:displayname>`；
  /// - `Uri.decodeComponent` 处理 URL 编码字符；
  /// - 限定 `.zip|.json` 两种扩展名（H1 修复：原只匹配 .zip 导致 JSON 备份不可见）。
  List<String> _extractBackupFileNames(String xml) {
    final out = <String>[];
    final hrefRe =
        RegExp(r'<[^>]*d:href[^>]*>([^<]+)</[^>]*d:href>', caseSensitive: false);
    final nameRe = RegExp(
        r'<[^>]*d:displayname[^>]*>([^<]+)</[^>]*d:displayname>',
        caseSensitive: false);

    final hrefs = hrefRe.allMatches(xml).map((m) => m.group(1)!.trim());
    final names = nameRe
        .allMatches(xml)
        .map((m) => m.group(1)!.trim())
        .toList();

    var nameIdx = 0;
    for (final raw in hrefs) {
      // href 通常是完整路径如 "/dav/backup/moying-xxx.zip"，取最后一段
      final decoded = Uri.decodeComponent(raw);
      final last = decoded.split('/').where((s) => s.isNotEmpty).last;
      final candidate = _backupFileNameRe.hasMatch(last) ? last : null;
      if (candidate != null) {
        out.add(candidate);
      } else if (nameIdx < names.length) {
        // 兜底：displayname 通常就是文件名（部分服务 href 直接是文件名）
        final n = names[nameIdx];
        if (_backupFileNameRe.hasMatch(n)) out.add(n);
        nameIdx++;
      }
    }
    return out.toSet().toList();
  }

  @override
  void close() {
    _http.close();
  }
}
