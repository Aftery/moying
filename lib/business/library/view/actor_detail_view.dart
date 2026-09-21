import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../component/theme/app_palette.dart';
import '../../../component/media/model/media_ref.dart';
import '../../../foundation/constants/app_strings.dart';
import '../view_model/library_provider.dart';
import '../../../component/media/media_cover.dart';

class ActorEditResult {
  const ActorEditResult({
    required this.name,
    required this.bio,
    this.avatarFile,
    this.avatarUrl = '',
    required this.avatarTouched,
  });

  final String name;
  final String bio;

  /// 从相册选中的本地头像（未落盘，由调用方复制进 images/）
  final File? avatarFile;

  /// 网络头像地址
  final String avatarUrl;

  /// 头像是否被用户动过（选图 / 填 URL / 清除）——true 时用新头像覆盖
  final bool avatarTouched;
}

/// 演员资料编辑弹层：输入控制器由自身 State 持有，
/// 随弹层 route 销毁统一释放，避免过早 dispose。
class ActorEditDialog extends StatefulWidget {
  const ActorEditDialog({super.key,
    required this.name,
    required this.bio,
    this.avatar,
    required this.hue,
  });

  final String name;
  final String bio;

  /// 原头像（未动过时预览用）
  final MediaRef? avatar;

  /// 占位渐变 hue（页面按姓名计算后传入）
  final double hue;

  @override
  State<ActorEditDialog> createState() => _ActorEditDialogState();
}

class _ActorEditDialogState extends State<ActorEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _avatarUrlCtrl;

  /// 从相册选中的本地图（保存时由调用方 attach）
  File? _picked;

  /// 用户显式点了「清除头像」（把 localFile 头像也归入可清除范围）
  bool _cleared = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.name);
    _bioCtrl = TextEditingController(text: widget.bio);
    _avatarUrlCtrl = TextEditingController(
        text: widget.avatar?.remoteUrl ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _avatarUrlCtrl.dispose();
    super.dispose();
  }

  /// 头像是否被改动过（决定保存时覆盖原头像还是原样保留）：
  /// 选中本地图 / 显式清除 / URL 文本与原网络图不同，任一即视为改动。
  bool get _avatarTouched {
    if (_picked != null || _cleared) return true;
    final url = _avatarUrlCtrl.text.trim();
    if (url.isEmpty) return false;
    return url != widget.avatar?.remoteUrl;
  }

  /// 预览输入：选中本地图 → [MediaCover.pendingFile] 优先；
  /// URL 非空 → 网络；否则回到原头像。
  MediaRef? get _previewAvatar {
    if (_picked != null) return null;
    final url = _avatarUrlCtrl.text.trim();
    if (url.isNotEmpty) return MediaRef.network(url);
    return widget.avatar;
  }

  bool get _canPick =>
      context.read<LibraryProvider>().canPickImage;

  Future<void> _pickFromGallery() async {
    final lib = context.read<LibraryProvider>();
    final picked = await lib.pickImageFile();
    if (picked == null || !mounted) return;
    setState(() {
      _picked = picked;
      _avatarUrlCtrl.clear();
    });
  }

  InputDecoration _dec(String label, String hint) {
    return InputDecoration(
      labelText: label,
      labelStyle:  TextStyle(color: context.colors.textMuted, fontSize: 13),
      hintText: hint,
      hintStyle:  TextStyle(color: context.colors.textMuted, fontSize: 13),
      filled: true,
      fillColor: context.colors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:  BorderSide(color: context.colors.outline, width: 0.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:  BorderSide(color: context.colors.outline, width: 0.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:  BorderSide(color: context.colors.accent, width: 1.2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surfaceHigh,
      title:  Text(
        '编辑演员资料',
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
            _buildAvatarSection(context),
            const SizedBox(height: 6),
            _buildUrlField(context),
            const SizedBox(height: 10),
            _buildNameField(context),
            const SizedBox(height: 10),
            _buildBioField(context),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child:
               Text('取消', style: TextStyle(color: context.colors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(ActorEditResult(
            name: _nameCtrl.text,
            bio: _bioCtrl.text,
            avatarFile: _picked,
            avatarUrl: _avatarUrlCtrl.text.trim(),
            avatarTouched: _avatarTouched,
          )),
          child:  Text(
            '保存',
            style: TextStyle(
                color: context.colors.accent, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  /// 头像区：预览 + 从相册选择 / 清除头像（含姓名 ValueListenable 重建预览）
  Widget _buildAvatarSection(BuildContext context) {
    return Row(
      children: [
        // H4：只重建头像预览，姓名输入不再重建整个 Dialog
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _nameCtrl,
          builder: (_, value, __) {
            final name = value.text.trim();
            return SizedBox(
              width: 56,
              height: 56,
              child: MediaCover(
                circular: true,
                media: _previewAvatar,
                pendingFile: _picked,
                title: name.isEmpty ? '演员' : name,
                hue: widget.hue,
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
    );
  }

  /// 头像 URL 输入框（与本地图互斥，仅在真有本地图时重建一次）
  Widget _buildUrlField(BuildContext context) {
    return TextField(
      controller: _avatarUrlCtrl,
      keyboardType: TextInputType.url,
      // H4：URL 与本地图互斥（URL 优先）。仅在真有本地图时重建一次，
      // 后续每个字符不再触发整页 setState。
      onChanged: (_) {
        if (_picked != null) setState(() => _picked = null);
      },
      style:
           TextStyle(color: context.colors.textPrimary, fontSize: 13),
      cursorColor: context.colors.accent,
      decoration: _dec(AppStrings.networkAvatarUrl, 'https://…（可选）'),
    );
  }

  /// 姓名输入框
  Widget _buildNameField(BuildContext context) {
    return TextField(
      controller: _nameCtrl,
      style:  TextStyle(color: context.colors.textPrimary, fontSize: 15),
      cursorColor: context.colors.accent,
      decoration: _dec('姓名', '演员姓名'),
    );
  }

  /// 简介输入框（2~4 行）
  Widget _buildBioField(BuildContext context) {
    return TextField(
      controller: _bioCtrl,
      minLines: 2,
      maxLines: 4,
      style:
           TextStyle(color: context.colors.textPrimary, fontSize: 14),
      cursorColor: context.colors.accent,
      decoration: _dec('简介', '一句话介绍 TA（可选）'),
    );
  }
}
