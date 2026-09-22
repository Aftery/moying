import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// 底部弹层顶部拖拽指示条（36×4 圆条）
///
/// 收敛自 6 处逐字重复实现（cast_bottom_sheet / profile_page ×2 /
/// profile_view / data_source_guide_sheet / data_source_view），
/// 视觉完全一致：`outline` 色、36×4、圆角 2。差异只有外边距——
/// 不同弹层与后续内容的留白不同，用 [margin] 覆盖默认值。
///
/// 组件本体**不带 Center**：各弹层父级 Column 的对齐方式不同
/// （如编辑资料弹层为 `CrossAxisAlignment.start`），需要居中的调用方
/// 自行包 `Center`，保持行为零变更。
class SheetGrabber extends StatelessWidget {
  const SheetGrabber(
      {super.key, this.margin = const EdgeInsets.only(bottom: 16)});

  /// 外边距。默认 `bottom: 16`；弹层自带顶部留白的场景
  /// 传 `EdgeInsets.only(top: 10, bottom: …)` 覆盖。
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: margin,
      decoration: BoxDecoration(
        color: context.colors.outline,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
