import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

import '../data/library_store.dart';
import '../models/sync_settings.dart';
import '../services/backup_service.dart';
import '../services/secure_storage_service.dart';
import '../services/webdav_client.dart';
import 'library_provider.dart';

/// 云端待恢复项（[fetchLatestBackup] 的返回，确认弹窗 → [confirmRestore]）
class PendingRestore {
  const PendingRestore({
    required this.fileName,
    required this.bytes,
    required this.manifest,
  });

  final String fileName;
  final Uint8List bytes;
  final BackupManifest manifest;
}

/// 云同步状态与动作（ChangeNotifier）
///
/// 依赖注入：
/// - [clientFactory] 按当前配置构造 WebDAV 客户端（测试注入 fake）
/// - [saveFile] 导出备份落盘的实现（默认 FilePicker 选位置保存，
///   写入失败自动回退系统分享面板；测试替换为收集器）
/// - [connectivity] Wi-Fi 探测（null = 不拦截，仅测试环境）
class SyncProvider extends ChangeNotifier {
  SyncProvider({
    required LibraryStore? store,
    required LibraryProvider library,
    SecureStorageService? secureStorage,
    WebDavClient Function(SyncSettings settings, String password)?
        clientFactory,
    Future<bool> Function(String fileName, Uint8List bytes)? saveFile,
    Connectivity? connectivity,
  })  : _store = store,
        _library = library,
        _secure = secureStorage ?? SecureStorageService(),
        _clientFactory = clientFactory ?? _defaultClient,
        _saveFile = saveFile ?? _defaultSaveFile,
        _connectivity = connectivity;

  final LibraryStore? _store;
  final LibraryProvider _library;
  final SecureStorageService _secure;
  final WebDavClient Function(SyncSettings, String) _clientFactory;
  final Future<bool> Function(String, Uint8List) _saveFile;
  final Connectivity? _connectivity;

  SyncSettings _settings = const SyncSettings();
  bool _isSyncing = false;
  String? _lastError;

  SyncSettings get settings => _settings;
  bool get isSyncing => _isSyncing;
  String? get lastError => _lastError;

  /// 启动加载配置（main.dart init 阶段调用；损坏回退默认值）
  Future<void> loadSettings() async {
    final store = _store;
    if (store == null) return;
    _settings = await store.loadSettings();
    notifyListeners();
  }

  /// 保存配置（settings.json；密码单独走安全存储见 [savePassword]）
  Future<void> saveSettings(SyncSettings next) async {
    _settings = next;
    notifyListeners();
    await _store?.saveSettings(next);
  }

  /// 保存 / 更新 WebDAV 密码（安全存储，不落 settings.json）
  Future<void> savePassword(String password) =>
      _secure.saveWebDavPassword(_settings.username.trim(), password);

  /// UI 回填密码用（仅编辑页展示；安全存储按当前用户名读取）
  Future<String?> readPasswordForUi() =>
      _secure.readWebDavPassword(_settings.username.trim());

  // ==================== 连接与同步动作 ====================

  /// 测试连接：验证 URL/凭据并确保远程目录存在
  Future<void> testConnection() async {
    final client = await _requireClient();
    try {
      await client.testConnection();
      _lastError = null;
    } on WebDavException catch (e) {
      _lastError = e.message;
      rethrow;
    } finally {
      client.close();
      notifyListeners();
    }
  }

  /// 立即上传备份（flush → 打包 → PUT → 记录同步时间）
  Future<void> uploadNow() async {
    final store = _store;
    if (store == null) throw WebDavException(null, '当前平台不支持备份');
    final client = await _requireClient();
    _isSyncing = true;
    _lastError = null;
    notifyListeners();
    try {
      await store.flush();
      final bytes = await BackupService(
        store: store,
      ).buildBackup(includeImages: _settings.includeImages);
      final now = DateTime.now();
      final stamp = BackupService(store: store).backupFileStamp(now);
      final fileName = _settings.includeImages ? '$stamp.zip' : '$stamp.json';
      await client.upload(fileName, bytes);
      _settings = _settings.copyWith(lastSyncAt: now);
      await store.saveSettings(_settings);
    } on WebDavException catch (e) {
      _lastError = e.message;
      rethrow;
    } finally {
      client.close();
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// 拉取云端最新备份（不落盘），供确认弹窗展示
  Future<PendingRestore> fetchLatestBackup() async {
    final store = _store;
    if (store == null) throw WebDavException(null, '当前平台不支持恢复');
    final client = await _requireClient();
    _isSyncing = true;
    _lastError = null;
    notifyListeners();
    try {
      final names = await client.listBackups();
      if (names.isEmpty) {
        throw WebDavException(null, '云端还没有备份文件');
      }
      final bytes = await client.download(names.first);
      final manifest = await BackupService(store: store).peekBackup(bytes);
      _lastError = null;
      return PendingRestore(
        fileName: names.first,
        bytes: bytes,
        manifest: manifest,
      );
    } on WebDavException catch (e) {
      _lastError = e.message;
      rethrow;
    } finally {
      client.close();
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// 确认恢复：覆盖本地数据并重新加载（UI 二次确认后调用）
  Future<void> confirmRestore(PendingRestore pending) async {
    final store = _store;
    if (store == null) throw WebDavException(null, '当前平台不支持恢复');
    _isSyncing = true;
    notifyListeners();
    try {
      await BackupService(store: store).restoreBackup(pending.bytes);
      await _library.reloadFromStore();
      _settings = _settings.copyWith(lastSyncAt: DateTime.now());
      await store.saveSettings(_settings);
      _lastError = null;
    } on BackupException catch (e) {
      _lastError = e.message;
      rethrow;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  // ==================== 本地导出 / 导入（保底备选） ====================

  /// 导出备份到本地：按「备份包含本地图片」设置打包（JSON 单文件 / 含图 ZIP），
  /// FilePicker 选保存位置，用户取消返回 false，写入成功返回 true
  Future<bool> exportLocal() async {
    final store = _store;
    if (store == null) throw WebDavException(null, '当前平台不支持导出');
    await store.flush();
    final bytes = await BackupService(store: store).buildBackup(
      includeImages: _settings.includeImages,
    );
    final stamp = BackupService(store: store).backupFileStamp(DateTime.now());
    final fileName = _settings.includeImages ? '$stamp.zip' : '$stamp.json';
    return _saveFile(fileName, bytes);
  }

  /// 从本地备份文件恢复（UI 先读文件字节 + peek 弹窗，确认后走 [confirmRestore]）
  Future<PendingRestore> parseLocalBackup(Uint8List bytes) async {
    final store = _store;
    if (store == null) throw WebDavException(null, '当前平台不支持恢复');
    final manifest = await BackupService(store: store).peekBackup(bytes);
    return PendingRestore(
      fileName: '本地文件',
      bytes: bytes,
      manifest: manifest,
    );
  }

  // ==================== 自动同步 ====================

  /// App 冷启动后首帧触发（main.dart onResume 钩子调用；节流 1 小时）
  Future<void> tryAutoSyncOnResume() async {
    if (!_settings.autoSync || !_settings.isConfigured || _isSyncing) return;
    final last = _settings.lastSyncAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(hours: 1)) {
      return;
    }
    if (_settings.onlyOnWifi && !await _isOnWifi()) return;
    try {
      await uploadNow();
    } on Exception {
      // 自动同步静默失败：错误已记入 lastError，不打断启动流程
    }
  }

  Future<bool> _isOnWifi() async {
    final connectivity = _connectivity;
    if (connectivity == null) return true; // 无法探测时不拦截
    final results = await connectivity.checkConnectivity();
    return results.any((r) =>
        r == ConnectivityResult.wifi || r == ConnectivityResult.ethernet);
  }

  // ==================== 内部 ====================

  /// 按当前配置 + 安全存储密码构造客户端（未配置 / 无密码抛异常）
  Future<WebDavClient> _requireClient() async {
    if (!_settings.isConfigured) {
      throw WebDavException(null, '请先填写服务器地址与账号');
    }
    final password =
        await _secure.readWebDavPassword(_settings.username.trim());
    if (password == null || password.isEmpty) {
      throw WebDavException(null, '请先填写密码（应用授权码）');
    }
    return _clientFactory(_settings, password);
  }

  static WebDavClient _defaultClient(SyncSettings settings, String password) {
    return WebDavClientHttp(
      remoteDirUrl: settings.remoteDirUrl,
      username: settings.username.trim(),
      password: password,
    );
  }

  /// 默认导出实现：系统「另存为」对话框选位置 → 写文件。
  /// 用户取消（返回 null）→ false；选了位置但 dart:io 写入失败（部分机型
  /// SAF 路径不可直接写）→ 自动回退到系统分享面板兜底。
  static Future<bool> _defaultSaveFile(String fileName, Uint8List bytes) async {
    final path = await FilePicker.platform.saveFile(
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [fileName.endsWith('.zip') ? 'zip' : 'json'],
    );
    if (path == null || path.isEmpty) return false; // 用户取消
    try {
      await File(path).writeAsBytes(bytes);
      return true;
    } on FileSystemException {
      final tmp = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}$fileName',
      );
      await tmp.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(tmp.path)], subject: '墨影数据备份');
      return true;
    }
  }
}
