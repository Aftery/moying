import '../../../foundation/storage/secure_store.dart';

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
