import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../models/data_source.dart';
import '../providers/data_source_provider.dart';
import '../services/data_source_interface.dart';
import '../widgets/data_source_guide_sheet.dart';
import 'data_source_widgets.dart';

/// 数据源管理 —— 影视 / 书籍两类源的增删改、默认源选择与连接测试
///
/// 布局对齐截图（影视数据源 + 书籍数据源两个区块）：
/// - 每行：单选（设为默认）+ 名称 + 状态徽标 + 配置摘要 + 编辑入口
/// - 「+ 添加」：内置类型选择（豆瓣后续迭代开放）
/// - 编辑弹窗：动态渲染 [ConfigField]（secret 字段密文输入），支持测试连接
class DataSourcePage extends StatelessWidget {
  const DataSourcePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ds = context.watch<DataSourceProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据源管理'),
        actions: [
          // ❓ 帮助：弹出「自建部署指南」（GitHub + Render 免费托管豆瓣代理）
          IconButton(
            icon: const Icon(Icons.help_outline_rounded),
            tooltip: '如何配置数据源',
            onPressed: () => showDataSourceGuideSheet(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _section(
            context,
            icon: Icons.movie_outlined,
            title: DataSourceCategory.movie.label,
            sources: ds.sourcesOf(DataSourceCategory.movie),
          ),
          _addButton(context, DataSourceCategory.movie),
          const SizedBox(height: 24),
          _section(
            context,
            icon: Icons.menu_book_outlined,
            title: DataSourceCategory.book.label,
            sources: ds.sourcesOf(DataSourceCategory.book),
          ),
          _addButton(context, DataSourceCategory.book),
          const SizedBox(height: 24),
          // 操作错误提示（测试连接 / 配置保存失败）
          if (ds.actionError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                ds.actionError!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.error,
                ),
              ),
            ),
          Text(
            '凭据（API Key / Token）保存在系统安全存储中，备份文件不包含这些信息',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.6,
              color: context.colors.textMuted.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 区块 ----------

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<DataSourceConfig> sources,
  }) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: c.accent),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (sources.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '暂无数据源，点击下方按钮添加',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: c.textMuted),
            ),
          )
        else
          ...sources.map((s) => SourceTile(config: s)),
      ],
    );
  }

  Widget _addButton(BuildContext context, DataSourceCategory category) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: TextButton.icon(
          onPressed: () => _showAddSheet(context, category),
          style: TextButton.styleFrom(
            foregroundColor: context.colors.accent,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
          label: Text(
            category == DataSourceCategory.movie
                ? '添加影视数据源'
                : '添加书籍数据源',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  // ---------- 添加数据源（直接弹自定义配置表单）----------

  /// 点击「添加影视/书籍数据源」→ 直接进入自定义 API 配置表单，
  /// 不再先选类型——自定义源通过 Base URL + API Key 对接用户自建服务，
  /// 返回数据由智能解析器启发式提取。
  Future<void> _showAddSheet(
    BuildContext context,
    DataSourceCategory category,
  ) async {
    final ds = context.read<DataSourceProvider>();
    final type = category == DataSourceCategory.movie
        ? DataSourceType.customMovie
        : DataSourceType.customBook;
    final id = 'user_${type.name}_${DateTime.now().millisecondsSinceEpoch}';
    var config = DataSourceConfig(
      id: id,
      type: type,
      name: type.displayName,
      status: DataSourceStatus.inactive,
    );
    final saved = await _showEditSheet(context, config, isNew: true);
    if (saved != null) {
      config = saved;
      await ds.addSource(config);
    }
  }

  // ---------- 编辑 / 配置弹层（添加与编辑共用）----------

  /// 返回编辑后的配置（取消返回 null；isNew 时不落盘，由调用方 addSource）
  Future<DataSourceConfig?> _showEditSheet(
    BuildContext context,
    DataSourceConfig config, {
    required bool isNew,
  }) {
    final ds = context.read<DataSourceProvider>();
    return showModalBottomSheet<DataSourceConfig>(
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
      builder: (ctx) => SourceEditSheet(
        config: config,
        isNew: isNew,
        provider: ds,
      ),
    );
  }
}

/// 数据源单行（单选默认 + 状态徽标 + 摘要 + 编辑）
