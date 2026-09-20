import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 凭据读写最小接口
///
/// 真实实现走平台 Keychain / Keystore；测试注入内存版（[InMemorySecureStore]）。
/// 只暴露本项目需要的三个操作，避免测试端适配 FlutterSecureStorage 的
/// 全平台 options 签名。
abstract class SecureStore {
  Future<void> write({required String key, required String? value});
  Future<String?> read({required String key});
  Future<void> delete({required String key});
}

/// 平台实现（Android Keystore / iOS·macOS Keychain）
class FlutterSecureStore implements SecureStore {
  const FlutterSecureStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<void> write({required String key, required String? value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// 内存实现（widget 测试 / 平台通道不可用环境）
class InMemorySecureStore implements SecureStore {
  final Map<String, String> _values = {};

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<String?> read({required String key}) => Future.value(_values[key]);

  @override
  Future<void> delete({required String key}) async => _values.remove(key);
}
