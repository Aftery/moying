import 'package:flutter/material.dart';

import '../config/app_palette.dart';
import '../services/app_logger.dart';

class SummaryHeader extends StatelessWidget {
  const SummaryHeader({super.key,
    required this.total,
    required this.problems,
    required this.warnings,
    required this.environment,
  });

  final int total;
  final int problems;
  final int warnings;
  final String environment;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Metric(
                value: '$problems',
                label: '错误/崩溃',
                color: context.colors.error,
              ),
              _Metric(
                value: '$warnings',
                label: '警告',
                color: context.colors.warning,
              ),
              _Metric(
                value: '$total',
                label: '总条数',
                color: context.colors.accent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '运行环境：$environment',
            style: TextStyle(fontSize: 11.5, color: context.colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.colors.textMuted),
        ),
      ],
    );
  }
}

/// 隐私提示条
class HintBar extends StatelessWidget {
  const HintBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 13,
            color: context.colors.textMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '日志仅保存在本机，不会自动上传。反馈问题时请导出后发送给开发者。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: context.colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 44,
            color: context.colors.success.withOpacity(0.7),
          ),
          const SizedBox(height: 12),
          Text(
            '暂无错误日志',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '应用运行正常，没有记录到问题',
            style: TextStyle(fontSize: 12.5, color: context.colors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// 单条日志（点击展开完整消息与结构化信息）
class LogTile extends StatefulWidget {
  const LogTile({super.key, required this.entry});

  final LogEntry entry;

  @override
  State<LogTile> createState() => _LogTileState();
}

class _LogTileState extends State<LogTile> {
  bool _expanded = false;

  Color _levelColor(AppPalette c) => switch (widget.entry.level) {
        LogLevel.fatal || LogLevel.error => c.error,
        LogLevel.warning => c.warning,
        LogLevel.info => c.accent,
      };

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final color = _levelColor(context.colors);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _LevelChip(level: e.level, color: color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e.tag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: context.colors.textMuted,
                            ),
                          ),
                        ),
                        Text(
                          formatLogTime(e.time),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: context.colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      e.message,
                      maxLines: _expanded ? null : 3,
                      overflow: _expanded ? null : TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: context.colors.textSecondary,
                      ),
                    ),
                    if (_expanded && e.meta.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final kv in e.meta.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '${kv.key}: ${kv.value}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: context.colors.textMuted,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level, required this.color});

  final LogLevel level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        level.label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// 底部动作栏（导出 / 复制全部）
class ActionBar extends StatelessWidget {
  const ActionBar({super.key,
    required this.enabled,
    required this.onExport,
    required this.onCopy,
  });

  final bool enabled;
  final Future<void> Function() onExport;
  final Future<void> Function() onCopy;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: context.colors.background,
          border: Border(
            top: BorderSide(color: context.colors.outline, width: 0.6),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: _BarButton(
                icon: Icons.ios_share_rounded,
                label: '导出日志',
                primary: true,
                onTap: enabled ? () => onExport() : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _BarButton(
                icon: Icons.copy_all_rounded,
                label: '复制全部',
                primary: false,
                onTap: enabled ? () => onCopy() : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.primary,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? context.colors.accent : context.colors.surface;
    final fg = primary ? Colors.white : context.colors.textSecondary;
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
