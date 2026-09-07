import 'package:flutter/material.dart';

import '../config/app_palette.dart';

/// 搜索结果条目的展示数据（Book/Movie 搜索结果的公共投影，
/// 由调用方从各自的结果类型 map 而来，组件不感知具体模型）
class QuickSearchItem {
  const QuickSearchItem({
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.externalId,
  });

  final String title;
  final String subtitle;
  final String? coverUrl;
  final String externalId;
}

/// 编辑页「快速检索」面板（book_edit / movie_edit 共用，M5 去重产物）。
///
/// 职责边界：搜索状态（controller / debounce / 请求发起 / 回填逻辑）
/// 由宿主 State 管理——两屏的差异（搜书 or 搜电影、IMDb/TMDB 回填）
/// 全部留在宿主；本组件只负责呈现：
/// 标题行 + 搜索框 + loading / 错误 / 空态提示 / 结果列表。
class QuickSearchPanel extends StatelessWidget {
  const QuickSearchPanel({
    super.key,
    required this.controller,
    required this.hint,
    required this.sourceName,
    required this.isSearching,
    required this.error,
    required this.results,
    required this.filledExternalId,
    required this.tagColor,
    required this.fallbackIcon,
    required this.onClear,
    required this.onPick,
  });

  /// 搜索词输入框 controller（宿主持有，debounce listener 在宿主侧）
  final TextEditingController controller;
  final String hint;

  /// 当前生效数据源展示名（如 'Open Library' / 'TMDB'）
  final String sourceName;

  final bool isSearching;
  final String? error;

  /// null = 尚未搜索（显示引导文案）；空 = 搜了但无结果
  final List<QuickSearchItem>? results;

  /// 最近一次已回填结果的外部 id（用于「已填充」标记）
  final String? filledExternalId;

  /// 「已填充」标签主色（书 readingStart / 影 movieStart）
  final Color tagColor;

  /// 封面加载失败时的占位图标（书/影不同）
  final IconData fallbackIcon;

  final VoidCallback onClear;
  final ValueChanged<QuickSearchItem> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.travel_explore_rounded, size: 18, color: c.accent),
              const SizedBox(width: 6),
              Text(
                '快速检索',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  '数据源：$sourceName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            style: TextStyle(color: c.textPrimary, fontSize: 14),
            cursorColor: c.accent,
            decoration: InputDecoration(
              prefixIcon:
                  Icon(Icons.search_rounded, size: 20, color: c.textMuted),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : GestureDetector(
                      onTap: onClear,
                      behavior: HitTestBehavior.opaque,
                      child: Icon(Icons.close_rounded,
                          size: 18, color: c.textMuted),
                    ),
              hintText: hint,
              hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
              isDense: true,
              filled: true,
              fillColor: c.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.outline, width: 0.8),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.outline, width: 0.8),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: c.accent, width: 1.3),
              ),
            ),
          ),
          _body(context),
        ],
      ),
    );
  }

  /// 搜索结果区：进行中 loading / 错误提示 / 空结果 / 结果列表
  Widget _body(BuildContext context) {
    final c = context.colors;
    if (isSearching) {
      return const Padding(
        padding: EdgeInsets.only(top: 14),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (results == null && error != null && error!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, size: 14, color: c.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                error!,
                style: TextStyle(fontSize: 12, color: c.error),
              ),
            ),
          ],
        ),
      );
    }
    if (results == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          '搜索结果将显示在这里，点击条目自动回填表单',
          style: TextStyle(fontSize: 12, color: c.textMuted),
        ),
      );
    }
    if (results!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          '未找到相关结果，换个关键词试试',
          style: TextStyle(fontSize: 12, color: c.textMuted),
        ),
      );
    }
    return Column(
      children: [for (final item in results!) _tile(context, item)],
    );
  }

  /// 结果条目：小封面 + 标题 + 副标题 + 回填入口
  Widget _tile(BuildContext context, QuickSearchItem item) {
    final c = context.colors;
    final filled = filledExternalId == item.externalId;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onPick(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _cover(context, item.coverUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  if (item.subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textMuted),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (filled)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tagColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '已填充',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: tagColor,
                  ),
                ),
              )
            else
              Icon(Icons.download_for_offline_outlined,
                  size: 18, color: c.textMuted),
          ],
        ),
      ),
    );
  }

  /// 封面缩略图（网络图失败回退占位图标）
  Widget _cover(BuildContext context, String? url) {
    final c = context.colors;
    Widget fallback() => ColoredBox(
          color: c.surface,
          child: Icon(fallbackIcon, size: 20, color: c.textMuted),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 40,
        height: 56,
        child: (url == null || url.isEmpty)
            ? fallback()
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback(),
              ),
      ),
    );
  }
}
