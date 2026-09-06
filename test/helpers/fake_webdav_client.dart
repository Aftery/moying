import 'dart:typed_data';

import 'package:moying/services/webdav_client.dart';

/// 内存 fake（widget / 单元测试注入；行为与 [WebDavClientHttp] 对齐）
class FakeWebDavClient implements WebDavClient {
  FakeWebDavClient({Map<String, int>? failOn}) : failOn = failOn ?? {};
  final Map<String, int> failOn;
  final Map<String, Uint8List> store = {};
  int mkdirCalls = 0;
  int uploadCalls = 0;
  bool failNext = false;

  void _maybeFail(String op) {
    final code = failOn[op];
    if (failNext || (code != null && code > 0)) {
      failNext = false;
      if (code != null) failOn[op] = code - 1;
      throw WebDavException(500, '$op：模拟失败');
    }
  }

  @override
  Future<bool> testConnection() async {
    _maybeFail('testConnection');
    mkdirCalls++;
    return true;
  }

  @override
  Future<void> upload(String fileName, Uint8List bytes) async {
    _maybeFail('upload');
    uploadCalls++;
    store[fileName] = bytes;
  }

  @override
  Future<Uint8List> download(String fileName) async {
    _maybeFail('download');
    final data = store[fileName];
    if (data == null) {
      throw WebDavException(404, '下载备份：云端不存在该文件');
    }
    return data;
  }

  @override
  Future<List<String>> listBackups() async {
    _maybeFail('listBackups');
    final names = store.keys.where((n) => n.startsWith('moying-')).toList();
    names.sort((a, b) => b.compareTo(a));
    return names;
  }

  @override
  void close() {}
}
