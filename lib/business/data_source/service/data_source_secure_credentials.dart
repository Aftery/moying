import '../../../foundation/storage/secure_store.dart';
import 'data_source_interface.dart';

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
