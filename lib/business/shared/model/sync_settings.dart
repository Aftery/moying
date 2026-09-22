/// 数据同步配置（settings.json 持久化；WebDAV 密码不在此存）
///
/// 非敏感配置走普通 JSON 文件（便于备份排查）；密码/授权码单独存入
/// 系统安全存储（`SecureStorageService`，Android Keystore / iOS Keychain），
/// 两者分离——即使 settings.json 被导出查看也拿不到凭据。
class SyncSettings {
  const SyncSettings({
    this.webdavUrl = '',
    this.username = '',
    this.remoteFolder = defaultRemoteFolder,
    this.autoSync = false,
    this.onlyOnWifi = true,
    this.includeImages = true,
    this.lastSyncAt,
  });

  /// 服务器地址（含协议与 base path，如 https://dav.jianguoyun.com/dav）
  final String webdavUrl;

  /// 登录账号（坚果云为邮箱）
  final String username;

  /// 云端存储目录（相对 base path，默认 /墨影Backup/）
  final String remoteFolder;

  /// 启动时自动静默同步（总开关）
  final bool autoSync;

  /// 仅 Wi-Fi 下自动同步（autoSync 关闭时无效）
  final bool onlyOnWifi;

  /// 备份包含本地上传的海报 / 图片（关闭则仅 JSON 文本，体积小）
  final bool includeImages;

  /// 上次成功同步时间（null = 从未同步）
  final DateTime? lastSyncAt;

  static const String defaultRemoteFolder = '/墨影Backup/';

  /// 云端配置是否已填写完整（不含密码——密码在安全存储中单独校验）
  bool get isConfigured =>
      webdavUrl.trim().isNotEmpty && username.trim().isNotEmpty;

  /// 拼接后的完整目录 URL（自动补齐斜杠边界）
  String get remoteDirUrl {
    final base = webdavUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final folder = remoteFolder.trim();
    if (folder.isEmpty || folder == '/') return '$base/';
    return '$base/${folder.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '')}/';
  }

  SyncSettings copyWith({
    String? webdavUrl,
    String? username,
    String? remoteFolder,
    bool? autoSync,
    bool? onlyOnWifi,
    bool? includeImages,
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
  }) {
    return SyncSettings(
      webdavUrl: webdavUrl ?? this.webdavUrl,
      username: username ?? this.username,
      remoteFolder: remoteFolder ?? this.remoteFolder,
      autoSync: autoSync ?? this.autoSync,
      onlyOnWifi: onlyOnWifi ?? this.onlyOnWifi,
      includeImages: includeImages ?? this.includeImages,
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
    );
  }

  Map<String, dynamic> toJson() => {
        'webdavUrl': webdavUrl,
        'username': username,
        'remoteFolder': remoteFolder,
        'autoSync': autoSync,
        'onlyOnWifi': onlyOnWifi,
        'includeImages': includeImages,
        'lastSyncAt': lastSyncAt?.toIso8601String(),
      };

  factory SyncSettings.fromJson(Map<String, dynamic> json) {
    final lastSync = json['lastSyncAt'];
    return SyncSettings(
      webdavUrl: json['webdavUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      remoteFolder:
          json['remoteFolder'] as String? ?? defaultRemoteFolder,
      autoSync: json['autoSync'] as bool? ?? false,
      onlyOnWifi: json['onlyOnWifi'] as bool? ?? true,
      includeImages: json['includeImages'] as bool? ?? true,
      lastSyncAt:
          lastSync is String ? DateTime.tryParse(lastSync) : null,
    );
  }
}
