import 'package:flutter/material.dart';

import '../config/app_colors.dart';

/// 暗色圆角搜索栏（图书列表页顶部）
///
/// - 实时回调 [onChanged]（输入清空/变化均触发）
/// - 有内容时显示清除按钮
class SearchBarWidget extends StatelessWidget {
  const SearchBarWidget({
    super.key,
    required this.onChanged,
    this.hintText = '搜索书名或作者…',
    this.controller,
  });

  /// 输入变化回调（含清除）
  final ValueChanged<String> onChanged;

  /// 占位提示文案
  final String hintText;

  /// 外部控制器（可选，编辑时用于外部重置）
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 14,
      ),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
        prefixIcon: const Icon(
          Icons.search_rounded,
          color: AppColors.textMuted,
          size: 22,
        ),
        // 清除按钮（无内容时不占位）
        suffixIcon: controller != null
            ? ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller!,
                builder: (_, value, __) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textMuted,
                          size: 20,
                        ),
                        onPressed: () {
                          controller!.clear();
                          onChanged('');
                        },
                      ),
              )
            : null,
        filled: true,
        fillColor: AppColors.surfaceHigh,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.outline, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
        ),
      ),
    );
  }
}
