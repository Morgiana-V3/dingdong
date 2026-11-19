import '../../ui/theme.dart';
import '../../ui/selection_sheet.dart';
import 'package:flutter/material.dart';
import 'studio_page.dart';
import 'bilibili_followings.dart';
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
        case 'forums':
          config[key] = studioItems(
            initial ??
                [
                  {'name': '', 'filter': ''},
                ],
          );
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
    if (field['type'] == 'forums') {
      final forums = config[key] as List<Map<String, dynamic>>;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          for (final forum in forums)
            Card(
              key: ObjectKey(forum),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextFormField(
                      initialValue: forum['name'] as String? ?? '',
                      decoration: const InputDecoration(labelText: '吧名'),
                      maxLength: 60,
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? '请填写吧名' : null,
                      onChanged: (v) => forum['name'] = v,
                    ),
                    TextFormField(
                      initialValue: forum['filter'] as String? ?? '',
                      decoration: const InputDecoration(
                        labelText: '本吧过滤说明（可选）',
                      ),
                      minLines: 2,
                      maxLines: 5,
                      maxLength: 3000,
                      onChanged: (v) => forum['filter'] = v,
                    ),
                    TextButton(
                      onPressed: forums.length <= 1
                          ? null
                          : () => setState(() => forums.remove(forum)),
                      child: const Text('移除此吧'),
                    ),
                  ],
                ),
              ),
            ),
          TextButton.icon(
            onPressed: forums.length >= 5
                ? null
                : () => setState(() => forums.add({'name': '', 'filter': ''})),
            icon: const Icon(Icons.add),
            label: const Text('添加贴吧'),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        key: ValueKey('$pluginId/$key'),
        controller: fields[key],
        decoration: InputDecoration(
          labelText: label,
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
        minLines: field['type'] == 'textarea' ? 3 : 1,
        maxLines: field['type'] == 'textarea' ? 6 : 1,
        keyboardType: field['type'] == 'number'
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : TextInputType.multiline,
        validator: (value) {
          if (field['required'] == true &&
              (value == null || value.trim().isEmpty)) {
            return '请填写$label';
          }
          if (field['type'] == 'number' && num.tryParse(value ?? '') == null) {
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

  @override
  Widget build(BuildContext context) => SubscriptionStyle(
    child: PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.asSource
                ? '配置内容源'
                : widget.task == null
                ? '添加任务'
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
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '任务名称'),
                  maxLength: 80,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请填写任务名称' : null,
                ),
                const SizedBox(height: 10),
                choice(
                  '订阅插件',
                  pluginId,
                  plugins
                      .where(
                        (entry) =>
                            (widget.task != null || entry['legacy'] != true) &&
                            (!widget.asSource || entry['id'] != digestPluginId),
                      )
                      .toList(),
                  (v) {
                    pluginId = v;
                    resetConfig({});
                  },
                  locked: widget.task != null,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => showAppSheet<void>(
                      context: context,
                      builder: (context) => SheetDialog(
                        title: Text(plugin['name'] as String),
                        content: Text(plugin['description'] as String? ?? ''),
                      ),
                    ),
                    icon: const Icon(Icons.info_outline, size: 16),
                    label: const Text('插件说明'),
                  ),
                ),
                const SizedBox(height: 12),
                Text('订阅内容', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                for (final field in studioItems(plugin['fields'])) ...[
                  pluginField(field),
                  if (pluginId == 'bilibili-videos' && field['key'] == 'upIds')
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.people_outline),
                        label: const Text('从关注列表选择 UP 主'),
                        onPressed: () async {
                          final result = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BilibiliFollowings(
                                selected: fields['upIds']!.text,
                              ),
                            ),
                          );
                          if (result != null && mounted) {
                            setState(() => fields['upIds']!.text = result);
                          }
                        },
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '执行与推送',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                choice(
                  'AI 配置',
                  providerId,
                  studioItems(snapshotData['providers']),
                  (v) => providerId = v,
                  optional: true,
                ),
                if ((plugin['capabilities'] as List? ?? []).contains(
                      'ai.tools',
                    ) &&
                    studioItems(snapshotData['providers']).isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text('此插件需要 AI，可在服务器配置中添加服务。'),
                  ),
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
                    decoration: const InputDecoration(labelText: '间隔（分钟）'),
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
                if (!widget.asSource)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用订阅'),
                    value: enabled,
                    onChanged: (v) => setState(() => enabled = v),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('仅内容变化时推送'),
                  value: onlyChanged,
                  onChanged: (v) => setState(() => onlyChanged = v),
                ),
                const SizedBox(height: 20),
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
