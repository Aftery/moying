import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import '../models/cast_item.dart';

/// 演职员表弹层（详情页「主创 / 演员 → 全部」入口）
///
/// 布局：拖拽条 → 标题「演职员表 (N)」+ 关闭 → 搜索框 → 分组列表
/// （导演 / 主要演员），每行 = 头像 + 姓名 + 角色 + 箭头。
///
/// 跳转不在本组件内 import 演员页——由 [onTapActor] 回调交给调用方执行，
/// 避免 widgets → screens → widgets 的循环依赖。
Future<void> showCastBottomSheet({
  required BuildContext context,
  required List<CastItem> cast,
  required void Function(String actorId) onTapActor,
  String? movieTitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surfaceHigh,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _CastSheet(
      cast: cast,
      onTapActor: onTapActor,
      movieTitle: movieTitle,
    ),
  );
}

class _CastSheet extends StatefulWidget {
  const _CastSheet({
    required this.cast,
    required this.onTapActor,
    this.movieTitle,
  });

  final List<CastItem> cast;

  /// 点击已收录演员时回调（参数为本地 Actor id）
  final void Function(String actorId) onTapActor;

  /// 片名（副标题，可空）
  final String? movieTitle;

  @override
  State<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<_CastSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (mounted) setState(() => _query = _searchCtrl.text.trim());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 按姓名或角色名过滤（大小写不敏感）
  List<CastItem> get _filtered {
    if (_query.isEmpty) return widget.cast;
    final q = _query.toLowerCase();
    return widget.cast
        .where((c) =>
            c.name.toLowerCase().contains(q) ||
            c.characterText.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final all = _filtered;
    final directors =
        all.where((c) => c.isDirector).toList(growable: false);
    final actors = all.where((c) => !c.isDirector).toList(growable: false);
    // 弹层高度：屏高 85%，键盘弹起时由 MediaQuery 自动挤压
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---------- 拖拽条 ----------
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 16),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // ---------- 标题行 ----------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '演职员表 (${widget.cast.length})',
                        style:  TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (widget.movieTitle != null &&
                          widget.movieTitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          widget.movieTitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:  TextStyle(
                            color: context.colors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  icon:  Icon(Icons.close_rounded,
                      color: context.colors.textMuted),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ---------- 搜索框 ----------
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchCtrl,
              style:  TextStyle(color: context.colors.textPrimary, fontSize: 14),
              cursorColor: context.colors.accent,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索演员或角色姓名…',
                hintStyle:
                     TextStyle(color: context.colors.textMuted, fontSize: 13.5),
                prefixIcon:  Icon(Icons.search_rounded,
                    size: 19, color: context.colors.textMuted),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon:  Icon(Icons.close_rounded,
                            size: 17, color: context.colors.textMuted),
                        onPressed: _searchCtrl.clear,
                      ),
                filled: true,
                fillColor: context.colors.surface,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // ---------- 分组列表 ----------
          Flexible(
            child: all.isEmpty
                ?  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        _query.isEmpty ? '暂无演职员信息' : '没有匹配的演员',
                        style: TextStyle(
                            color: context.colors.textMuted, fontSize: 13),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    children: [
                      if (directors.isNotEmpty) ...[
                        _groupTitle(context, '导演'),
                        ...directors.map(_buildRow),
                        const SizedBox(height: 12),
                      ],
                      if (actors.isNotEmpty) ...[
                        _groupTitle(context, '主要演员'),
                        ...actors.map(_buildRow),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _groupTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        text,
        style:  TextStyle(
          color: context.colors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildRow(CastItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // 未收录（actorId 为空）不给点击反馈
        onTap: item.canOpen ? () => widget.onTapActor(item.actorId!) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
          child: Row(
            children: [
              _SheetAvatar(name: item.name, photoUrl: item.photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:  TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (item.characterText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.characterText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:  TextStyle(
                          color: context.colors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.canOpen)
                 Icon(Icons.chevron_right_rounded,
                    size: 20, color: context.colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹层内的圆形头像（与详情页 [_CastAvatar] 同款：有图显图，无图中性灰渐变）
class _SheetAvatar extends StatelessWidget {
  const _SheetAvatar({required this.name, this.photoUrl});

  final String name;
  final String? photoUrl;

  static const double size = 46;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final hasPhoto = url != null && url.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.colors.outline, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: 200,
              // 图源失效（断网 / 404）时回退占位，不留透明空圆
              errorBuilder: (_, __, ___) => _SheetAvatarFallback(name: name),
            )
          : _SheetAvatarFallback(name: name),
    );
  }
}

/// 占位：中性灰渐变 + 姓名首字（与详情页演员头像同款）
class _SheetAvatarFallback extends StatelessWidget {
  const _SheetAvatarFallback({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed.substring(0, 1);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: _SheetAvatar.size,
      height: _SheetAvatar.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [Color(0xFF565664), Color(0xFF33333F)]
              : const [Color(0xFFD4D4DE), Color(0xFFAEAEBB)],
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: isDark ? const Color(0xFFD8D8E2) : const Color(0xFF5A5A6A),
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
