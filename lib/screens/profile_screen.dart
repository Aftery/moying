import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../providers/library_provider.dart';

/// 个人中心页面 —— 框架占位
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('个人')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 头像 + 昵称
          const _ProfileCard(),
          const SizedBox(height: 20),

          // 年度统计摘要
          _StatSummary(library: library),
          const SizedBox(height: 24),

          // 设置入口
          const _SettingItem(icon: Icons.edit_note_rounded, label: '编辑资料'),
          const _SettingItem(
            icon: Icons.data_usage_rounded,
            label: '数据统计',
          ),
          const _SettingItem(
            icon: Icons.dark_mode_rounded,
            label: '深色模式',
            trailing: Switch(value: true, onChanged: null),
          ),
          const _SettingItem(
            icon: Icons.sync_rounded,
            label: '数据同步',
            trailing: Text('即将上线',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ),
          const SizedBox(height: 32),
          Text(
            '墨影 · v0.1.0\n一个正在成长的书籍与电影记录应用',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: AppColors.textMuted.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          // Container 无 const 构造，仅内部子树 const
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              gradient: AppColors.movieGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
          const SizedBox(width: 16),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '书友',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '读万卷书 · 行万里路',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ],
          ),
          const Spacer(),
          const Icon(Icons.qr_code_2_rounded, color: AppColors.textMuted),
        ],
      ),
    );
  }
}

class _StatSummary extends StatelessWidget {
  const _StatSummary({required this.library});

  final LibraryProvider library;

  @override
  Widget build(BuildContext context) {
    final b = library.bookStats;
    final m = library.movieStats;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '我的年度记录',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatCell(value: '${b.finished}', label: '读完书籍'),
              _StatCell(value: '${m.rated}', label: '看过电影'),
              _StatCell(value: '${b.pagesRead}', label: '阅读页数'),
              _StatCell(value: '${m.total}', label: '观影总数'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _SettingItem extends StatelessWidget {
  const _SettingItem({
    required this.icon,
    required this.label,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: AppColors.accent, size: 22),
        title: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        trailing: trailing ??
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      ),
    );
  }
}
