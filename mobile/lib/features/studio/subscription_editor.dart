import '../../ui/theme.dart';
import '../../ui/selection_sheet.dart';
import 'package:flutter/material.dart';
import 'source_selection.dart';
import 'subscription_style.dart';

class SubscriptionEditor extends StatefulWidget {
  const SubscriptionEditor({
    super.key,
    required this.snapshot,
    this.initialPluginId,
    this.saveSource,
    this.asSource = false,
    this.task,
    required this.save,
  });
  final Map<String, dynamic> snapshot;
  final String? initialPluginId;
  final bool asSource;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? saveSource;
  final Map<String, dynamic>? task;
  final Future<void> Function(Map<String, dynamic>) save;
  @override
  State<SubscriptionEditor> createState() => _SubscriptionEditorState();
}

class _SubscriptionEditorState extends State<SubscriptionEditor> {
  final form = GlobalKey<FormState>();
  late Map<String, dynamic> snapshotData = Map.from(widget.snapshot);
  late final name = TextEditingController(
    text: widget.task?['name'] as String? ?? '',
  );
  late final minutes = TextEditingController(
    text: '${(widget.task?['schedule'] as Map?)?['minutes'] ?? 60}',
  );
  late String pluginId =
      widget.task?['pluginId'] as String? ??
      widget.initialPluginId ??
      plugins.first['id'] as String;
  late String channelId =
      widget.task?['channelId'] as String? ??
      (studioItems(snapshotData['channels']).firstOrNull?['id'] as String? ??
          '');
  late String providerId = widget.task?['providerId'] as String? ?? '';
  late String scheduleType =
      (widget.task?['schedule'] as Map?)?['type'] as String? ?? 'manual';
  late bool enabled = widget.task?['enabled'] as bool? ?? !widget.asSource;
  late bool onlyChanged = widget.task?['onlyChanged'] != false;
  late List<String> times =
      ((widget.task?['schedule'] as Map?)?['times'] as List? ??
              [(widget.task?['schedule'] as Map?)?['time'] ?? '09:00'])
          .cast<String>()
          .toList();
  final Map<String, TextEditingController> fields = {};
  Map<String, dynamic> config = {};
  bool busy = false;
  String? error;
  List<Map<String, dynamic>> get plugins =>
      studioItems(snapshotData['plugins']);
  Map<String, dynamic> get plugin =>
      plugins.firstWhere((entry) => entry['id'] == pluginId);

  @override
  void initState() {
    super.initState();
    resetConfig(widget.task?['config'] as Map? ?? {});
  }

  void resetConfig(Map value) {
    for (final controller in fields.values) {
      controller.dispose();
    }
    fields.clear();
    config = Map<String, dynamic>.from(value);
    for (final field in studioItems(plugin['fields'])) {
      final key = field['key'] as String;
      final initial = config[key] ?? field['default'];
      switch (field['type']) {
        case 'boolean':
          config[key] = initial == true;
        case 'select':
        case 'aiProvider':
          config[key] = '${initial ?? ''}';
        case 'stringList':
          final text = initial is List
              ? initial.map((e) => '$e').join('\n')
              : '${initial ?? ''}';
          fields[key] = TextEditingController(text: text);
        case 'secret':
          // Never backfill saved secret values; empty means keep existing.
          fields[key] = TextEditingController(text: '');
        case 'tasks':
          config[key] = (initial as String? ?? '')
              .split(',')
              .where((id) => id.isNotEmpty)
              .toSet();
        default:
          fields[key] = TextEditingController(text: '${initial ?? ''}');
      }
    }
  }

  @override
  void dispose() {
    name.dispose();
    minutes.dispose();
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final values = Map<String, dynamic>.from(config);
      for (final field in studioItems(plugin['fields'])) {
        final key = field['key'] as String;
        if (field['type'] == 'tasks') {
          values[key] = (config[key] as Set<String>).join(',');
        } else if (field['type'] == 'stringList' && fields.containsKey(key)) {
          values[key] = fields[key]!.text
              .split(RegExp(r'\r?\n'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
        } else if (fields.containsKey(key)) {
          values[key] = field['type'] == 'number'
              ? num.parse(fields[key]!.text)
              : fields[key]!.text;
        }
      }
      await widget.save({
        if (snapshotData['revision'] != null)
          'revision': snapshotData['revision'],
        if (widget.task != null) 'id': widget.task!['id'],
        'name': name.text.trim(),
        'pluginId': pluginId,
        'channelId': channelId,
        'providerId': providerId,
        'enabled': enabled,
        'onlyChanged': onlyChanged,
        'config': values,
        'schedule': {
          'type': scheduleType,
          if (scheduleType == 'interval') 'minutes': int.parse(minutes.text),
          if (scheduleType == 'daily') 'times': times,
        },
      });
      if (mounted) {
        if (!widget.asSource) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('服务器已保存任务')));
        }
        Navigator.pop(context);
      }
    } catch (failure) {
      if (mounted) {
        setState(
          () => error = '${studioError(failure)}\n若提示设置已变化，请返回列表刷新后重新编辑。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget choice(
    String label,
    String value,
    List<Map<String, dynamic>> entries,
    ValueChanged<String> change, {
    bool optional = false,
    bool locked = false,
  }) {
    final values = [
      if (optional) {'id': '', 'name': '不使用 AI'},
      ...entries,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SheetSelectField(
        key: ValueKey('$label/$value'),
        label: label,
        value: values.any((e) => e['id'] == value) ? value : null,
        choices: [
          for (final entry in values)
            SheetChoice(
              value: entry['id'] as String,
              label: entry['name'] as String,
              description: entry['description'] as String?,
            ),
        ],
        onChanged: locked ? null : (next) => setState(() => change(next)),
        validator: (selected) =>
            selected == null || (!optional && selected.isEmpty)
            ? '请选择$label'
            : null,
      ),
    );
  }

  Widget pluginField(Map<String, dynamic> field) {
    final key = field['key'] as String;
    final label = field['label'] as String;
    if (field['type'] == 'account') {
      return const SizedBox.shrink();
    }
    if (field['type'] == 'boolean') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: config[key] == true,
        onChanged: (v) => setState(() => config[key] = v),
      );
    }
    if (field['type'] == 'tasks') {
      final selected = config[key] as Set<String>;
      final tasks = studioItems(snapshotData['tasks']);
      return FormField<Set<String>>(
        key: ValueKey('digest-sources/${selected.join(',')}'),
        initialValue: selected,
        validator: (_) =>
            selected.isEmpty || selected.length > 8 ? '请选择 1–8 个内容源' : null,
        builder: (state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '内容源 · ${selected.length}/8',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('最多选择 8 个来源，由汇总统一执行。'),
            const SizedBox(height: 12),
            for (final id in selected)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(
                    tasks.where((task) => task['id'] == id).firstOrNull?['name']
                            as String? ??
                        '来源已删除，请移除后重选',
                  ),
                  trailing: IconButton(
                    tooltip: '移除内容源',
                    onPressed: () => setState(() => selected.remove(id)),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            if (state.errorText != null)
              Text(
                state.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.checklist),
              label: const Text('选择已有任务'),
              onPressed: () async {
                final result = await selectDigestSources(
                  context: context,
                  tasks: tasks,
                  plugins: plugins,
                  selected: selected,
                  digestId: widget.task?['id'] as String?,
                );
                if (result != null && mounted) {
                  setState(() => config[key] = result);
                }
              },
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.add),
              label: const Text('添加内容源'),
              onPressed: widget.saveSource == null || selected.length >= 8
                  ? null
                  : () => addSource(key),
            ),
          ],
        ),
      );
    }
    if (field['type'] == 'aiProvider') {
      final providers = studioItems(snapshotData['providers']);
      final current = config[key] as String? ?? '';
      final requiredField = field['required'] == true;
      final choices = [
        if (!requiredField) const SheetChoice(value: '', label: '不使用 AI'),
        for (final p in providers)
          SheetChoice(
            value: '${p['id']}',
            label: '${p['name']}',
            description: p['model'] as String?,
          ),
      ];
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetSelectField(
              key: ValueKey('$pluginId/$key/$current'),
              label: label,
              value: choices.any((c) => c.value == current) ? current : null,
              choices: choices,
              onChanged: (next) => setState(() => config[key] = next),
              validator: (selected) =>
                  requiredField && (selected == null || selected.isEmpty)
                  ? '请选择$label'
                  : null,
            ),
            if (providers.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '服务器尚未添加 AI 服务商，可在订阅管理右上角「服务器配置」中添加。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    if (field['type'] == 'select') {
      final options = studioItems(field['options']);
      final current = config[key] as String? ?? '';
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: SheetSelectField(
          key: ValueKey('$pluginId/$key/$current'),
          label: label,
          value: options.any((o) => '${o['value']}' == current)
              ? current
              : null,
          choices: [
            for (final opt in options)
              SheetChoice(
                value: '${opt['value']}',
                label: '${opt['label']}',
                description: opt['description'] as String?,
              ),
          ],
          onChanged: (next) => setState(() => config[key] = next),
          validator: (selected) =>
              field['required'] == true &&
                  (selected == null || selected.isEmpty)
              ? '请选择$label'
              : null,
        ),
      );
    }
    final isSecret = field['type'] == 'secret';
    final hasSavedSecret = isSecret && config[key] == true;
    final multiline =
        field['type'] == 'textarea' || field['type'] == 'stringList';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        key: ValueKey('$pluginId/$key'),
        controller: fields[key],
        obscureText: isSecret,
        decoration: InputDecoration(
          labelText: hasSavedSecret ? '$label（已保存，留空保持不变）' : label,
          hintText: field['placeholder'] as String?,
          suffixIcon: (field['help'] as String? ?? '').isEmpty
              ? null
              : IconButton(
                  tooltip: '$label说明',
                  icon: const Icon(Icons.help_outline, size: 20),
                  onPressed: () => showAppSheet<void>(
                    context: context,
                    builder: (_) => SheetDialog(
                      title: Text(label),
                      content: Text(field['help'] as String),
                    ),
                  ),
                ),
        ),
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 6 : 1,
        keyboardType: field['type'] == 'number'
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : multiline
            ? TextInputType.multiline
            : TextInputType.text,
        validator: (value) {
          if (field['required'] == true &&
              !hasSavedSecret &&
              (value == null || value.trim().isEmpty)) {
            return '请填写$label';
          }
          if (field['type'] == 'number' &&
              (value ?? '').trim().isNotEmpty &&
              num.tryParse(value!) == null) {
            return '请输入数字';
          }
          return null;
        },
      ),
    );
  }

  Future<void> addSource(String key) async {
    final id = await showChoiceSheet<String>(
      context: context,
      title: '选择来源插件',
      choices: [
        for (final entry in plugins.where(
          (entry) => entry['id'] != digestPluginId && entry['legacy'] != true,
        ))
          SheetChoice(
            value: entry['id'] as String,
            label: entry['name'] as String,
            description: entry['description'] as String?,
          ),
      ],
    );
    if (id == null || !mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SubscriptionEditor(
          snapshot: snapshotData,
          initialPluginId: id,
          asSource: true,
          save: (values) async {
            final before = studioItems(
              snapshotData['tasks'],
            ).map((task) => task['id']).toSet();
            final result = await widget.saveSource!(values);
            if (!mounted) return;
            final added = studioItems(
              result['tasks'],
            ).where((task) => !before.contains(task['id'])).firstOrNull;
            setState(() {
              snapshotData = result;
              if (added != null) {
                (config[key] as Set<String>).add(added['id'] as String);
              }
            });
          },
        ),
      ),
    );
  }

  Future<void> addTime() async {
    final time = await showTimeSheet(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null || !mounted) return;
    final text =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    if (!times.contains(text)) {
      setState(() {
        times.add(text);
        times.sort();
      });
    }
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pluginFields = studioItems(plugin['fields']);
    final caps = (plugin['capabilities'] as List? ?? []);
    final aiFields = pluginFields
        .where((f) => f['type'] == 'aiProvider')
        .toList();
    final supportsAI =
        aiFields.isNotEmpty ||
        caps.contains('ai.required') ||
        caps.contains('ai.optional') ||
        caps.contains('ai.tools');
    final requiresAI =
        aiFields.any((f) => f['required'] == true) ||
        caps.contains('ai.required') ||
        caps.contains('ai.tools');
    final hasAuth = plugin['authId'] != null;

    return SubscriptionStyle(
      child: PopScope(
        canPop: !busy,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              widget.asSource
                  ? '配置内容源'
                  : widget.task == null
                  ? '新建任务'
                  : '编辑任务',
            ),
          ),
          body: Form(
            key: form,
            child: AbsorbPointer(
              absorbing: busy,
              child: ListView(
                key: const ValueKey('subscription-form-list'),
                padding: pageInsets(context),
                children: [
                  if (busy) const LinearProgressIndicator(),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InlineNotice(error!),
                    ),
                  // 顶部插件身份卡
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  plugin['name'] as String,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (widget.task == null && plugins.length > 1)
                                TextButton(
                                  onPressed: () async {
                                    final selectable = plugins
                                        .where(
                                          (entry) =>
                                              entry['legacy'] != true &&
                                              (!widget.asSource ||
                                                  entry['id'] !=
                                                      digestPluginId),
                                        )
                                        .toList();
                                    final next = await showChoiceSheet<String>(
                                      context: context,
                                      title: '切换插件',
                                      selected: pluginId,
                                      choices: [
                                        for (final entry in selectable)
                                          SheetChoice(
                                            value: entry['id'] as String,
                                            label: entry['name'] as String,
                                            description:
                                                entry['description'] as String?,
                                          ),
                                      ],
                                    );
                                    if (next != null &&
                                        next != pluginId &&
                                        mounted) {
                                      setState(() {
                                        pluginId = next;
                                        resetConfig({});
                                      });
                                    }
                                  },
                                  child: const Text('更换插件'),
                                ),
                            ],
                          ),
                          if ((plugin['description'] as String? ?? '')
                              .isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              plugin['description'] as String,
                              style: TextStyle(
                                fontSize: 13,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (hasAuth || supportsAI) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (hasAuth)
                                  SubscriptionStatus(
                                    '保存开启后需在「所需账号」完成 ${plugin['authName'] ?? plugin['authId']} 登录',
                                    color: colors.primary,
                                  ),
                                if (requiresAI)
                                  SubscriptionStatus(
                                    '需要 AI 配置',
                                    color: colors.tertiary,
                                  ),
                                if (supportsAI && !requiresAI)
                                  const SubscriptionStatus('可选 AI 增强'),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // 分组 1：基本设置（编辑页只管配置，新建默认启用，启停在外部列表控制）
                  _sectionCard(
                    context,
                    title: '基本设置',
                    children: [
                      TextFormField(
                        controller: name,
                        decoration: InputDecoration(
                          labelText: '任务名称',
                          hintText: '例如：${plugin['name']}',
                        ),
                        maxLength: 80,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? '请填写任务名称' : null,
                      ),
                    ],
                  ),

                  // 分组 2：插件自定义配置（完全由插件 Schema 驱动，含 aiProvider 字段）
                  if (pluginFields.isNotEmpty)
                    _sectionCard(
                      context,
                      title: '插件配置',
                      subtitle: '以下表单由「${plugin['name']}」插件声明',
                      children: [
                        for (final field in pluginFields) pluginField(field),
                      ],
                    ),

                  // 分组 3：调度与推送（宿主统一控制触发方式，去重由插件自行通过 state 管理）
                  _sectionCard(
                    context,
                    title: '调度设置',
                    children: [
                      if (widget.asSource)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 10),
                          child: Text('来源随统一推送执行，默认暂停独立运行。'),
                        ),
                      if (!widget.asSource)
                        choice('执行方式', scheduleType, [
                          {'id': 'manual', 'name': '仅手动'},
                          {'id': 'interval', 'name': '固定间隔'},
                          {'id': 'daily', 'name': '每天定点（北京时间）'},
                        ], (v) => scheduleType = v),
                      if (scheduleType == 'interval')
                        TextFormField(
                          controller: minutes,
                          decoration: const InputDecoration(
                            labelText: '间隔（分钟）',
                          ),
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            return n == null || n < 1 || n > 10080
                                ? '请输入 1–10080 分钟'
                                : null;
                          },
                        ),
                      if (scheduleType == 'daily')
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final time in times)
                              InputChip(
                                label: Text(time),
                                onDeleted: times.length <= 1
                                    ? null
                                    : () => setState(() => times.remove(time)),
                              ),
                            TextButton.icon(
                              onPressed: times.length >= 24 ? null : addTime,
                              icon: const Icon(Icons.add),
                              label: const Text('添加时间'),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(busy ? '正在保存…' : '保存任务'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
