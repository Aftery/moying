import 'package:flutter/material.dart';

import '../config/app_palette.dart';

/// 封面占位组件
///
/// 不依赖网络图片：按传入的 [emoji]、[hue] 与 [title] 生成
/// 渐变封面，保证离线 / 无资源时界面依然完整。
class CoverPlaceholder extends StatelessWidget {
  const CoverPlaceholder({
    super.key,
    required this.title,
    this.emoji,
    this.hue = 250,
    this.aspectRatio = 3 / 4,
    this.borderRadius = 12,
    this.fontSize = 26,
    this.showTitle = false,
  });

  /// 标题（用于占位文字首字/回退）
  final String title;

  /// 展示的 emoji（为空则显示标题首字符）
  final String? emoji;

  /// 色相 0-360
  final double hue;

  /// 宽高比（书籍/海报通用 3:4）
  final double aspectRatio;

  /// 圆角
  final double borderRadius;

  /// 中央图形字号
  final double fontSize;

  /// 是否在底部叠加标题文字
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final symbol = emoji?.trim();
    final fallback = symbol == null || symbol.isEmpty
        ? (title.isEmpty ? '?' : title.characters.first)
        : symbol;
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: coverGradient(hue)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 轻微噪感装饰圆
              Positioned(
                right: -12,
                bottom: -12,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.06),
                  ),
                ),
              ),
              Center(
                child: Text(
                  fallback,
                  style: TextStyle(fontSize: fontSize),
                ),
              ),
              if (showTitle)
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
