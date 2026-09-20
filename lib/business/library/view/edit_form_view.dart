import 'package:flutter/material.dart';
import 'package:moying/app/config/app_palette.dart';

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
  bool canLookup = false,
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
          if (canLookup)
            ListTile(
              leading: Icon(Icons.travel_explore_rounded,
                  color: context.colors.textSecondary),
              title: Text('联网自动找封面',
                  style: TextStyle(color: context.colors.textPrimary)),
              subtitle: Text('按 ISBN / 书名检索一次数据源',
                  style: TextStyle(
                      color: context.colors.textMuted, fontSize: 12)),
              onTap: () => Navigator.of(ctx).pop('lookup'),
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

/// 单行文本输入对话框（返回输入值；取消返回 null；[allowClear] 时多一个「清除」返回空串）
///
/// controller 由对话框**自身**持有并在 `dispose()` 中释放，而不是在
/// `showDialog` 返回后释放：`showDialog` 的 future 在路由 pop 时即完成，
/// 但对话框此时还在退场动画里、`TextField` 会重建并重新 `addListener`，
/// 提前释放会抛 `A TextEditingController was used after being disposed.`
/// （`media_pipeline_test` 已实测复现）。交给 State 持有才能保证释放时机
/// 落在子树真正 unmount 之后。
class TextPromptDialog extends StatefulWidget {
  const TextPromptDialog({
    super.key,
    required this.title,
    required this.initial,
    this.keyboardType,
    this.hint,
    this.allowClear = false,
  });

  final String title;
  final String initial;
  final TextInputType? keyboardType;
  final String? hint;
  final bool allowClear;

  @override
  State<TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<TextPromptDialog> {
  late final TextEditingController _ctrl;
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
    _ctrl = TextEditingController(text: widget.initial)
      ..selection = TextSelection.collapsed(offset: widget.initial.length);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surfaceHigh,
      title: Text(
        widget.title,
        style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700),
      ),
      content: TextField(
        autofocus: true,
        keyboardType: widget.keyboardType,
        controller: _ctrl,
        style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
        cursorColor: context.colors.accent,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(color: context.colors.textMuted, fontSize: 13),
          filled: true,
          fillColor: context.colors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: context.colors.outline, width: 0.8),
          ),
        ),
        onChanged: (s) => _value = s,
        onSubmitted: (s) => Navigator.of(context).pop(s),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: context.colors.textMuted)),
        ),
        if (widget.allowClear && widget.initial.trim().isNotEmpty)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(
              '清除',
              style: TextStyle(
                  color: context.colors.danger, fontWeight: FontWeight.w700),
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_value),
          child: Text(
            '确定',
            style: TextStyle(
                color: context.colors.accent, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
