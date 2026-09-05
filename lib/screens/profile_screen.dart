import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../models/media_ref.dart';
import '../models/user_profile.dart';
import '../providers/library_provider.dart';
import '../widgets/media_cover.dart';
import 'personal_stats_screen.dart';

/// 个人中心 —— 档案（昵称/签名/头像）、主题偏好、个人统计入口
///
/// 档案与主题偏好均持久化于 profile.json（单例集合）；
/// 编辑弹层交互与演员资料编辑（actor_detail_screen）同构。
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('个人')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 头像 + 昵称（点击即编辑）
          _ProfileCard(
            profile: library.userProfile,
            onEdit: () => _openProfileEditor(context, library),
          ),
          const SizedBox(height: 20),

          // 年度统计摘要
          _StatSummary(library: library),
          const SizedBox(height: 24),

          // 设置入口
          _SettingItem(
            icon: Icons.edit_note_rounded,
            label: '编辑资料',
            onTap: () => _openProfileEditor(context, library),
          ),
          _SettingItem(
            icon: Icons.data_usage_rounded,
            label: '数据统计',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PersonalStatsScreen()),
            ),
          ),
          _SettingItem(
            icon: Icons.dark_mode_rounded,
            label: '深色模式',
            trailing: _ThemeModeLabel(mode: library.themeMode),
            onTap: () => _chooseThemeMode(context, library),
          ),
          _SettingItem(
            icon: Icons.sync_rounded,
            label: '数据同步',
            trailing: Text('即将上线',
                style: TextStyle(
                    fontSize: 12, color: context.colors.textMuted)),
          ),
          const SizedBox(height: 32),
          Text(
            '墨影 · v0.1.0\n一个正在成长的书籍与电影记录应用',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: context.colors.textMuted.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 编辑资料（弹层：昵称 / 签名 / 换头像）----------

  Future<void> _openProfileEditor(
    BuildContext context,
    LibraryProvider lib,
  ) async {
    final profile = lib.userProfile;
    final messenger = ScaffoldMessenger.of(context);
    // 编辑弹层自管输入控制器生命周期（随 route 销毁释放），
    // 规避「pop 退出动画未结束即 dispose controller」的 framework 断言。
    final result = await showDialog<_ProfileEditResult>(
      context: context,
      builder: (_) => _ProfileEditDialog(profile: profile),
    );
    if (result == null || !context.mounted) return;
    final nickname = result.nickname.trim();
    if (nickname.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('昵称不能为空')));
      return;
    }
    final signature = result.signature.trim();
    final base = profile.copyWith(
      nickname: nickname,
      signature: signature.isEmpty ? null : signature,
    );
    if (!result.avatarTouched) {
      await lib.updateProfile(base);
      return;
    }
    // 头像被改动：本地图先复制落盘 → local；URL → network；否则移除(null)
    MediaRef? avatar;
    final picked = result.avatarFile;
    if (picked != null) {
      // 单例档案：固定 entryId 'profile'，copyImage 同名覆盖天然回收旧图
      final rel = await lib.attachImage(picked, 'profile');
      avatar = rel == null ? null : MediaRef.local(rel);
    } else if (result.avatarUrl.isNotEmpty) {
      avatar = MediaRef.network(result.avatarUrl);
    }
    await lib.updateProfile(base.copyWith(avatar: avatar));
  }

  // ---------- 深色模式（三选：深色 / 浅色 / 跟随系统）----------

  Future<void> _chooseThemeMode(
    BuildContext context,
    LibraryProvider lib,
  ) async {
    final current = lib.themeMode;
    const options = [
      ('dark', '深色', Icons.dark_mode_rounded),
      ('light', '浅色', Icons.light_mode_rounded),
      ('system', '跟随系统', Icons.settings_brightness_rounded),
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            for (final (mode, label, icon) in options)
              ListTile(
                leading: Icon(icon, color: context.colors.accent, size: 22),
                title: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
                trailing: current == mode
                    ? Icon(Icons.check_rounded,
                        color: context.colors.accent, size: 20)
                    : null,
                onTap: () => Navigator.of(ctx).pop(mode),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null && selected != current) {
      await lib.setThemeMode(selected);
    }
  }
}

/// 主题偏好当前值标签（设置行 trailing）
class _ThemeModeLabel extends StatelessWidget {
  const _ThemeModeLabel({required this.mode});

  final String mode;

  @override
  Widget build(BuildContext context) {
    final text = switch (mode) {
      'light' => '浅色',
      'system' => '跟随系统',
      _ => '深色',
    };
    return Text(
      text,
      style: TextStyle(fontSize: 12, color: context.colors.textMuted),
    );
  }
}

/// 档案卡（头像 + 昵称 + 签名，点击编辑）
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.onEdit});

  final UserProfile profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: MediaCover(
                circular: true,
                media: profile.avatar,
                title: profile.nickname,
                hue: 262,
                fontSize: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile.signature ?? '读万卷书 · 行万里路',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: context.colors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _StatSummary extends StatelessWidget {
  const _StatSummary({required this.library});

  final LibraryProvider library;

  @override
  Widget build(BuildContext context) {
    final b = library.bookStats;
    final m = library.movieStats;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '我的年度记录',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatCell(value: '${b.finished}', label: '读完书籍'),
              _StatCell(value: '${m.rated}', label: '看过电影'),
              _StatCell(value: '${b.pagesRead}', label: '阅读页数'),
              _StatCell(value: '${m.total}', label: '观影总数'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: context.colors.accent,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.colors.textMuted),
        ),
      ],
    );
  }
}

class _SettingItem extends StatelessWidget {
  const _SettingItem({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onTap,
        leading: Icon(icon, color: context.colors.accent, size: 22),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        trailing: trailing ??
            Icon(Icons.chevron_right_rounded,
                color: context.colors.textMuted),
      ),
    );
  }
}

// ==================== 编辑资料弹层 ====================

/// 编辑结果（弹层 → 保存流程的数据载体）
class _ProfileEditResult {
  const _ProfileEditResult({
    required this.nickname,
    required this.signature,
    this.avatarFile,
    this.avatarUrl = '',
    required this.avatarTouched,
  });

  final String nickname;
  final String signature;

  /// 从相册选中的本地头像（未落盘，由调用方复制进 images/）
  final File? avatarFile;

  /// 网络头像链接（与本地图互斥，URL 优先）
  final String avatarUrl;

  /// 头像是否被改动（未改动时调用方跳过头像处理分支）
  final bool avatarTouched;
}

class _ProfileEditDialog extends StatefulWidget {
  const _ProfileEditDialog({required this.profile});

  final UserProfile profile;

  @override
  State<_ProfileEditDialog> createState() => _ProfileEditDialogState();
}

class _ProfileEditDialogState extends State<_ProfileEditDialog> {
  late final TextEditingController _nicknameCtrl;
  late final TextEditingController _signatureCtrl;
  late final TextEditingController _avatarUrlCtrl;

  /// 从相册选中的本地图（保存时由调用方 attach）
  File? _picked;

  /// 是否点了「清除头像」（与 URL 输入互斥）
  bool _cleared = false;

  bool get _canPick => context.read<LibraryProvider>().canPickImage;

  /// 头像是否被改动：选了本地图 / 显式清除 / 输入了不同 URL
  bool get _avatarTouched {
    if (_picked != null || _cleared) return true;
    final url = _avatarUrlCtrl.text.trim();
    return url != (widget.profile.avatar?.remoteUrl ?? '');
  }

  /// 头像预览输入：编辑态未改动 → 原头像；动过后 → URL 文本（网络）或空（占位）
  MediaRef? get _previewAvatar {
    if (_picked != null || _cleared) return null;
    final url = _avatarUrlCtrl.text.trim();
    if (url.isNotEmpty) return MediaRef.network(url);
    return widget.profile.avatar;
  }

  @override
  void initState() {
    super.initState();
    _nicknameCtrl = TextEditingController(text: widget.profile.nickname);
    _signatureCtrl =
        TextEditingController(text: widget.profile.signature ?? '');
    _avatarUrlCtrl =
        TextEditingController(text: widget.profile.avatar?.remoteUrl ?? '');
  }

  @override
  void dispose() {
    _nicknameCtrl.dispose();
    _signatureCtrl.dispose();
    _avatarUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    final lib = context.read<LibraryProvider>();
    final picked = await lib.pickImageFile();
    if (picked == null || !mounted) return;
    setState(() {
      _picked = picked;
      _cleared = false;
      _avatarUrlCtrl.clear();
    });
  }

  InputDecoration _dec(String label, String hint) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: context.colors.textMuted, fontSize: 13),
      hintText: hint,
      hintStyle: TextStyle(color: context.colors.textMuted, fontSize: 13),
      filled: true,
      fillColor: context.colors.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.colors.outline, width: 0.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.colors.outline, width: 0.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: context.colors.accent, width: 1.2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewName =
        _nicknameCtrl.text.trim().isEmpty ? '书友' : _nicknameCtrl.text.trim();
    return AlertDialog(
      backgroundColor: context.colors.surfaceHigh,
      title: Text(
        '编辑资料',
        style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------- 头像区 ----------
            Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: MediaCover(
                    circular: true,
                    media: _previewAvatar,
                    pendingFile: _picked,
                    title: previewName,
                    hue: 262,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_canPick)
                        TextButton.icon(
                          onPressed: _pickFromGallery,
                          style: TextButton.styleFrom(
                            foregroundColor: context.colors.textSecondary,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 36),
                          ),
                          icon: const Icon(Icons.photo_library_outlined,
                              size: 17),
                          label: const Text('从相册选择',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _cleared = true;
                          _picked = null;
                          _avatarUrlCtrl.clear();
                        }),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFF6B6B),
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 36),
                        ),
                        icon: const Icon(Icons.image_not_supported_outlined,
                            size: 16),
                        label: const Text('清除头像',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _avatarUrlCtrl,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {
                // 一旦输入 URL，丢弃已选本地图（两者互斥，URL 优先）
                _picked = null;
              }),
              style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
              cursorColor: context.colors.accent,
              decoration: _dec('网络头像链接', 'https://…（可选）'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nicknameCtrl,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: context.colors.textPrimary, fontSize: 15),
              cursorColor: context.colors.accent,
              decoration: _dec('昵称', '怎么称呼你'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _signatureCtrl,
              minLines: 2,
              maxLines: 4,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
              cursorColor: context.colors.accent,
              decoration: _dec('个性签名', '一句话签名（可选）'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: context.colors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ProfileEditResult(
            nickname: _nicknameCtrl.text,
            signature: _signatureCtrl.text,
            avatarFile: _picked,
            avatarUrl: _avatarUrlCtrl.text.trim(),
            avatarTouched: _avatarTouched,
          )),
          child: Text(
            '保存',
            style: TextStyle(
                color: context.colors.accent, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
