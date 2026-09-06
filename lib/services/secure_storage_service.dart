import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'data_source_interface.dart';

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

/// WebDAV 凭据安全存储（Android Keystore / iOS·macOS Keychain）
///
/// 密码/应用授权码**绝不落 settings.json**——那里只存非敏感配置。
/// key 按用户名隔离：`webdav_password_<username>`，切换账号互不干扰。
///
/// 测试注入：[store] 可替换为内存实现（见 `InMemorySecureStore`）。
class SecureStorageService {
  SecureStorageService({SecureStore? store})
      : _storage = store ?? const FlutterSecureStore();

  final SecureStore _storage;

  static String _key(String username) => 'webdav_password_$username';

  /// 保存密码（覆盖旧值；空串视为删除）
  Future<void> saveWebDavPassword(String username, String password) async {
    final key = _key(username);
    if (password.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: password);
    }
  }

  /// 读取密码（未存过返回 null）
  Future<String?> readWebDavPassword(String username) =>
      _storage.read(key: _key(username));

  /// 删除密码（换账号 / 清除配置时调用）
  Future<void> deleteWebDavPassword(String username) =>
      _storage.delete(key: _key(username));
}

/// 数据源凭据存取（[DataSourceCredentialStore] 平台实现）
///
/// key 形如 `ds_credential_<sourceId>_<configKey>`，与数据源配置文件
/// `data_sources.json`（不含凭据）分离。测试注入内存版 SecureStore。
class DataSourceSecureCredentials implements DataSourceCredentialStore {
  DataSourceSecureCredentials({SecureStore? store})
      : _storage = store ?? const FlutterSecureStore();

  final SecureStore _storage;

  static String _key(String sourceId, String configKey) =>
      'ds_credential_${sourceId}_$configKey';

  @override
  Future<String?> read(String sourceId, String key) =>
      _storage.read(key: _key(sourceId, key));

  @override
  Future<void> write(String sourceId, String key, String value) async {
    if (value.isEmpty) {
      await _storage.delete(key: _key(sourceId, key));
    } else {
      await _storage.write(key: _key(sourceId, key), value: value);
    }
  }

  @override
  Future<void> delete(String sourceId, String key) =>
      _storage.delete(key: _key(sourceId, key));
}
