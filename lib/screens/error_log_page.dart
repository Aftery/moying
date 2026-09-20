import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_palette.dart';
import '../services/app_logger.dart';
import '../services/log_exporter.dart';
import 'error_log_widgets.dart';

/// 错误日志页 —— 查看 / 导出本机记录的应用与请求错误
///
/// **纯本地**：日志只写在设备上，本页不上传任何数据；用户可通过
/// 「导出日志」（系统分享面板）或「复制全部」（剪贴板）把内容反馈给开发者。
class ErrorLogPage extends StatefulWidget {
  const ErrorLogPage({super.key});

  @override
  State<ErrorLogPage> createState() => _ErrorLogPageState();
}

class _ErrorLogPageState extends State<ErrorLogPage> {
  String _stamp() {
    final now = DateTime.now();
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${p2(now.month)}${p2(now.day)}-'
        '${p2(now.hour)}${p2(now.minute)}';
  }

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = 'moying-error-log-${_stamp()}.txt';
    final text = AppLogger.instance.exportText();
    try {
      final saved = await exportLogText(text, name);
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('已生成日志文件：$saved')));
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _copyAll() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(text: AppLogger.instance.exportText()),
    );
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('日志已复制到剪贴板')));
  }

  /// 清空内存缓冲与落盘历史
  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceHigh,
        title: Text(
          '清空日志？',
          style: TextStyle(color: context.colors.textPrimary),
        ),
        content: Text(
          '清空后无法恢复，建议先导出或复制再清空。',
          style: TextStyle(color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              '取消',
              style: TextStyle(color: context.colors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '清空',
              style: TextStyle(
                color: context.colors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppLogger.instance.clear();
    // 不需要手动 refresh，订阅会自动更新
  }

  @override
  Widget build(BuildContext context) {
    final logger = AppLogger.instance;
    // 整页订阅 logger：新日志落缓冲后自动刷新（清空按钮显隐 / 列表 / 统计头一并联动）
    return ListenableBuilder(
      listenable: logger,
      builder: (_, __) {
        final entries = logger.entries;
        return Scaffold(
          appBar: AppBar(
            title: const Text('错误日志'),
            actions: [
              if (entries.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: '清空日志',
                  onPressed: _clear,
                ),
            ],
          ),
          body: Column(
            children: [
              SummaryHeader(
                total: logger.totalCount,
                problems: logger.problemCount,
                warnings: logger.warningCount,
                environment: logger.environmentDescription,
              ),
              const HintBar(),
              Expanded(
                child: entries.isEmpty
                    ? const EmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        itemCount: entries.length,
                        itemBuilder: (_, i) {
                          // 最新在最上
                          final entry = entries[entries.length - 1 - i];
                          return LogTile(entry: entry);
                        },
                      ),
              ),
              ActionBar(
                enabled: entries.isNotEmpty,
                onExport: _export,
                onCopy: _copyAll,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 顶部统计（错误/警告/总数 + 运行环境）
