import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/config/app_palette.dart';

/// 交互式五星评分选择器（书籍编辑页使用）
///
/// 两种手势都支持，且都会给触感反馈：
/// - **点击**第 N 颗星 → 评分为 N（整数档位）；再点当前选中档 → 清除（0 = 未评分）
/// - **左右拖动**划过星星 → 连续改档，**每跨一档震一次**
///   （[HapticFeedback.selectionClick]，最轻的一档 —— 不打字、不打扰，
///   但「拖到几分」有明确的落点手感）
///
/// 触感只在**档位真正变化**时触发：手指按下、原地抖动、拖到同一档内
/// 都不会震，避免连续蜂鸣式的廉价感。
class StarRatingPicker extends StatefulWidget {
  const StarRatingPicker({
    super.key,
    required this.rating,
    required this.onChanged,
    this.size = 34,
    this.haptics = true,
  });

  /// 当前评分 0-5（0 表示未评分）
  final double rating;

  /// 评分变化回调（传 0 表示清除）
  final ValueChanged<double> onChanged;

  /// 单颗星尺寸
  final double size;

  /// 是否触发触感反馈。
  /// 单测环境可关掉（`HapticFeedback` 走平台通道，测试里无人接收）。
  final bool haptics;

  @override
  State<StarRatingPicker> createState() => _StarRatingPickerState();
}

class _StarRatingPickerState extends State<StarRatingPicker> {
  /// 拖动中的实时档位；< 0 表示未在拖动（此时以 [StarRatingPicker.rating] 渲染）。
  ///
  /// 拖动期间用本地值渲染，不依赖父级 setState 回灌 —— 否则手指还在移动、
  /// 父级尚未重建时星星会闪回旧档位。
  double _dragging = -1;

  double get _value => _dragging >= 0 ? _dragging : widget.rating;

  /// 单颗星的触控槽宽（图标 + 左右各 5 的间距）——拖动时按 x 坐标换算档位
  double get _slotWidth => widget.size + 10;

  /// 落定一个档位：变化才回调 + 震动
  void _commit(double value) {
    if (value == _value) return;
    setState(() => _dragging = value);
    widget.onChanged(value);
    _vibrate();
  }

  /// 拖动点 → 档位 1..5（越界钳制：左半区记 1，右半区记 5）
  void _dragTo(double dx) {
    final index = (dx / _slotWidth).floor() + 1;
    _commit(index.clamp(1, 5).toDouble());
  }

  void _endDrag() {
    if (_dragging >= 0) setState(() => _dragging = -1);
  }

  /// selectionClick：最轻的一档触感，跨档时逐次触发
  void _vibrate() {
    if (!widget.haptics) return;
    unawaited(HapticFeedback.selectionClick());
  }

  @override
  Widget build(BuildContext context) {
    final rounded = _value.round();

    return Center(
      child: GestureDetector(
        // opaque：星星之间的 5px 间隙也要能起拖，否则手感断断续续
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => _dragTo(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => _dragTo(d.localPosition.dx),
        onHorizontalDragEnd: (_) => _endDrag(),
        onHorizontalDragCancel: _endDrag,
        child: Row(
          // min：让手势框正好包住五颗星，localPosition.dx 才能直接换算档位
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 5; i++)
              // 触控热区保证 ≥ 44dp（Material 无障碍要求）
              SizedBox(
                width: _slotWidth,
                height: _slotWidth,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  splashRadius: widget.size * 0.6,
                  tooltip: '$i 分',
                  onPressed: () {
                    _dragging = -1;
                    final next = rounded == i ? 0.0 : i.toDouble();
                    // 点击落到当前档 = 清除；档位变了才震（与拖动同一口径）
                    if (next != widget.rating) {
                      widget.onChanged(next);
                      _vibrate();
                    }
                    setState(() {});
                  },
                  icon: Icon(
                    i <= rounded
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: widget.size,
                    color: i <= rounded
                        ? context.colors.star
                        : context.colors.textMuted.withOpacity(0.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
