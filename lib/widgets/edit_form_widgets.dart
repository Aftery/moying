import 'package:flutter/material.dart';
import 'package:moying/config/app_palette.dart';

/// 编辑页分组标题
class EditSectionTitle extends StatelessWidget {
  const EditSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.colors.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// 编辑页通用输入框
class EditInputField extends StatelessWidget {
  const EditInputField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.suffixText,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;
  final FocusNode? focusNode;
  /// 后缀文字（如 '分钟'）；suffixText 与 suffixIcon 二选一，
  /// suffixText 会自动靠右对齐，无需额外 Padding。
  final String? suffixText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: onChanged,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      focusNode: focusNode,
      style: TextStyle(color: context.colors.textPrimary, fontSize: 15),
      cursorColor: context.colors.accent,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.colors.textMuted, fontSize: 13),
        hintText: hint,
        hintStyle: TextStyle(color: context.colors.textMuted, fontSize: 14),
        filled: true,
        fillColor: context.colors.surfaceHigh,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        suffixText: suffixText,
        suffixStyle:
            TextStyle(color: context.colors.textMuted.withOpacity(0.8), fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.colors.outline, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.colors.outline, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: context.colors.accent, width: 1.3),
        ),
      ),
    );
  }
}

/// 底部封面/海报操作菜单（从相册选择、粘贴链接、移除）
Future<String?> showCoverActionSheet({
  required BuildContext context,
  required bool canPickImage,
  String removeLabel = '移除封面',
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: context.colors.surfaceHigh,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canPickImage)
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: context.colors.textSecondary),
              title: Text('从相册选择',
                  style: TextStyle(color: context.colors.textPrimary)),
              onTap: () => Navigator.of(ctx).pop('pick'),
            ),
          ListTile(
            leading:
                Icon(Icons.link_rounded, color: context.colors.textSecondary),
            title: Text('粘贴网络图片链接',
                style: TextStyle(color: context.colors.textPrimary)),
            onTap: () => Navigator.of(ctx).pop('url'),
          ),
          ListTile(
            leading: Icon(Icons.image_not_supported_outlined,
                color: context.colors.danger),
            title:
                Text(removeLabel, style: TextStyle(color: context.colors.danger)),
            onTap: () => Navigator.of(ctx).pop('remove'),
          ),
        ],
      ),
    ),
  );
}
