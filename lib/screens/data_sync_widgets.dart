part of 'data_sync_page.dart';

class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.lastSyncAt,
    required this.isSyncing,
    required this.configured,
    required this.onUpload,
    required this.onRestore,
    this.mergeSummary,
  });

  final DateTime? lastSyncAt;
  final bool isSyncing;
  final bool configured;
  final VoidCallback onUpload;
  final VoidCallback onRestore;

  /// 最近一次合并摘要（null = 无合并发生或尚未同步过）
  final String? mergeSummary;

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
          if (mergeSummary != null) ...[
            const SizedBox(height: 4),
            Text(mergeSummary!,
                style: TextStyle(
                    fontSize: 12, color: c.textSecondary.withOpacity(0.8))),
          ],
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
