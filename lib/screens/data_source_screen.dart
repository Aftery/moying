import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_palette.dart';
import '../models/data_source.dart';
import '../providers/data_source_provider.dart';
import '../services/data_source_interface.dart';

/// 数据源管理 —— 影视 / 书籍两类源的增删改、默认源选择与连接测试
///
/// 布局对齐截图（影视数据源 + 书籍数据源两个区块）：
/// - 每行：单选（设为默认）+ 名称 + 状态徽标 + 配置摘要 + 编辑入口
/// - 「+ 添加」：内置类型选择（豆瓣后续迭代开放）
/// - 编辑弹窗：动态渲染 [ConfigField]（secret 字段密文输入），支持测试连接
class DataSourceScreen extends StatelessWidget {
  const DataSourceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ds = context.watch<DataSourceProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('数据源管理')),
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
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFFF6B6B),
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
          ...sources.map((s) => _SourceTile(config: s)),
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

  // ---------- 添加数据源（类型选择弹层）----------

  Future<void> _showAddSheet(
    BuildContext context,
    DataSourceCategory category,
  ) async {
    final ds = context.read<DataSourceProvider>();
    // 各类别当前可添加的内置类型（豆瓣后续迭代，占位禁用）
    final candidates = DataSourceType.values
        .where((t) => t.category == category)
        .toList()
      ..sort((a, b) {
        // 已存在同类型源的类型排后（不禁止重复添加——用户可能配多个节点）
        final aExists = ds.sourcesOf(category).any((s) => s.type == a);
        final bExists = ds.sourcesOf(category).any((s) => s.type == b);
        if (aExists != bExists) return aExists ? 1 : -1;
        return 0;
      });

    final selected = await showModalBottomSheet<DataSourceType>(
      context: context,
      backgroundColor: context.colors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              '选择数据源类型',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            for (final type in candidates)
              ListTile(
                leading: Icon(
                  _typeIcon(type),
                  color: context.colors.accent,
                  size: 22,
                ),
                title: Text(
                  type.displayName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  _typeSubtitle(type),
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textMuted,
                  ),
                ),
                // 豆瓣：官方 API 已关闭，需自建代理 → 后续迭代开放
                enabled: type != DataSourceType.douban,
                trailing: type == DataSourceType.douban
                    ? Text(
                        '即将支持',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.textMuted,
                        ),
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: context.colors.textMuted,
                      ),
                onTap: () => Navigator.of(ctx).pop(type),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;

    final id = 'user_${selected.name}_${DateTime.now().millisecondsSinceEpoch}';
    var config = DataSourceConfig(
      id: id,
      type: selected,
      name: selected.displayName,
      status: DataSourceStatus.inactive,
    );
    final saved = await _showEditSheet(context, config, isNew: true);
    if (saved != null) {
      config = saved;
      await ds.addSource(config);
    }
  }

  IconData _typeIcon(DataSourceType type) => switch (type) {
        DataSourceType.tmdb => Icons.local_movies_outlined,
        DataSourceType.googleBooks => Icons.menu_book_outlined,
        DataSourceType.douban => Icons.bookmarks_outlined,
      };

  String _typeSubtitle(DataSourceType type) => switch (type) {
        DataSourceType.tmdb => '影视元数据最全，需免费申请 API Key',
        DataSourceType.googleBooks => '免 API Key，开箱即用',
        DataSourceType.douban => '官方 API 已关闭，需自建代理',
      };

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
      backgroundColor: context.colors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SourceEditSheet(
        config: config,
        isNew: isNew,
        provider: ds,
      ),
    );
  }
}

/// 数据源单行（单选默认 + 状态徽标 + 摘要 + 编辑）
class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.config});

  final DataSourceConfig config;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final ds = context.read<DataSourceProvider>();
    final testing = context.select<DataSourceProvider, bool>(
      (p) => p.testingId == config.id,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        // 单选：设为该类别默认源
        leading: Radio<String>(
          value: config.id,
          groupValue: ds.sourcesOf(config.category).any((s) => s.isDefault)
              ? ds.sourcesOf(config.category).firstWhere((s) => s.isDefault).id
              : null,
          activeColor: c.accent,
          onChanged: (_) async {
            final messenger = ScaffoldMessenger.of(context);
            await ds.setDefault(config.id);
            messenger.showSnackBar(
              SnackBar(content: Text('已将「${config.name}」设为默认')),
            );
          },
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                config.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
            ),
            if (config.isDefault) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: c.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '默认',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: c.accent,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            children: [
              _StatusDot(status: config.status),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  config.displaySummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ),
            ],
          ),
        ),
        trailing: testing
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.accent,
                ),
              )
            : Icon(Icons.chevron_right_rounded, size: 20, color: c.textMuted),
        onTap: () => _openEditor(context),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    final ds = context.read<DataSourceProvider>();
    final saved = await showModalBottomSheet<DataSourceConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surfaceHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SourceEditSheet(
        config: config,
        isNew: false,
        provider: ds,
      ),
    );
    if (saved != null && context.mounted) {
      await ds.updateSource(saved);
    }
  }
}

/// 状态圆点 + 文字徽标
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final DataSourceStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      DataSourceStatus.connected => const Color(0xFF4CD97B),
      DataSourceStatus.notConfigured => context.colors.textMuted,
      DataSourceStatus.inactive => const Color(0xFFFFB020),
      DataSourceStatus.timeout => const Color(0xFFFFB020),
      DataSourceStatus.error => const Color(0xFFFF6B6B),
    };
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ==================== 编辑弹层 ====================

/// 数据源配置编辑（添加 / 编辑共用）
///
/// - 动态渲染数据源的 [ConfigField]：普通字段写 config，secret 字段走
///   Provider 凭据通道（安全存储）；
/// - 保存返回配置实例；编辑态额外提供「测试连接」与「删除」。
class _SourceEditSheet extends StatefulWidget {
  const _SourceEditSheet({
    required this.config,
    required this.isNew,
    required DataSourceProvider provider,
  }) : _provider = provider;

  final DataSourceConfig config;
  final bool isNew;
  final DataSourceProvider _provider;

  @override
  State<_SourceEditSheet> createState() => _SourceEditSheetState();
}

class _SourceEditSheetState extends State<_SourceEditSheet> {
  late final DataSourceProvider _ds = widget._provider;
  late final DataSourceConfig _config = widget.config;

  late final List<ConfigField> _fields;
  late final Map<String, TextEditingController> _plainCtrls;
  late final Map<String, TextEditingController> _secretCtrls;
  late final Map<String, bool> _secretVisible;

  @override
  void initState() {
    super.initState();
    // 字段描述由 Manager 注册表提供——经 Provider 转发（避免暴露 manager）
    _fields = _ds.configFieldsOf(_config.type);
    _plainCtrls = {
      for (final f in _fields)
        if (!f.isSecret)
          f.key: TextEditingController(
            text: _config.config[f.key]?.toString() ?? '',
          ),
    };
    _secretCtrls = {
      for (final f in _fields)
        if (f.isSecret) f.key: TextEditingController(),
    };
    _secretVisible = {for (final f in _fields) if (f.isSecret) f.key: false};
    // 预填 secret 字段的掩码占位（已有凭据时显示「已保存」态）
    _loadSecretMask();
  }

  Future<void> _loadSecretMask() async {
    for (final f in _fields.where((f) => f.isSecret)) {
      final existing = await _ds.readCredential(_config, f.key);
      if (!mounted) return;
      if (existing != null && existing.isNotEmpty) {
        setState(() {
          _secretCtrls[f.key]!.text = '••••••••';
          _secretFilled[f.key] = true;
        });
      }
    }
  }

  /// 已保存的凭据标记（掩码展示；重新输入则覆盖）
  final Map<String, bool> _secretFilled = {};

  @override
  void dispose() {
    for (final c in _plainCtrls.values) {
      c.dispose();
    }
    for (final c in _secretCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  InputDecoration _dec(ConfigField f) {
    final c = context.colors;
    return InputDecoration(
      labelText: f.label + (f.required ? ' *' : ''),
      labelStyle: TextStyle(color: c.textMuted, fontSize: 13),
      hintText: f.hint,
      hintStyle: TextStyle(color: c.textMuted.withOpacity(0.7), fontSize: 13),
      filled: true,
      fillColor: c.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
        borderSide: BorderSide(color: c.accent, width: 1.2),
      ),
      suffixIcon: f.isSecret
          ? IconButton(
              icon: Icon(
                _secretVisible[f.key] ?? false
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 18,
                color: c.textMuted,
              ),
              onPressed: () => setState(
                () => _secretVisible[f.key] = !(_secretVisible[f.key] ?? false),
              ),
            )
          : null,
    );
  }

  Future<void> _save() async {
    final name = (_nameCtrl.text).trim();
    if (name.isEmpty) {
      _toast('名称不能为空');
      return;
    }
    // 必填校验：required 且非 secret 的看 plain 输入；secret 的看凭据/掩码
    for (final f in _fields.where((f) => f.required)) {
      if (f.isSecret) {
        final hasMask = _secretFilled[f.key] ?? false;
        final typed = _secretCtrls[f.key]!.text.trim();
        final isMask = typed == '••••••••';
        if (!hasMask && (typed.isEmpty || isMask)) {
          _toast('请填写 ${f.label}');
          return;
        }
      } else if (_plainCtrls[f.key]!.text.trim().isEmpty) {
        _toast('请填写 ${f.label}');
        return;
      }
    }

    // 组装新配置（非 secret 字段进 config）
    final newConfig = _config.copyWith(
      name: name,
      config: {
        for (final e in _plainCtrls.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
      },
      clearSummary: true,
    );
    // secret 字段写入安全存储（掩码态不覆盖）
    for (final f in _fields.where((f) => f.isSecret)) {
      final typed = _secretCtrls[f.key]!.text.trim();
      if (typed.isNotEmpty && typed != '••••••••') {
        await _ds.saveCredential(_config, f.key, typed);
      }
    }
    if (mounted) {
      Navigator.of(context).pop(newConfig);
    }
  }

  Future<void> _testConnection() async {
    // 先把当前表单内容落到 Provider（测试连接读取的是已保存配置）
    final name = (_nameCtrl.text).trim();
    final draft = _config.copyWith(
      name: name.isEmpty ? _config.name : name,
      config: {
        for (final e in _plainCtrls.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
      },
      clearSummary: true,
    );
    for (final f in _fields.where((f) => f.isSecret)) {
      final typed = _secretCtrls[f.key]!.text.trim();
      if (typed.isNotEmpty && typed != '••••••••') {
        await _ds.saveCredential(_config, f.key, typed);
      }
    }
    if (!widget.isNew) {
      await _ds.updateSource(draft);
    }
    final ok = await _ds.testSource(_config.id);
    if (!mounted) return;
    final matches =
        _ds.configs.where((c) => c.id == _config.id).toList(growable: false);
    final latest = matches.isEmpty ? null : matches.first;
    _toast(ok
        ? '连接成功 ✓'
        : (latest?.summary ?? _ds.actionError ?? '连接失败'));
    if (ok) {
      Navigator.of(context).pop(draft.copyWith(status: DataSourceStatus.connected));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surfaceHigh,
        title: Text(
          '删除数据源',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
          ),
        ),
        content: Text(
          '确定删除「${_config.name}」吗？相关凭据会一并清除。',
          style: TextStyle(fontSize: 13.5, color: context.colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: context.colors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '删除',
              style: TextStyle(
                color: Color(0xFFFF6B6B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _ds.removeSource(_config.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  late final TextEditingController _nameCtrl =
      TextEditingController(text: _config.name);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.isNew ? '配置数据源' : '编辑数据源',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _config.type.displayName,
                style: TextStyle(fontSize: 12.5, color: c.textMuted),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameCtrl,
                style: TextStyle(color: c.textPrimary, fontSize: 14),
                cursorColor: c.accent,
                decoration: _dec(const ConfigField(
                  key: '__name',
                  label: '显示名称',
                )),
              ),
              const SizedBox(height: 10),
              for (final f in _fields) ...[
                if (!f.isSecret)
                  TextField(
                    controller: _plainCtrls[f.key],
                    style: TextStyle(color: c.textPrimary, fontSize: 14),
                    cursorColor: c.accent,
                    decoration: _dec(f),
                  )
                else
                  TextField(
                    controller: _secretCtrls[f.key],
                    obscureText: !(_secretVisible[f.key] ?? false),
                    style: TextStyle(color: c.textPrimary, fontSize: 14),
                    cursorColor: c.accent,
                    decoration: _dec(f).copyWith(
                      helperText: (_secretFilled[f.key] ?? false)
                          ? '已保存（重新输入可覆盖）'
                          : null,
                    ),
                  ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testConnection,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.accent,
                        side: BorderSide(color: c.accent, width: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.wifi_tethering_rounded, size: 17),
                      label: const Text('测试连接',
                          style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: c.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        widget.isNew ? '添加' : '保存',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
              if (!widget.isNew) ...[
                const SizedBox(height: 10),
                Center(
                  child: TextButton.icon(
                    onPressed: _delete,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFFF6B6B),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('删除此数据源',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
