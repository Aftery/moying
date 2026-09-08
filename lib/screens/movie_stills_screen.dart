import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import '../models/media_ref.dart';
import '../widgets/media_cover.dart';

/// 剧照与海报全量页（详情页「剧照 → 全部」入口）
///
/// 布局：AppBar（片名 + 总数）→ Tab（全部 / 剧照 / 海报）→ 网格。
/// 数据来自 [Movie.stills]（TMDB backdrops 落盘缓存）与主海报，
/// 已在详情页缓存，进本页不再发起网络请求。
///
/// 未实现右上角「筛选」：当前剧照只存了 URL，没有语言 / 尺寸等可筛维度，
/// 加了也是空壳——等后续接入元数据再补（Karpathy：不为对齐截图造无用控件）。
class MovieStillsScreen extends StatefulWidget {
  const MovieStillsScreen({
    super.key,
    required this.title,
    this.backdrops = const <MediaRef>[],
    this.posters = const <MediaRef>[],
  });

  /// 片名（AppBar 副标题 / 空态文案）
  final String title;

  /// 剧照（横版）
  final List<MediaRef> backdrops;

  /// 海报（竖版；当前为主海报，后续可扩展为 TMDB 海报墙）
  final List<MediaRef> posters;

  @override
  State<MovieStillsScreen> createState() => _MovieStillsScreenState();
}

class _MovieStillsScreenState extends State<MovieStillsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  /// 全部 = 剧照 + 海报（剧照在前，横版更适合先入眼）
  List<MediaRef> get _all => [...widget.backdrops, ...widget.posters];

  int get _total => widget.backdrops.length + widget.posters.length;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '剧照与海报',
              style:  TextStyle(
                color: context.colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${widget.title} · 共 $_total 张',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:  TextStyle(
                color: context.colors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ---------- Tab ----------
          TabBar(
            controller: _tab,
            labelColor: context.colors.textPrimary,
            unselectedLabelColor: context.colors.textMuted,
            indicatorColor: context.colors.movieStart,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle:
                const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
            unselectedLabelStyle:
                const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
            tabs: [
              Tab(text: '全部 $_total'),
              Tab(text: '剧照 ${widget.backdrops.length}'),
              Tab(text: '海报 ${widget.posters.length}'),
            ],
          ),
          // ---------- 网格 ----------
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildGrid(_all, aspect: 16 / 10),
                _buildGrid(widget.backdrops, aspect: 16 / 10, empty: '暂无剧照'),
                _buildGrid(widget.posters, aspect: 2 / 3, empty: '暂无海报'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(
    List<MediaRef> items, {
    required double aspect,
    String empty = '暂无图片',
  }) {
    if (items.isEmpty) {
      return  Center(
        child: Text(
          empty,
          style: TextStyle(color: context.colors.textMuted, fontSize: 13),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: aspect,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) => GestureDetector(
        onTap: () => _openPreview(ctx, items[i]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: MediaCover(
            media: items[i],
            title: '',
            aspectRatio: aspect,
            borderRadius: 12,
            fontSize: 0,
          ),
        ),
      ),
    );
  }

  /// 全屏预览（点击任意图放大，再点关闭）
  void _openPreview(BuildContext context, MediaRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(ctx).pop(),
          child: Center(
            child: MediaCover(
              media: ref,
              title: '',
              aspectRatio: 16 / 10,
              borderRadius: 14,
              fontSize: 0,
            ),
          ),
        ),
      ),
    );
  }
}
