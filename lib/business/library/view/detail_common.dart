import 'package:flutter/material.dart';

import '../../../component/theme/app_palette.dart';

/// 分类 / 出版社等「小胶囊」标签（图书与影视详情页共用）
///
/// 抽到公共组件的动因：详情页曾各自持有一份逐字重复的实现，
/// 颜色或圆角一改就要改两处。
class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.outline, width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 内容简介文本块：超过 4 行自动折叠，提供「展开全部 / 收起」
///
/// **折叠判定**：用 [TextPainter] 预排版测量是否溢出，结果按
/// 「文本 + 可用宽度」缓存；测量不在 build 阶段同步执行，而是交给
/// postFrame 调度——避免长简介下每次 rebuild 都触发一次排版
/// （调度去重 + 宽度缓存，见 `_measureScheduled` / `_lastWidth`）。
///
/// **[boxed]** 决定是否自带描边卡片容器：
/// - 影视详情页传 `true`——该页信息区没有外层卡片，需要自带一层；
/// - 图书详情页保持默认 `false`——调用处已在卡片内，再加一层会双层描边。
///
/// 两个详情页原先各有一份逻辑完全相同的私有实现（仅外层容器不同），
/// 本组件是其合并结果；折叠测量这类易错逻辑从此只有一处需要维护。
class ExpandableSynopsis extends StatefulWidget {
  const ExpandableSynopsis({
    super.key,
    required this.text,
    this.boxed = false,
  });

  final String text;

  /// 是否自带卡片容器与描边（影视详情页为 true）
  final bool boxed;

  @override
  State<ExpandableSynopsis> createState() => _ExpandableSynopsisState();
}

class _ExpandableSynopsisState extends State<ExpandableSynopsis> {
  static const int _foldLines = 4;

  bool _expanded = false;
  bool _overflow = false;
  bool _measured = false;

  /// 上次测量的可用宽度（文本或宽度变化才重测，避免每次 rebuild 重复排版）
  double _lastWidth = -1;

  /// postFrame 调度去重——首帧前若发生多次 rebuild，不重复入队相同的测量任务
  bool _measureScheduled = false;

  /// 测量简介是否超过 [_foldLines] 行，结果按（文本, 宽度）缓存。
  ///
  /// 排版是同步重活，不在 build 阶段执行——由 postFrame 调度本方法，
  /// 避免长简介下每次 rebuild 都触发一次 TextPainter.layout()。
  void _measure(double maxWidth) {
    _measured = true;
    _measureScheduled = false;
    _lastWidth = maxWidth;
    final painter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: TextStyle(
          fontSize: 14,
          height: 1.7,
          color: context.colors.textSecondary,
        ),
      ),
      maxLines: _foldLines,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    final needFold = painter.didExceedMaxLines;
    if (needFold != _overflow && mounted) {
      setState(() => _overflow = needFold);
    }
  }

  @override
  void didUpdateWidget(covariant ExpandableSynopsis oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 简介内容变化（如编辑后返回）时重新测量折叠状态
    if (oldWidget.text != widget.text) {
      _measured = false;
      _measureScheduled = false;
      _lastWidth = -1;
      _overflow = false;
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = LayoutBuilder(
      builder: (context, constraints) {
        // 排版不在 build 阶段同步执行，交给 postFrame（_measure 内缓存结果）
        if (!_measured || constraints.maxWidth != _lastWidth) {
          if (!_measureScheduled) {
            _measureScheduled = true;
            final width = constraints.maxWidth;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _measure(width);
            });
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.text,
              maxLines: _expanded ? null : _foldLines,
              overflow: _expanded ? null : TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.7,
                color: context.colors.textSecondary,
              ),
            ),
            if (_overflow)
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _expanded ? '收起' : '展开全部',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: context.colors.accent,
                          ),
                        ),
                        Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 16,
                          color: context.colors.accent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );

    if (!widget.boxed) return content;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.outline, width: 0.7),
      ),
      child: content,
    );
  }
}
