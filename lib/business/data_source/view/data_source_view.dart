import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../component/theme/app_palette.dart';
import '../../../foundation/constants/app_strings.dart';
import '../model/data_source.dart';
import '../view_model/data_source_provider.dart';
import '../service/data_source_interface.dart';

class SourceTile extends StatelessWidget {
  const SourceTile({super.key, required this.config});

  final DataSourceConfig config;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: _buildLeading(context),
        title: _buildTitle(context),
        subtitle: _buildSubtitle(context),
        trailing: _buildTrailing(context, testing),
        onTap: () => _openEditor(context),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    final ds = context.read<DataSourceProvider>();
    final saved = await showModalBottomSheet<DataSourceConfig>(
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
        isNew: false,
        provider: ds,
      ),
    );
    if (saved != null && context.mounted) {
      await ds.updateSource(saved);
    }
  }

  /// 单选：设为该类别默认源。
  Widget _buildLeading(BuildContext context) {
    final c = context.colors;
    final ds = context.read<DataSourceProvider>();
    return Radio<String>(
      value: config.id,
      groupValue: ds.sourcesOf(config.category).any((s) => s.isDefault)
          ? ds.sourcesOf(config.category).firstWhere((s) => s.isDefault).id
          : null,
      activeColor: c.accent,
      onChanged: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          await ds.setDefault(config.id);
          messenger.showSnackBar(
            SnackBar(content: Text('已将「${config.name}」设为默认')),
          );
        } on Object catch (e) {
          messenger.showSnackBar(
            SnackBar(content: Text('设置默认源失败：$e')),
          );
        }
      },
    );
  }

  /// 名称（默认源附「默认」徽标）。
  Widget _buildTitle(BuildContext context) {
    final c = context.colors;
    return Row(
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
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
    );
  }

  /// 状态圆点 + 摘要文案。
  Widget _buildSubtitle(BuildContext context) {
    final c = context.colors;
    return Padding(
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
    );
  }

  /// 测试连接中的转圈 / 常态右箭头。
  Widget _buildTrailing(BuildContext context, bool testing) {
    final c = context.colors;
    return testing
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: c.accent,
            ),
          )
        : Icon(Icons.chevron_right_rounded, size: 20, color: c.textMuted);
  }

}

/// 状态圆点 + 文字徽标
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final DataSourceStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      DataSourceStatus.connected => context.colors.success,
      DataSourceStatus.notConfigured => context.colors.textMuted,
      DataSourceStatus.inactive => context.colors.warning,
      DataSourceStatus.timeout => context.colors.warning,
      DataSourceStatus.error => context.colors.error,
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
class SourceEditSheet extends StatefulWidget {
  const SourceEditSheet({
    super.key,
    required this.config,
    required this.isNew,
    required DataSourceProvider provider,
  }) : _provider = provider;

  final DataSourceConfig config;
  final bool isNew;
  final DataSourceProvider _provider;

  @override
  State<SourceEditSheet> createState() => _SourceEditSheetState();
}

class _SourceEditSheetState extends State<SourceEditSheet> {
  late final DataSourceProvider _ds = widget._provider;
  late final DataSourceConfig _config = widget.config;

  late final TextEditingController _nameCtrl =
      TextEditingController(text: _config.name);
  // L-4：容器字段**非空且提前建好**（不再 `late final` 待 initState 赋值）。
  // configFieldsOf 若对未知类型抛错，initState 会在容器仍为空时中断，
  // 此时 dispose 遍历空容器即可安全返回——不会二次抛 LateInitializationError
  // 掩盖原始异常（旧写法把这两个 map 声明成 `late final`，正是这个隐患）。
  List<ConfigField> _fields = const [];
  final Map<String, TextEditingController> _plainCtrls = {};
  final Map<String, TextEditingController> _secretCtrls = {};
  late final Map<String, bool> _secretVisible;

  /// 防止异步操作连击
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 字段描述由 Manager 注册表提供——经 Provider 转发（避免暴露 manager）
    // 可能抛错的调用放在容器就绪之后。
    _fields = _ds.configFieldsOf(_config.type);
    for (final f in _fields) {
      if (f.isSecret) {
        _secretCtrls[f.key] = TextEditingController();
      } else {
        _plainCtrls[f.key] = TextEditingController(
          text: _config.config[f.key]?.toString() ?? '',
        );
      }
    }
    for (final f in _fields.where((f) => f.isSecret)) {
      _secretModified[f.key] = false;
      _secretCtrls[f.key]!.addListener(() {
        if (_secretCtrls[f.key]!.text != _kSecretMask) {
          _secretModified[f.key] = true;
        }
      });
    }
    _secretVisible = {
      for (final f in _fields)
        if (f.isSecret) f.key: false
    };
    // 预填 secret 字段的掩码占位（已有凭据时显示「已保存」态）
    _loadSecretMask();
  }

  Future<void> _loadSecretMask() async {
    for (final f in _fields.where((f) => f.isSecret)) {
      final existing = await _ds.readCredential(_config, f.key);
      if (!mounted) return;
      if (existing != null && existing.isNotEmpty) {
        setState(() {
          _secretCtrls[f.key]!.text = _kSecretMask;
          _secretFilled[f.key] = true;
          _secretModified[f.key] = false;
        });
      }
    }
  }

  static const _kSecretMask = '••••••••';

  /// 已保存的凭据标记（掩码展示；重新输入则覆盖）
  final Map<String, bool> _secretFilled = {};
  final Map<String, bool> _secretModified = {};

  @override
  void dispose() {
    _nameCtrl.dispose();
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _doSave();
    } on Object catch (e) {
      if (mounted) _toast(AppStrings.saveFailed(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doSave() async {
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
        final isMask = typed == _kSecretMask;
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
      if (typed.isNotEmpty && typed != _kSecretMask) {
        await _ds.saveCredential(_config, f.key, typed);
      }
    }
    if (mounted) {
      Navigator.of(context).pop(newConfig);
    }
  }

  Future<void> _testConnection() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
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
        if (typed.isNotEmpty && typed != _kSecretMask) {
          await _ds.saveCredential(_config, f.key, typed);
        }
      }
      // 新增流程：草稿未落盘，走 testDraft（配置/凭据按草稿直接测试）；
      // 编辑流程：先落盘草稿再按 id 测试，保证列表状态同步更新
      final bool ok;
      if (widget.isNew) {
        ok = await _ds.testDraft(draft);
      } else {
        await _ds.updateSource(draft);
        ok = await _ds.testSource(_config.id);
      }
      if (!mounted) return;
      final matches =
          _ds.configs.where((c) => c.id == _config.id).toList(growable: false);
      final latest = matches.isEmpty ? null : matches.first;
      _toast(ok ? '连接成功 ✓' : (latest?.summary ?? _ds.actionError ?? '连接失败'));
      if (ok) {
        Navigator.of(context)
            .pop(draft.copyWith(status: DataSourceStatus.connected));
      }
    } on Object catch (e) {
      if (mounted) _toast('测试失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
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
            child:
                Text('取消', style: TextStyle(color: context.colors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              '删除',
              style: TextStyle(
                color: context.colors.danger,
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDragHandle(context),
              ..._buildTitleSection(context),
              const SizedBox(height: 14),
              _buildNameField(context),
              const SizedBox(height: 10),
              ..._buildFields(context),
              const SizedBox(height: 6),
              _buildActionButtons(context),
              if (!widget.isNew) ...[
                const SizedBox(height: 10),
                _buildDeleteButton(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // 拖拽指示条（与编辑资料/查看资料统一风格）
  Widget _buildDragHandle(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: c.outline,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  /// 标题 + 数据源类型名。
  List<Widget> _buildTitleSection(BuildContext context) {
    final c = context.colors;
    return [
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
    ];
  }

  /// 名称输入框。
  Widget _buildNameField(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: _nameCtrl,
      style: TextStyle(color: c.textPrimary, fontSize: 14),
      cursorColor: c.accent,
      decoration: _dec(const ConfigField(
        key: '__name',
        label: '显示名称',
      )),
    );
  }

  /// 动态字段列表（普通字段明文 / secret 字段掩码态）。
  List<Widget> _buildFields(BuildContext context) {
    final c = context.colors;
    return [
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
    ];
  }

  /// 底部操作区：测试连接 / 保存（新增为添加）。
  Widget _buildActionButtons(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _testConnection,
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
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: _busy ? null : _save,
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
    );
  }

  /// 删除入口（仅编辑态显示）。
  Widget _buildDeleteButton(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: _busy ? null : _delete,
        style: TextButton.styleFrom(
          foregroundColor: context.colors.danger,
          padding: const EdgeInsets.symmetric(vertical: 6),
        ),
        icon: const Icon(Icons.delete_outline_rounded, size: 16),
        label: const Text('删除此数据源',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
