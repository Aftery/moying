import 'package:flutter/material.dart';
import 'package:moying/config/app_palette.dart';

/// 通用筛选项
class FilterItem<T> {
  const FilterItem({required this.label, required this.value});

  final String label;
  final T value;
}

/// 下拉筛选组件（适配深浅主题与 ThemeExtension）
///
/// [onChanged] 用 [ValueChanged<T?>]：「全部」项的 value 就是 null（T 以可空类型
/// 实例化，如 BookStatus? / String?），必须允许 null 回传——此处加非空 guard 会导致
/// 「选不回全部」问题。
class FilterDropdown<T> extends StatelessWidget {
  const FilterDropdown({
    super.key,
    required this.icon,
    required this.items,
    required this.onChanged,
    required this.value,
  });

  final IconData icon;
  final List<FilterItem<T>> items;
  final ValueChanged<T?> onChanged;
  final T value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: context.colors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.outline, width: 0.8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            isDense: true,
            dropdownColor: context.colors.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            icon: Icon(Icons.expand_more_rounded,
                color: context.colors.textSecondary),
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            items: [
              for (final item in items)
                DropdownMenuItem<T>(
                  value: item.value,
                  child: Row(
                    children: [
                      Icon(icon, size: 16, color: context.colors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            // 直接回调：「全部」项的 value 就是 null，不能加非空 guard（否则选不回全部）。
            // DropdownButton 仅在真正选中菜单项时触发 onChanged，dismiss 不会回调。
            onChanged: (v) => onChanged(v),
          ),
        ),
      ),
    );
  }
}
