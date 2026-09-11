import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_palette.dart';
import '../data/deploy_guide.dart';

/// 弹出「数据源自建部署指南」底部弹层。
///
/// 入口：数据源管理页 AppBar 右上角的 ❓（见 `data_source_screen.dart`）。
/// 内容：[kDataSourceDeployGuide] 经 flutter_markdown 渲染；文内链接
/// （GitHub / Render / UptimeRobot）交给系统浏览器打开。
///
/// 用 [DraggableScrollableSheet] 承载：可上下拖拽改变高度，内容超屏时
/// 内部 `Markdown`（本质是 ListView）随 [ScrollController] 滚动。
Future<void> showDataSourceGuideSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // 透明底：圆角与配色由内部 Container 控制
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) =>
          _GuideSheet(scrollController: scrollController),
    ),
  );
}

class _GuideSheet extends StatelessWidget {
  const _GuideSheet({required this.scrollController});

  final ScrollController scrollController;

  /// 用外部浏览器打开文内链接；失败（无浏览器 / 非法 URL）时给中文提示。
  ///
  /// 先取 [ScaffoldMessenger] 再 await —— 避免 await 后 context 失效。
  Future<void> _openLink(BuildContext context, String? href) async {
    final messenger = ScaffoldMessenger.of(context);
    final raw = href?.trim() ?? '';
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text('无法打开链接：$raw')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 拖拽指示条
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 10),
            decoration: BoxDecoration(
              color: c.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 6, 6),
            child: Row(
              children: [
                Icon(Icons.auto_stories_rounded, size: 18, color: c.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '数据源配置教程',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 20, color: c.textMuted),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.outline),
          Expanded(
            child: Markdown(
              controller: scrollController,
              data: kDataSourceDeployGuide,
              // 允许长按复制域名 / Dockerfile
              selectable: true,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              styleSheet: _styleSheet(context),
              onTapLink: (text, href, title) => _openLink(context, href),
            ),
          ),
        ],
      ),
    );
  }

  /// 按当前主题（暗/浅）生成 Markdown 排版样式。
  ///
  /// 颜色一律取自 [AppPalette]（`context.colors`），主题切换自动重绘；
  /// 禁止硬编码色值，否则浅色主题下会「白底白字」。
  MarkdownStyleSheet _styleSheet(BuildContext context) {
    final c = context.colors;
    return MarkdownStyleSheet(
      h1: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w800,
        height: 1.35,
        color: c.textPrimary,
      ),
      h1Padding: const EdgeInsets.only(top: 2, bottom: 8),
      h2: TextStyle(
        fontSize: 16.5,
        fontWeight: FontWeight.w800,
        height: 1.4,
        color: c.accent,
      ),
      h2Padding: const EdgeInsets.only(top: 20, bottom: 8),
      h3: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w700,
        color: c.textPrimary,
      ),
      h3Padding: const EdgeInsets.only(top: 14, bottom: 6),
      p: TextStyle(fontSize: 13.5, height: 1.75, color: c.textSecondary),
      listBullet:
          TextStyle(fontSize: 13.5, height: 1.75, color: c.textSecondary),
      listIndent: 22,
      blockSpacing: 10,
      strong: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary),
      em: TextStyle(fontStyle: FontStyle.italic, color: c.textSecondary),
      a: TextStyle(
        color: c.accent,
        decoration: TextDecoration.underline,
        decorationColor: c.accent,
      ),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 12.5,
        color: c.accent,
        backgroundColor: c.surface,
      ),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.outline, width: 0.8),
      ),
      blockquote: TextStyle(fontSize: 12.5, height: 1.7, color: c.textMuted),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      blockquoteDecoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: c.accent, width: 3)),
      ),
      tableHead: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: c.textPrimary,
      ),
      tableBody: TextStyle(fontSize: 13, color: c.textSecondary),
      tableBorder: TableBorder.all(color: c.outline, width: 0.8),
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      tableColumnWidth: const IntrinsicColumnWidth(),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.outline, width: 0.8)),
      ),
    );
  }
}
