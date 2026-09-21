import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../component/theme/app_palette.dart';
import '../../../foundation/constants/app_strings.dart';
import '../model/sync_settings.dart';
import '../../data_source/view_model/data_source_provider.dart';
import '../view_model/sync_provider.dart';
import '../service/backup_service.dart';
import '../service/merge_engine.dart';
import '../service/webdav_client.dart';
import '../view/data_sync_view.dart';

/// 数据同步页 —— WebDAV 云同步 + 本地导出/导入（P5）
///
/// 结构对齐设计稿：云同步卡（上次同步 + 立即备份 / 从云端恢复）→
/// 服务器设置（4 输入 + 测试连接）→ 同步偏好（3 开关）→ 本地备份（导出 / 导入）。
class DataSyncPage extends StatefulWidget {
  const DataSyncPage({super.key});

  @override
  State<DataSyncPage> createState() => _DataSyncPageState();
}

class _DataSyncPageState extends State<DataSyncPage> {
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
    } on Object catch (e) {
      _toast('测试连接失败：$e', error: true);
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
    } on Object catch (e) {
      _toast('上传备份失败：$e', error: true);
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
    } on Object catch (e) {
      _toast('云端恢复失败：$e', error: true);
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
    } on Object catch (e) {
      _toast(AppStrings.exportFailed(e), error: true);
    }
  }

  Future<void> _onImportLocal() async {
    final sync = context.read<SyncProvider>();
    // M9：不一次性 bytes 全加载；改为 withData:false 取 path +
    // 磁盘流式读，避免 50MB+ 大文件被全量复制到内存
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'zip'],
      withData: false,
    );
    final file = picked?.files.singleOrNull;
    if (file?.path == null) return; // 用户取消
    final path = file!.path!;
    const maxBytes = 50 * 1024 * 1024;
    final size = await File(path).length();
    if (size > maxBytes) {
      _toast('备份文件超过 50 MB，无法导入', error: true);
      return;
    }
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on Object catch (e) {
      _toast('读取备份文件失败：$e', error: true);
      return;
    }
    try {
      final pending = await sync.parseLocalBackup(bytes);
      if (!mounted) return;
      final confirmed =
          await _confirmRestore(pending.manifest, source: pending.fileName);
      if (confirmed != true || !mounted) return;
      await sync.confirmRestore(pending);
      _toast('已从本地文件恢复');
      await _afterRestoreReload();
    } on BackupException catch (e) {
      _toast(e.message, error: true);
    } on Object catch (e) {
      _toast('本地恢复失败：$e', error: true);
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
          SyncCard(
            lastSyncAt: sync.settings.lastSyncAt,
            isSyncing: sync.isSyncing,
            configured: sync.settings.isConfigured,
            onUpload: _onUpload,
            onRestore: _onRestoreFromCloud,
            mergeSummary: _mergeSummary(sync.lastMerge),
          ),
          const SizedBox(height: 24),
          _sectionTitle('WebDAV 服务器设置'),
          ServerCard(
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
          PrefsCard(
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
          LocalCard(
            onExport: _onExportLocal,
            onImport: _onImportLocal,
          ),
        ],
      ),
    );
  }

  /// 合并统计摘要（null → 不显示该行）
  String? _mergeSummary(MergeResult? merge) {
    if (merge == null || !merge.hasChanges) return null;
    return '本次合并：${merge.fromRemote} 条来自云端'
        ' · ${merge.localKept} 条本地保留'
        ' · ${merge.localOnly} 条并入';
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

/// 顶部云同步卡：上次同步时间（含合并统计）+ 两个动作按钮
