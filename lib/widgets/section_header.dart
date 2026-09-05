import 'package:flutter/material.dart';

import '../config/app_palette.dart';

/// 区块标题（主标题 + 可选副标题/操作）
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  /// 区块标题文字
  final String title;

  /// 右侧操作区（如 “查看全部”）
  final Widget? trailing;

  /// 外边距
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              gradient: context.colors.readingGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style:  TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          if (trailing != null)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {},
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: DefaultTextStyle.merge(
                  style:  TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.colors.accent,
                  ),
                  child: trailing!,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
