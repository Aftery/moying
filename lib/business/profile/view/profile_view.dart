import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../component/theme/app_palette.dart';
import '../../../component/media/model/media_ref.dart';
import '../../../foundation/constants/app_strings.dart';
import '../../stats/model/stats.dart';
import '../model/user_profile.dart';
import '../../library/view_model/library_provider.dart';
import '../../../component/media/media_cover.dart';

class ThemeModeLabel extends StatelessWidget {
  const ThemeModeLabel({super.key, required this.mode});

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

/// 档案卡（头像 + 昵称 + 签名，点击只读展示；编辑走「编辑资料」设置行）
class ProfileCard extends StatelessWidget {
  const ProfileCard({super.key, required this.profile, required this.onTap});

  final UserProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: onTap,
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

class StatSummary extends StatelessWidget {
  const StatSummary({super.key, required this.bookStats, required this.movieStats});

  final BookStats bookStats;
  final MovieStats movieStats;

  @override
  Widget build(BuildContext context) {
    final b = bookStats;
    final m = movieStats;
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

class SettingItem extends StatelessWidget {
  const SettingItem({super.key,
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
class ProfileEditResult {
  const ProfileEditResult({
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

class ProfileEditSheet extends StatefulWidget {
  const ProfileEditSheet({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends State<ProfileEditSheet> {
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 24, 20 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 拖拽指示条
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: context.colors.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 标题
              Text(
                AppStrings.editProfile,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              // ---------- 头像区 ----------
              Row(
                children: [
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _nicknameCtrl,
                    builder: (_, value, __) {
                      final name = value.text.trim();
                      return SizedBox(
                        width: 56,
                        height: 56,
                        child: MediaCover(
                          circular: true,
                          media: _previewAvatar,
                          pendingFile: _picked,
                          title: name.isEmpty ? '书友' : name,
                          hue: 262,
                          fontSize: 24,
                        ),
                      );
                    },
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
                            foregroundColor: context.colors.danger,
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
                onChanged: (_) {
                  if (_picked != null) setState(() => _picked = null);
                },
                style:
                    TextStyle(color: context.colors.textPrimary, fontSize: 13),
                cursorColor: context.colors.accent,
                decoration: _dec(AppStrings.networkAvatarUrl, 'https://…（可选）'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nicknameCtrl,
                style:
                    TextStyle(color: context.colors.textPrimary, fontSize: 15),
                cursorColor: context.colors.accent,
                decoration: _dec('昵称', '怎么称呼你'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _signatureCtrl,
                minLines: 2,
                maxLines: 4,
                style:
                    TextStyle(color: context.colors.textPrimary, fontSize: 14),
                cursorColor: context.colors.accent,
                decoration: _dec('个性签名', '一句话签名（可选）'),
              ),
              const SizedBox(height: 20),
              // 按钮行
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        backgroundColor: context.colors.surface,
                        foregroundColor: context.colors.textMuted,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('取消',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(
                          ProfileEditResult(
                        nickname: _nicknameCtrl.text,
                        signature: _signatureCtrl.text,
                        avatarFile: _picked,
                        avatarUrl: _avatarUrlCtrl.text.trim(),
                        avatarTouched: _avatarTouched,
                      )),
                      style: TextButton.styleFrom(
                        backgroundColor: context.colors.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('保存',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
