import 'package:flutter/material.dart';

import '../../../app/config/app_palette.dart';
import '../../../component/media/model/media_ref.dart';

class CastAvatar extends StatelessWidget {
  const CastAvatar({super.key,
    required this.name,
    this.photoUrl,
  });

  /// 头像半径（详情页横滑条固定尺寸，无第二个调用点故不作参数）
  static const double radius = 31;

  final String name;

  /// 头像地址（空 = 走占位）
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    const size = radius * 2;
    final url = photoUrl;
    final hasPhoto = url != null && url.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.outline, width: 0.8),
      ),
      // 圆形裁剪由容器承担，图片本身无需再套 ClipOval
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: 200,
              // TMDB 图源失效（404 / 断网）时回退占位，而不是留一个透明圆圈
              errorBuilder: (_, __, ___) =>
                  _CastAvatarFallback(name: name, size: size),
            )
          : _CastAvatarFallback(name: name, size: size),
    );
  }
}

/// 头像占位：中性灰渐变 + 姓名首字
class _CastAvatarFallback extends StatelessWidget {
  const _CastAvatarFallback({required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppPalette.placeholderGradient(isDark),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: AppPalette.placeholderGlyph(isDark),
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 剧照单图：网络图优先，加载中 / 失败 / 无图统一走中性灰占位
///
/// 剧照目前只来自 TMDB images（网络引用）；本地图（用户上传）尚未接入，
/// 命中 localFile 时同样走占位，避免相对路径未解析导致空白块。
class StillImage extends StatelessWidget {
  const StillImage({super.key, required this.ref});

  final MediaRef ref;

  @override
  Widget build(BuildContext context) {
    final url = ref.remoteUrl;
    if (url == null || url.isEmpty) return _placeholder(context);
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : _placeholder(context),
      errorBuilder: (_, __, ___) => _placeholder(context),
    );
  }

  Widget _placeholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF3A3A46), Color(0xFF25252F)]
              : const [Color(0xFFE2E2EA), Color(0xFFCACAD4)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.movie_filter_rounded,
          color: isDark ? Colors.white24 : Colors.black26,
          size: 30,
        ),
      ),
    );
  }
}

/// 元数据小格（图标 + 标签 + 值）
class MetaCell extends StatelessWidget {
  const MetaCell({super.key,
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: context.colors.movieStart),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:  TextStyle(
                    color: context.colors.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style:  TextStyle(
              color: context.colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
