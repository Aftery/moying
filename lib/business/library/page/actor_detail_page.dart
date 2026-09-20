
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../component/theme/app_palette.dart';
import '../model/actor.dart';
import '../../../component/media/model/media_ref.dart';
import '../model/movie.dart';
import '../view_model/library_provider.dart';
import '../../../component/media/media_cover.dart';
import 'movie_detail_page.dart';
import '../view/actor_detail_view.dart';

/// 演员详情界面（P3 内链闭环）
///
/// 展示头像（无头像时姓名首字占位）、简介与参演作品。作品列表由
/// [LibraryProvider.moviesByActor] 反查得出、不落盘——删除电影后列表自动消失。
/// AppBar 提供「编辑资料」（改名/写简介）与「删除演员」：
/// 被电影引用时删除被拒并列出引用作品，引用清零后才允许删除。
class ActorDetailPage extends StatelessWidget {
  const ActorDetailPage({super.key, required this.actorId});

  /// 需要展示的演员 id
  final String actorId;

  /// 由姓名派生的稳定色相（同名演员始终同色）
  static double _hueOf(String name) =>
      (name.codeUnits.fold<int>(0, (s, c) => s + c) % 360).toDouble();

  // ---------- 编辑资料（弹层：改名 / 写简介 / 换头像）----------

  Future<void> _openEditor(
    BuildContext context,
    LibraryProvider lib,
    Actor actor,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    // 编辑弹层自管输入控制器生命周期（随 route 销毁释放），
    // 规避「pop 退出动画未结束即 dispose controller」的 framework 断言。
    final result = await showDialog<ActorEditResult>(
      context: context,
      builder: (_) => ActorEditDialog(
        name: actor.name,
        bio: actor.bio ?? '',
        avatar: actor.avatar,
        hue: _hueOf(actor.name),
      ),
    );
    if (result == null || !context.mounted) return;
    final name = result.name.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('演员姓名不能为空')));
      return;
    }
    final bio = result.bio.trim();
    final base = actor.copyWith(
      name: name,
      bio: bio.isEmpty ? null : bio,
    );
    try {
      if (!result.avatarTouched) {
        // updateActor 为同步 void（内部 _persistActors 自行 catchError 兜底），
        // 不能 await；try/catch 保留用于兜住下方 attachImage 的落盘异常。
        lib.updateActor(base);
        return;
      }
      // 头像被改动：本地图先复制落盘 → local；URL → network；否则移除(null)
      MediaRef? avatar;
      final picked = result.avatarFile;
      if (picked != null) {
        final rel = await lib.attachImage(picked, actor.id);
        avatar = rel == null ? null : MediaRef.local(rel);
      } else if (result.avatarUrl.isNotEmpty) {
        avatar = MediaRef.network(result.avatarUrl);
      }
      lib.updateActor(base.copyWith(avatar: avatar));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存演员信息失败：$e')));
    }
  }

  // ---------- 删除（引用保护）----------

  Future<void> _confirmDelete(
    BuildContext context,
    LibraryProvider lib,
    Actor actor,
  ) async {
    final refs = lib.moviesByActor(actor.id);
    if (refs.isNotEmpty) {
      final titles = refs.take(3).map((m) => '《${m.title}》').join('、');
      final more = refs.length > 3 ? '，等 ${refs.length} 部' : '';
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.colors.surfaceHigh,
          title:  Text(
            '暂不能删除',
            style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700),
          ),
          content: Text(
            '${actor.name} 参演了$more$titles。\n\n请先在这些电影的编辑页移除 TA 的演员条目，再回来删除。',
            style:  TextStyle(
                color: context.colors.textSecondary,
                fontSize: 13.5,
                height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child:
                   Text('知道了', style: TextStyle(color: context.colors.textMuted)),
            ),
          ],
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceHigh,
        title:  Text(
          '删除这位演员？',
          style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700),
        ),
        content: Text(
          '${actor.name} 当前没有参演任何电影，删除后不可恢复。',
          style:  TextStyle(color: context.colors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                 Text('取消', style: TextStyle(color: context.colors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '删除',
              style: TextStyle(
                  color: context.colors.danger, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      lib.deleteActor(actor.id);
      Navigator.of(context).pop();
    }
  }

  // ---------- 构建 ----------

  @override
  Widget build(BuildContext context) {
    // H6/M6：select 订阅演员表与影库引用；无关变化（档案/主题等）不再重建
    final lib = context.read<LibraryProvider>();
    final actors =
        context.select<LibraryProvider, List<Actor>>((p) => p.actors);
    final movies =
        context.select<LibraryProvider, List<Movie>>((p) => p.movieList);
    final matches = actors.where((a) => a.id == actorId).toList();
    final actor = matches.isEmpty ? null : matches.first;
    final works = actor == null
        ? const <Movie>[]
        : movies.where((m) => m.actorIds?.contains(actor.id) == true).toList();

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: actor == null
            ? null
            : [
                IconButton(
                  tooltip: '编辑资料',
                  icon:  Icon(Icons.edit_rounded,
                      color: context.colors.textPrimary),
                  onPressed: () => _openEditor(context, lib, actor),
                ),
                IconButton(
                  tooltip: '删除演员',
                  icon:  Icon(Icons.delete_outline_rounded,
                      color: context.colors.textPrimary),
                  onPressed: () => _confirmDelete(context, lib, actor),
                ),
                const SizedBox(width: 8),
              ],
      ),
      body: actor == null
          ?  Center(
              child: Text(
                '这位演员已从演员库移除',
                style: TextStyle(color: context.colors.textMuted),
              ),
            )
          : SafeArea(
              top: false,
              child: CustomScrollView(
                slivers: [
                  // ---------- 头部（头像 / 姓名 / 简介 / 区块标题）----------
                  // 固定且量小，放 SliverToBoxAdapter 即时构建；
                  // 真正会长的是下方「参演作品」，单独走懒构建 Sliver（M-3）。
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 116,
                              height: 116,
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: context.colors.outline, width: 0.8),
                              ),
                              child: MediaCover(
                                circular: true,
                                media: actor.avatar,
                                title: actor.name,
                                hue: _hueOf(actor.name),
                                fontSize: 44,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            actor.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // ---------- 简介 ----------
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: context.colors.surfaceHigh,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: context.colors.outline, width: 0.7),
                            ),
                            child: actor.bio == null || actor.bio!.isEmpty
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.auto_awesome_outlined,
                                          size: 15,
                                          color: context.colors.textMuted),
                                      const SizedBox(width: 6),
                                      Text(
                                        '暂无简介，点击右上角补充',
                                        style: TextStyle(
                                            color: context.colors.textMuted,
                                            fontSize: 13),
                                      ),
                                    ],
                                  )
                                : Text(
                                    actor.bio!,
                                    style: TextStyle(
                                      color: context.colors.textSecondary,
                                      fontSize: 14,
                                      height: 1.7,
                                    ),
                                  ),
                          ),
                          const SizedBox(height: 26),
                          // ---------- 参演作品标题 ----------
                          _sectionTitle(context, '参演作品'),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  // ---------- 参演作品：懒构建（作品数可达数十上百）----------
                  if (works.isEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                      sliver: SliverToBoxAdapter(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: context.colors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: context.colors.outline, width: 0.7),
                          ),
                          child: Center(
                            child: Text(
                              '还没有参演记录',
                              style: TextStyle(
                                  color: context.colors.textMuted,
                                  fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
                      sliver: SliverList.builder(
                        itemCount: works.length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildWorkTile(context, works[i]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  // ---------- 作品行 ----------

  Widget _buildWorkTile(BuildContext context, Movie movie) {
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MovieDetailPage(movieId: movie.id),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // 小海报
              SizedBox(
                width: 46,
                child: MediaCover(
                  media: movie.poster,
                  title: movie.title,
                  emoji: movie.emoji ?? '',
                  hue: movie.coverHue,
                  aspectRatio: 3 / 4,
                  borderRadius: 8,
                  fontSize: 15,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:  TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${movie.year}${movie.rating != null ? ' · ${movie.rating!.toStringAsFixed(1)} 分' : ''}',
                      style:  TextStyle(
                          color: context.colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
               Icon(Icons.chevron_right_rounded,
                  size: 20, color: context.colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 区块标题 ----------

  Widget _sectionTitle(BuildContext context, String text) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            gradient: context.colors.movieGradient,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style:  TextStyle(
            color: context.colors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// 演员资料编辑弹层的返回值（保存原始文本，由调用方 trim 判定）
