import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../component/common/sheet_grabber.dart';
import '../../../component/theme/app_palette.dart';
import '../../../component/media/model/media_ref.dart';
import '../../shared/model/stats.dart';
import '../../shared/model/user_profile.dart';
import '../../library/view_model/library_provider.dart';
import '../../../component/media/media_cover.dart';
import '../../data_source/page/data_source_page.dart';
import '../../sync/page/data_sync_page.dart';
import 'error_log_page.dart';
import '../../stats/page/personal_stats_page.dart';
import '../view/profile_view.dart';

/// 个人中心 —— 档案（昵称/签名/头像）、主题偏好、个人统计入口
///
/// 档案与主题偏好均持久化于 profile.json（单例集合）；
/// 编辑弹层交互与演员资料编辑（actor_detail_screen）同构。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    // H6/M6：select 收窄订阅——书库数据变化不再触发个人页 rebuild，
    // 仅档案/主题/统计摘要变化时重建；回调用 read 即可。
    final profile =
        context.select<LibraryProvider, UserProfile>((p) => p.userProfile);
    final themeMode =
        context.select<LibraryProvider, String>((p) => p.themeMode);
    final bookStats =
        context.select<LibraryProvider, BookStats>((p) => p.bookStats);
    final movieStats =
        context.select<LibraryProvider, MovieStats>((p) => p.movieStats);
    final library = context.read<LibraryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('个人')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 头像 + 昵称（点击只读展示，编辑走下方「编辑资料」入口）
          ProfileCard(
            profile: profile,
            onTap: () => _showProfileInfo(context, profile),
          ),
          const SizedBox(height: 20),

          // 年度统计摘要
          StatSummary(bookStats: bookStats, movieStats: movieStats),
          const SizedBox(height: 24),

          ..._buildSettingItems(context, library, themeMode),
          const SizedBox(height: 32),
          Text(
            '墨影 · v0.8.0\n一个正在成长的书籍与电影记录应用',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: context.colors.textMuted.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// 设置入口列表：编辑资料 / 数据统计 / 深色模式 / 数据源 / 同步 / 错误日志。
  List<Widget> _buildSettingItems(
      BuildContext context, LibraryProvider library, String themeMode) {
    return [
      SettingItem(
        icon: Icons.edit_note_rounded,
        label: '编辑资料',
        onTap: () => _openProfileEditor(context, library),
      ),
      SettingItem(
        icon: Icons.data_usage_rounded,
        label: '数据统计',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PersonalStatsPage()),
        ),
      ),
      SettingItem(
        icon: Icons.dark_mode_rounded,
        label: '深色模式',
        trailing: ThemeModeLabel(mode: themeMode),
        onTap: () => _chooseThemeMode(context, library),
      ),
      // Web 平台无本地存储 / 真实网络栈受限 → 隐藏数据源与同步入口
      if (!kIsWeb) ...[
        SettingItem(
          icon: Icons.cloud_download_outlined,
          label: '数据源管理',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DataSourcePage()),
          ),
        ),
        SettingItem(
          icon: Icons.sync_rounded,
          label: '数据同步',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DataSyncPage()),
          ),
        ),
        SettingItem(
          icon: Icons.bug_report_rounded,
          label: '错误日志',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ErrorLogPage()),
          ),
        ),
      ],
    ];
  }

  // ---------- 档案只读展示（点卡片弹出，编辑走「编辑资料」行）----------

  void _showProfileInfo(BuildContext context, UserProfile profile) {
    final signature = profile.signature?.trim() ?? '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      backgroundColor: context.colors.surfaceHigh,
      elevation: 3,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ProfileInfoSheet(
        profile: profile,
        signature: signature,
      ),
    );
  }

  // ---------- 编辑资料（弹层：昵称 / 签名 / 换头像）----------

  Future<void> _openProfileEditor(
    BuildContext context,
    LibraryProvider lib,
  ) async {
    final profile = lib.userProfile;
    final messenger = ScaffoldMessenger.of(context);
    // 编辑弹层自管输入控制器生命周期（随 route 销毁释放），
    // 规避「pop 退出动画未结束即 dispose controller」的 framework 断言。
    final result = await showModalBottomSheet<ProfileEditResult>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        minHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      backgroundColor: context.colors.surfaceHigh,
      elevation: 3,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProfileEditSheet(profile: profile),
    );
    if (result == null || !context.mounted) return;
    final nickname = result.nickname.trim();
    if (nickname.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('昵称不能为空')));
      return;
    }
    final signature = result.signature.trim();
    final base = profile.copyWith(
      nickname: nickname,
      signature: signature.isEmpty ? null : signature,
    );
    try {
      if (!result.avatarTouched) {
        await lib.updateProfile(base);
        return;
      }
      // 头像被改动：本地图先复制落盘 → local；URL → network；否则移除(null)
      MediaRef? avatar;
      final picked = result.avatarFile;
      if (picked != null) {
        // 单例档案：固定 entryId 'profile'，copyImage 同名覆盖天然回收旧图
        final rel = await lib.attachImage(picked, 'profile');
        avatar = rel == null ? null : MediaRef.local(rel);
      } else if (result.avatarUrl.isNotEmpty) {
        avatar = MediaRef.network(result.avatarUrl);
      }
      await lib.updateProfile(base.copyWith(avatar: avatar));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存档案失败：$e')));
    }
  }

  // ---------- 深色模式（三选：深色 / 浅色 / 跟随系统）----------

  Future<void> _chooseThemeMode(
    BuildContext context,
    LibraryProvider lib,
  ) async {
    final current = lib.themeMode;
    const options = [
      ('dark', '深色', Icons.dark_mode_rounded),
      ('light', '浅色', Icons.light_mode_rounded),
      ('system', '跟随系统', Icons.settings_brightness_rounded),
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.colors.surfaceHigh,
      elevation: 3,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖拽指示条
              const SheetGrabber(),
              for (final (mode, label, icon) in options)
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: context.colors.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: context.colors.accent, size: 20),
                  ),
                  title: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  trailing: current == mode
                      ? Icon(Icons.check_rounded,
                          color: context.colors.accent, size: 22)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(mode),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (selected != null && selected != current) {
      await lib.setThemeMode(selected);
    }
  }
}

/// 档案只读弹层内容：拖拽条 + 头像昵称 + 签名 + 关闭按钮。
class _ProfileInfoSheet extends StatelessWidget {
  const _ProfileInfoSheet({required this.profile, required this.signature});

  final UserProfile profile;
  final String signature;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖拽指示条
            const SheetGrabber(),
            // 头像
            SizedBox(
              width: 80,
              height: 80,
              child: MediaCover(
                circular: true,
                media: profile.avatar,
                title: profile.nickname,
                hue: 262,
                fontSize: 32,
              ),
            ),
            const SizedBox(height: 18),
            // 昵称
            Text(
              profile.nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: context.colors.textPrimary,
              ),
            ),
            // 签名
            if (signature.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  signature,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _closeButton(context),
          ],
        ),
      ),
    );
  }

  /// 关闭按钮：点击收起弹层。
  Widget _closeButton(BuildContext context) => SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            backgroundColor: context.colors.surface,
            foregroundColor: context.colors.textSecondary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text('知道了',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      );
}

/// 主题偏好当前值标签（设置行 trailing）
