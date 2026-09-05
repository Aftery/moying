import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../models/media_ref.dart';
import '../providers/library_provider.dart';
import 'cover_placeholder.dart';

/// 媒体图三态展示组件（Book 封面 / Movie 海报 / Actor 头像共用）
///
/// 展示优先级：**待落盘图**（[pendingFile]，编辑中选中尚未复制进 images/）
/// > **本地图**（media.localFile，由 [LibraryProvider] 解析 images 目录）
/// > **网络图**（media.remoteUrl）> **占位**（coverHue + emoji 渐变）。
/// 任何图加载失败均回退占位——图片是可降级资源，绝不让 UI 因此缺角。
///
/// 两种形态：
/// - 矩形（默认）：与 [CoverPlaceholder] 同几何（AspectRatio + 圆角），
///   无图时直接透出占位，替换既有调用点后像素零变化；
/// - 圆形（[circular] = true）：演员头像形态，占位 = 渐变圆 + 首字，
///   **需要父级提供正方形约束**（如外层 62×62 / 116×116 的盒子）。
class MediaCover extends StatelessWidget {
  const MediaCover({
    super.key,
    this.media,
    this.pendingFile,
    required this.title,
    this.emoji,
    this.hue = 250,
    this.aspectRatio = 3 / 4,
    this.borderRadius = 12,
    this.fontSize = 26,
    this.showTitle = false,
    this.circular = false,
  });

  /// 已保存的图片引用（本地/网络），null 或双空 = 占位
  final MediaRef? media;

  /// 编辑中选中、尚未复制进 images/ 的本地图（选图后预览）
  final File? pendingFile;

  /// 占位标题（显示首字 / 底部标题文字）
  final String title;

  /// 占位 emoji（空则显示标题首字符）
  final String? emoji;

  /// 占位渐变 / 背景色相
  final double hue;

  /// 矩形宽高比
  final double aspectRatio;

  /// 矩形圆角
  final double borderRadius;

  /// 占位中央图形字号
  final double fontSize;

  /// 是否在底部叠加标题文字（矩形模式）
  final bool showTitle;

  /// 圆形模式（演员头像）；需父级正方形约束
  final bool circular;

  /// 解析本地图目录的 Provider（可选探测）：
  /// MediaCover 也用于孤立预览/无 Provider 树的测试，此时本地图无法解析，
  /// 静默回退占位。网络图展示不依赖 Provider，不受影响。
  LibraryProvider? _libOf(BuildContext context) {
    try {
      return context.read<LibraryProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ---------- 确定图片来源 ----------
    File? local;
    String? network;
    if (pendingFile != null) {
      local = pendingFile;
    } else {
      final m = media;
      if (m != null && m.isNetwork) {
        network = m.remoteUrl;
      } else if (m != null && m.isLocal) {
        local = _libOf(context)?.resolveLocalImage(m.localFile);
      }
    }

    final fallback = circular ? _buildCircularFallback() : _buildRectFallback();

    Widget? img;
    if (local != null) {
      img = Image.file(
        local,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    } else if (network != null) {
      img = Image.network(
        network,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    if (img == null) return fallback;

    return circular
        ? ClipOval(child: SizedBox.expand(child: img))
        : AspectRatio(
            aspectRatio: aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: SizedBox.expand(child: img),
            ),
          );
  }

  /// 矩形占位（直接透出 CoverPlaceholder，与替换前像素一致）
  Widget _buildRectFallback() {
    return CoverPlaceholder(
      title: title,
      emoji: emoji,
      hue: hue,
      aspectRatio: aspectRatio,
      borderRadius: borderRadius,
      fontSize: fontSize,
      showTitle: showTitle,
    );
  }

  /// 圆形占位：渐变圆 + emoji/首字（需父级正方形约束）
  Widget _buildCircularFallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: coverGradient(hue),
      ),
      child: Center(
        child: Text(
          emoji ?? title.characters.first,
          style: TextStyle(
            fontSize: fontSize * 0.55,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
