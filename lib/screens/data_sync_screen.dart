import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../models/sync_settings.dart';
import '../providers/data_source_provider.dart';
import '../providers/sync_provider.dart';
import '../services/backup_service.dart';
import '../services/webdav_client.dart';

/// 数据同步页 —— WebDAV 云同步 + 本地导出/导入（P5）
///
/// 结构对齐设计稿：云同步卡（上次同步 + 立即备份 / 从云端恢复）→
/// 服务器设置（4 输入 + 测试连接）→ 同步偏好（3 开关）→ 本地备份（导出 / 导入）。
class DataSyncScreen extends StatefulWidget {
  const DataSyncScreen({super.key});

  @override
  State<DataSyncScreen> createState() => _DataSyncScreenState();
}

class _DataSyncScreenState extends State<DataSyncScreen> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _folderCtrl;
  bool _passwordVisible = false;
  bool _passwordLoaded = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SyncProvider>().settings;
    _urlCtrl = TextEditingController(text: settings.webdavUrl);
    _userCtrl = TextEditingController(text: settings.username);
    _folderCtrl = TextEditingController(text: settings.remoteFolder);
    _passwordCtrl = TextEditingController();
    _loadPassword();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passwordCtrl.dispose();
    _folderCtrl.dispose();
    super.dispose();
  }

  /// 密码从安全存储异步回填（settings.json 里没有它）
  Future<void> _loadPassword() async {
    final sync = context.read<SyncProvider>();
    await sync.loadSettings();
    if (!mounted) return;
    final password = await sync.readPasswordForUi();
    if (!mounted) return;
    _passwordCtrl.text = password ?? '';
    setState(() => _passwordLoaded = true);
  }

  /// 输入框当前值 → SyncSettings（动作前收集，保证最新）
  SyncSettings _collectInput({SyncSettings? base}) {
    final sync = context.read<SyncProvider>();
    final s = base ?? sync.settings;
    return s.copyWith(
      webdavUrl: _urlCtrl.text.trim(),
      username: _userCtrl.text.trim(),
      remoteFolder: _folderCtrl.text.trim().isEmpty
          ? SyncSettings.defaultRemoteFolder
          : _folderCtrl.text.trim(),
    );
  }

  /// 保存当前输入（含密码→安全存储）；配置不完整时只存已填部分
  Future<void> _persistInput() async {
    final sync = context.read<SyncProvider>();
    final next = _collectInput();
    await sync.saveSettings(next);
    await sync.savePassword(_passwordCtrl.text);
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: error ? context.colors.movieEnd : null,
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ==================== 动作 ====================

  Future<void> _onTestConnection() async {
    final sync = context.read<SyncProvider>();
    try {
      await _persistInput();
      await sync.testConnection();
      _toast('连接成功');
    } on WebDavException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _onUpload() async {
    final sync = context.read<SyncProvider>();
    try {
      await _persistInput();
      await sync.uploadNow();
      _toast('备份已上传');
    } on WebDavException catch (e) {
      _toast(e.message, error: true);
    } on BackupException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _onRestoreFromCloud() async {
    final sync = context.read<SyncProvider>();
    try {
      await _persistInput();
      final pending = await sync.fetchLatestBackup();
      if (!mounted) return;
      final confirmed =
          await _confirmRestore(pending.manifest, source: pending.fileName);
      if (confirmed != true || !mounted) return;
      await sync.confirmRestore(pending);
      _toast('已从云端恢复');
      await _afterRestoreReload();
    } on WebDavException catch (e) {
      _toast(e.message, error: true);
    } on BackupException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _onExportLocal() async {
    final sync = context.read<SyncProvider>();
    try {
      final saved = await sync.exportLocal();
      if (!mounted) return;
      if (saved) {
        _toast('备份已保存');
      }
      // 用户取消选位置：不提示
    } on Exception catch (e) {
      _toast('导出失败：$e', error: true);
    }
  }

  Future<void> _onImportLocal() async {
    final sync = context.read<SyncProvider>();
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'zip'],
      withData: true,
    );
    final data = picked?.files.singleOrNull?.bytes;
    if (data == null) return; // 用户取消
    try {
      final pending = await sync.parseLocalBackup(
        Uint8List.fromList(data),
      );
      if (!mounted) return;
      final confirmed =
          await _confirmRestore(pending.manifest, source: pending.fileName);
      if (confirmed != true || !mounted) return;
      await sync.confirmRestore(pending);
      _toast('已从本地文件恢复');
      await _afterRestoreReload();
    } on BackupException catch (e) {
      _toast(e.message, error: true);
    }
  }

  /// 恢复完成后的收尾：数据源配置可能被备份覆盖 → 重载内存列表；
  /// 必填凭据缺失的源（跨设备恢复场景）集中提示重填
  Future<void> _afterRestoreReload() async {
    DataSourceProvider? ds;
    try {
      ds = context.read<DataSourceProvider>();
    } on ProviderNotFoundException {
      return;
    }
    await ds.reload();
    final missing = await ds.sourcesMissingCredentials();
    if (!mounted) return;
    if (missing.isNotEmpty) {
      _toast('以下数据源需重新配置 API Key：${missing.join('、')}', error: true);
    }
  }

  /// 恢复二次确认（数据安全闸门：明确覆盖语义 + 条目数）
  Future<bool?> _confirmRestore(BackupManifest manifest,
      {required String source}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceHigh,
        title: Text('从${source == '本地文件' ? '本地文件' : '云端'}恢复',
            style: TextStyle(color: context.colors.textPrimary)),
        content: Text(
          '将覆盖本地现有数据：\n'
          '${manifest.counts['books.json'] ?? 0} 本书、'
          '${manifest.counts['movies.json'] ?? 0} 部电影、'
          '${manifest.counts['actors.json'] ?? 0} 位演员'
          '${manifest.includeImages ? '、${manifest.imageCount} 张图片' : ''}\n\n'
          '覆盖前会在本地保留一份当前数据快照（backup-pre-restore）。确定继续吗？',
          style: TextStyle(color: context.colors.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消',
                style: TextStyle(color: context.colors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.movieEnd,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('覆盖恢复'),
          ),
        ],
      ),
    );
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('数据同步'),
        backgroundColor: c.background,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _SyncCard(
            lastSyncAt: sync.settings.lastSyncAt,
            isSyncing: sync.isSyncing,
            configured: sync.settings.isConfigured,
            onUpload: _onUpload,
            onRestore: _onRestoreFromCloud,
          ),
          const SizedBox(height: 24),
          _sectionTitle('WebDAV 服务器设置'),
          _ServerCard(
            urlCtrl: _urlCtrl,
            userCtrl: _userCtrl,
            passwordCtrl: _passwordCtrl,
            folderCtrl: _folderCtrl,
            passwordVisible: _passwordVisible,
            passwordLoaded: _passwordLoaded,
            onToggleVisible: () =>
                setState(() => _passwordVisible = !_passwordVisible),
            onTest: _onTestConnection,
          ),
          const SizedBox(height: 24),
          _sectionTitle('同步偏好'),
          _PrefsCard(
            autoSync: sync.settings.autoSync,
            onlyOnWifi: sync.settings.onlyOnWifi,
            includeImages: sync.settings.includeImages,
            onChanged: (auto, wifi, images) async {
              try {
                await sync.saveSettings(
                  _collectInput(
                    base: sync.settings.copyWith(
                      autoSync: auto,
                      onlyOnWifi: wifi,
                      includeImages: images,
                    ),
                  ),
                );
              } catch (e) {
                _toast('保存偏好失败：$e', error: true);
              }
            },
          ),
          const SizedBox(height: 24),
          _sectionTitle('本地备份'),
          _LocalCard(
            onExport: _onExportLocal,
            onImport: _onImportLocal,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: context.colors.textSecondary,
          ),
        ),
      );
}

/// 顶部云同步卡：上次同步时间 + 两个动作按钮
class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.lastSyncAt,
    required this.isSyncing,
    required this.configured,
    required this.onUpload,
    required this.onRestore,
  });

  final DateTime? lastSyncAt;
  final bool isSyncing;
  final bool configured;
  final VoidCallback onUpload;
  final VoidCallback onRestore;

  String get _syncLabel {
    final t = lastSyncAt;
    if (t == null) return '从未同步';
    String two(int n) => n.toString().padLeft(2, '0');
    return '上次同步：'
        '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_sync_rounded, size: 18, color: c.accent),
              const SizedBox(width: 8),
              Text(
                'WebDAV 云同步',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(_syncLabel,
              style: TextStyle(fontSize: 13, color: c.textSecondary)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: (isSyncing || !configured) ? null : onUpload,
                  icon: isSyncing
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.backup_rounded, size: 17),
                  label: const Text('立即备份'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.outline),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: (isSyncing || !configured) ? null : onRestore,
                  icon: const Icon(Icons.restore_rounded, size: 17),
                  label: const Text('从云端恢复'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 服务器设置卡（4 输入 + 测试连接）
class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.urlCtrl,
    required this.userCtrl,
    required this.passwordCtrl,
    required this.folderCtrl,
    required this.passwordVisible,
    required this.passwordLoaded,
    required this.onToggleVisible,
    required this.onTest,
  });

  final TextEditingController urlCtrl;
  final TextEditingController userCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController folderCtrl;
  final bool passwordVisible;
  final bool passwordLoaded;
  final VoidCallback onToggleVisible;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _field(
            context,
            controller: urlCtrl,
            label: '服务器地址',
            hint: '如 https://dav.jianguoyun.com/dav',
            keyboardType: TextInputType.url,
          ),
          _field(
            context,
            controller: userCtrl,
            label: '账号',
            hint: '登录账号或邮箱',
            keyboardType: TextInputType.emailAddress,
          ),
          _field(
            context,
            controller: passwordCtrl,
            label: '密码 / 应用授权码',
            hint: passwordLoaded ? '推荐使用网盘生成的应用专用密码' : '',
            obscure: !passwordVisible,
            suffix: IconButton(
              icon: Icon(
                passwordVisible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 19,
                color: c.textMuted,
              ),
              onPressed: onToggleVisible,
            ),
          ),
          _field(
            context,
            controller: folderCtrl,
            label: '云端存储目录',
            hint: SyncSettings.defaultRemoteFolder,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: c.accent,
                side: BorderSide(color: c.accent),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: onTest,
              icon: const Icon(Icons.wifi_tethering_rounded, size: 17),
              label: const Text('测试服务器连接'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
    TextInputType? keyboardType,
    Widget? suffix,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        autocorrect: false,
        enableSuggestions: false,
        style: TextStyle(color: c.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: c.textSecondary, fontSize: 13),
          hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
          suffixIcon: suffix,
          filled: true,
          fillColor: c.surfaceHigh,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: c.accent),
          ),
        ),
      ),
    );
  }
}

/// 同步偏好卡（3 开关；仅 Wi-Fi 跟随自动同步灰显）
class _PrefsCard extends StatelessWidget {
  const _PrefsCard({
    required this.autoSync,
    required this.onlyOnWifi,
    required this.includeImages,
    required this.onChanged,
  });

  final bool autoSync;
  final bool onlyOnWifi;
  final bool includeImages;
  final Future<void> Function(bool auto, bool wifi, bool images) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _row(
            context,
            icon: Icons.sync_rounded,
            title: '启动时自动同步',
            subtitle: '冷启动后静默上传一次备份',
            value: autoSync,
            onChanged: (v) => onChanged(v, onlyOnWifi, includeImages),
          ),
          _row(
            context,
            icon: Icons.wifi_rounded,
            title: '仅 Wi-Fi 下同步',
            subtitle: '自动同步时避开移动流量',
            value: onlyOnWifi,
            enabled: autoSync,
            onChanged: (v) => onChanged(autoSync, v, includeImages),
          ),
          _row(
            context,
            icon: Icons.image_rounded,
            title: '备份包含本地图片',
            subtitle: '含海报 / 头像，体积更大但还原完整',
            value: includeImages,
            onChanged: (v) => onChanged(autoSync, onlyOnWifi, v),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    final c = context.colors;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: Icon(icon, size: 20, color: c.accent),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: enabled ? c.textPrimary : c.textMuted,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: c.textMuted),
      ),
      trailing: Switch(
        value: value && enabled,
        onChanged: enabled ? (v) => onChanged(v) : null,
        activeColor: c.accent,
      ),
    );
  }
}

/// 本地备份卡（导出 / 导入，保底备选）
class _LocalCard extends StatelessWidget {
  const _LocalCard({required this.onExport, required this.onImport});

  final VoidCallback onExport;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          ListTile(
            leading:
                Icon(Icons.file_download_rounded, size: 20, color: c.accent),
            title: Text('导出备份到本地',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary)),
            subtitle: Text('选择保存位置；按「备份包含本地图片」开关打包 JSON / ZIP',
                style: TextStyle(fontSize: 12, color: c.textMuted)),
            trailing:
                Icon(Icons.chevron_right_rounded, size: 20, color: c.textMuted),
            onTap: onExport,
          ),
          Divider(height: 1, color: c.outline),
          ListTile(
            leading: Icon(Icons.file_upload_rounded, size: 20, color: c.accent),
            title: Text('从本地备份文件恢复',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary)),
            subtitle: Text('支持 .json / .zip 备份，覆盖前会二次确认',
                style: TextStyle(fontSize: 12, color: c.textMuted)),
            trailing:
                Icon(Icons.chevron_right_rounded, size: 20, color: c.textMuted),
            onTap: onImport,
          ),
        ],
      ),
    );
  }
}
