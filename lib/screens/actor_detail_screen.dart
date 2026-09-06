import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../models/actor.dart';
import '../models/media_ref.dart';
import '../models/movie.dart';
import '../providers/library_provider.dart';
import '../widgets/media_cover.dart';
import 'movie_detail_screen.dart';

/// 演员详情界面（P3 内链闭环）
///
/// 展示头像（无头像时姓名首字占位）、简介与参演作品。作品列表由
/// [LibraryProvider.moviesByActor] 反查得出、不落盘——删除电影后列表自动消失。
/// AppBar 提供「编辑资料」（改名/写简介）与「删除演员」：
/// 被电影引用时删除被拒并列出引用作品，引用清零后才允许删除。
class ActorDetailScreen extends StatelessWidget {
  const ActorDetailScreen({super.key, required this.actorId});

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
    final result = await showDialog<_ActorEditResult>(
      context: context,
      builder: (_) => _ActorEditDialog(
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
    final lib = context.watch<LibraryProvider>();
    final matches = lib.actors.where((a) => a.id == actorId).toList();
    final actor = matches.isEmpty ? null : matches.first;
    final works = actor == null ? const <Movie>[] : lib.moviesByActor(actor.id);

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
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
                children: [
                  // ---------- 头像 + 姓名 ----------
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
                    style:  TextStyle(
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
                      border: Border.all(color: context.colors.outline, width: 0.7),
                    ),
                    child: actor.bio == null || actor.bio!.isEmpty
                        ?  Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.auto_awesome_outlined,
                                  size: 15, color: context.colors.textMuted),
                              const SizedBox(width: 6),
                              Text(
                                '暂无简介，点击右上角补充',
                                style: TextStyle(
                                    color: context.colors.textMuted, fontSize: 13),
                              ),
                            ],
                          )
                        : Text(
                            actor.bio!,
                            style:  TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 14,
                              height: 1.7,
                            ),
                          ),
                  ),
                  const SizedBox(height: 26),
                  // ---------- 参演作品 ----------
                  _sectionTitle(context, '参演作品'),
                  const SizedBox(height: 12),
                  if (works.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: context.colors.outline, width: 0.7),
                      ),
                      child:  Center(
                        child: Text(
                          '还没有参演记录',
                          style:
                              TextStyle(color: context.colors.textMuted, fontSize: 13),
                        ),
                      ),
                    )
                  else
                    ...works.map(
                      (m) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildWorkTile(context, m),
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
            builder: (_) => MovieDetailScreen(movieId: movie.id),
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
class _ActorEditResult {
  const _ActorEditResult({
    required this.name,
    required this.bio,
    this.avatarFile,
    this.avatarUrl = '',
    required this.avatarTouched,
  });

  final String name;
  final String bio;

  /// 从相册选中的本地头像（未落盘，由调用方复制进 images/）
  final File? avatarFile;

  /// 网络头像地址
  final String avatarUrl;

  /// 头像是否被用户动过（选图 / 填 URL / 清除）——true 时用新头像覆盖
  final bool avatarTouched;
}

/// 演员资料编辑弹层：输入控制器由自身 State 持有，
/// 随弹层 route 销毁统一释放，避免过早 dispose。
class _ActorEditDialog extends StatefulWidget {
  const _ActorEditDialog({
    required this.name,
    required this.bio,
    this.avatar,
    required this.hue,
  });

  final String name;
  final String bio;

  /// 原头像（未动过时预览用）
  final MediaRef? avatar;

  /// 占位渐变 hue（页面按姓名计算后传入）
  final double hue;

  @override
  State<_ActorEditDialog> createState() => _ActorEditDialogState();
}

class _ActorEditDialogState extends State<_ActorEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _avatarUrlCtrl;

  /// 从相册选中的本地图（保存时由调用方 attach）
  File? _picked;

  /// 用户显式点了「清除头像」（把 localFile 头像也归入可清除范围）
  bool _cleared = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.name);
    _bioCtrl = TextEditingController(text: widget.bio);
    _avatarUrlCtrl = TextEditingController(
        text: widget.avatar?.remoteUrl ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _avatarUrlCtrl.dispose();
    super.dispose();
  }

  /// 头像是否被改动过（决定保存时覆盖原头像还是原样保留）：
  /// 选中本地图 / 显式清除 / URL 文本与原网络图不同，任一即视为改动。
  bool get _avatarTouched {
    if (_picked != null || _cleared) return true;
    final url = _avatarUrlCtrl.text.trim();
    if (url.isEmpty) return false;
    return url != widget.avatar?.remoteUrl;
  }

  /// 预览输入：选中本地图 → [MediaCover.pendingFile] 优先；
  /// URL 非空 → 网络；否则回到原头像。
  MediaRef? get _previewAvatar {
    if (_picked != null) return null;
    final url = _avatarUrlCtrl.text.trim();
    if (url.isNotEmpty) return MediaRef.network(url);
    return widget.avatar;
  }

  bool get _canPick =>
      context.read<LibraryProvider>().canPickImage;

  Future<void> _pickFromGallery() async {
    final lib = context.read<LibraryProvider>();
    final picked = await lib.pickImageFile();
    if (picked == null || !mounted) return;
    setState(() {
      _picked = picked;
      _avatarUrlCtrl.clear();
    });
  }

  InputDecoration _dec(String label, String hint) {
    return InputDecoration(
      labelText: label,
      labelStyle:  TextStyle(color: context.colors.textMuted, fontSize: 13),
      hintText: hint,
      hintStyle:  TextStyle(color: context.colors.textMuted, fontSize: 13),
      filled: true,
      fillColor: context.colors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:  BorderSide(color: context.colors.outline, width: 0.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:  BorderSide(color: context.colors.outline, width: 0.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:  BorderSide(color: context.colors.accent, width: 1.2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final previewName =
        _nameCtrl.text.trim().isEmpty ? '演员' : _nameCtrl.text.trim();
    return AlertDialog(
      backgroundColor: context.colors.surfaceHigh,
      title:  Text(
        '编辑演员资料',
        style: TextStyle(
            color: context.colors.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------- 头像区 ----------
            Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: MediaCover(
                    circular: true,
                    media: _previewAvatar,
                    pendingFile: _picked,
                    title: previewName,
                    hue: widget.hue,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_canPick)
                        TextButton.icon(
                          onPressed: _pickFromGallery,
                          style: TextButton.styleFrom(
                            foregroundColor: context.colors.textSecondary,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 36),
                          ),
                          icon: const Icon(Icons.photo_library_outlined,
                              size: 17),
                          label: const Text('从相册选择',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _cleared = true;
                          _picked = null;
                          _avatarUrlCtrl.clear();
                        }),
                        style: TextButton.styleFrom(
                          foregroundColor: context.colors.danger,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 36),
                        ),
                        icon: const Icon(Icons.image_not_supported_outlined,
                            size: 16),
                        label: const Text('清除头像',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _avatarUrlCtrl,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {
                // 一旦输入 URL，丢弃已选本地图（两者互斥，URL 优先）
                _picked = null;
              }),
              style:
                   TextStyle(color: context.colors.textPrimary, fontSize: 13),
              cursorColor: context.colors.accent,
              decoration: _dec('网络头像链接', 'https://…（可选）'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtrl,
              onChanged: (_) => setState(() {}),
              style:  TextStyle(color: context.colors.textPrimary, fontSize: 15),
              cursorColor: context.colors.accent,
              decoration: _dec('姓名', '演员姓名'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _bioCtrl,
              minLines: 2,
              maxLines: 4,
              style:
                   TextStyle(color: context.colors.textPrimary, fontSize: 14),
              cursorColor: context.colors.accent,
              decoration: _dec('简介', '一句话介绍 TA（可选）'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child:
               Text('取消', style: TextStyle(color: context.colors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ActorEditResult(
            name: _nameCtrl.text,
            bio: _bioCtrl.text,
            avatarFile: _picked,
            avatarUrl: _avatarUrlCtrl.text.trim(),
            avatarTouched: _avatarTouched,
          )),
          child:  Text(
            '保存',
            style: TextStyle(
                color: context.colors.accent, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
