import '../../ui/theme.dart';
import '../../ui/selection_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/inbox_repository.dart';

const digestPluginId = 'minipush-digest';

List<Map<String, dynamic>> studioItems(dynamic value) => (value as List? ?? [])
    .map((item) => Map<String, dynamic>.from(item as Map))
    .toList();

String studioError(Object error) => error is PlatformException
    ? error.message ?? '无法连接 Studio'
    : error is StudioFailure
    ? error.message
    : '操作未完成，请刷新后重试';

class StudioFailure implements Exception {
  StudioFailure(this.message);
  final String message;
}

class StudioPage extends StatefulWidget {
  const StudioPage({
    super.key,
    required this.repository,
    this.embedded = false,
  });
  final InboxRepository repository;
  final bool embedded;
  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  Map<String, dynamic>? snapshot;
  String session = '';
  String? error;
  bool busy = false;
  bool online = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.repository.studio();
      if (!mounted) return;
      setState(() {
        online = result['online'] == true;
        session = result['session'] as String? ?? '';
        snapshot = result['snapshot'] as Map<String, dynamic>?;
      });
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = studioError(failure);
          online = false;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> command(String action, Map<String, dynamic> payload) async {
    if (busy || !online || snapshot == null) {
      throw StudioFailure('请先刷新并连接 Studio');
    }
    setState(() => busy = true);
    try {
      final result = await widget.repository.studio({
        'session': session,
        'revision': snapshot!['revision'],
        'action': action,
        'payload': payload,
      });
      if (!mounted) return;
      // A rejected edit must keep its original revision until the user refreshes.
      if (result['ok'] != true) {
        throw StudioFailure(result['error'] as String? ?? 'Studio 未能保存设置');
      }
      setState(() {
        snapshot = result['snapshot'] as Map<String, dynamic>;
        session = result['session'] as String;
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> perform(String action, Map<String, dynamic> payload) async {
    try {
      await command(action, payload);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Studio 已保存设置')));
      }
    } catch (failure) {
      if (mounted) setState(() => error = studioError(failure));
    }
  }

  Future<void> edit([Map<String, dynamic>? task]) async {
    final data = snapshot!;
    if (task != null &&
        !studioItems(
          data['plugins'],
        ).any((plugin) => plugin['id'] == task['pluginId'])) {
      setState(() => error = '此订阅插件尚未安装，请先在电脑端安装后刷新');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StudioTaskEditor(
          snapshot: data,
          task: task,
          save: (input) => command('saveTask', input),
        ),
      ),
    );
    if (mounted) await refresh();
  }

  Future<void> remove(Map<String, dynamic> task) async {
    final confirmed = await showAppSheet<bool>(
      context: context,
      builder: (context) => SheetDialog(
        title: const Text('删除订阅？'),
        content: Text('将从 Studio 删除「${task['name']}」，无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await perform('deleteTask', {'id': task['id']});
    }
  }

  String scheduleLabel(Map<String, dynamic> task) {
    final schedule = task['schedule'] as Map;
    if (schedule['type'] == 'interval') return '每 ${schedule['minutes']} 分钟';
    if (schedule['type'] == 'daily') {
      return '每天 ${(schedule['times'] as List? ?? [schedule['time']]).join('、')}（北京时间）';
    }
    return '仅手动执行';
  }

  @override
  Widget build(BuildContext context) {
    final tasks = studioItems(snapshot?['tasks']);
    final plugins = studioItems(snapshot?['plugins']);
    final running = snapshot?['running'] as List? ?? [];
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Studio 订阅'),
              actions: [
                IconButton(
                  tooltip: '刷新订阅',
                  onPressed: busy ? null : refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      floatingActionButton: online && snapshot != null && plugins.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: busy ? null : () => edit(),
              icon: const Icon(Icons.add),
              label: const Text('新增订阅'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: pageInsets(context, bottom: 100),
          children: [
            if (busy) const LinearProgressIndicator(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              trailing: widget.embedded
                  ? IconButton(
                      tooltip: '刷新订阅',
                      onPressed: busy ? null : refresh,
                      icon: const Icon(Icons.refresh),
                    )
                  : null,
              leading: Icon(
                online ? Icons.computer : Icons.desktop_access_disabled,
              ),
              title: Text(online ? 'Studio 已连接' : 'Studio 未连接'),
              subtitle: Text(
                online
                    ? '修改经电脑确认后生效。执行时间均为北京时间。'
                    : '请在电脑 Studio 的应用设置中开启手机管理，选择与手机相同的叮咚服务器，并保持 Studio 运行。',
              ),
            ),
            if (error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(error!),
                ),
              ),
            if (online && tasks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂无订阅。可在手机新增；平台登录和插件安装请先在电脑端完成。'),
              ),
            if (online)
              for (final task in tasks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      title: Text(
                        task['name'] as String,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${plugins.where((p) => p['id'] == task['pluginId']).map((p) => p['name']).firstOrNull ?? '订阅'} · ${scheduleLabel(task)}${running.contains(task['id']) ? '\n正在执行' : ''}',
                      ),
                      onTap: busy || running.contains(task['id'])
                          ? null
                          : () => edit(task),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: task['enabled'] == true,
                            onChanged: busy || running.contains(task['id'])
                                ? null
                                : (value) => perform('setEnabled', {
                                    'id': task['id'],
                                    'enabled': value,
                                  }),
                          ),
                          SheetMenuButton<String>(
                            tooltip: '订阅操作 · ${task['name']}',
                            choices: [
                              SheetChoice(
                                value: 'edit',
                                label: '编辑',
                                enabled: !busy && !running.contains(task['id']),
                              ),
                              SheetChoice(
                                value: 'delete',
                                label: '删除',
                                enabled: !busy && !running.contains(task['id']),
                              ),
                            ],
                            onSelected: (action) {
                              if (action == 'edit') edit(task);
                              if (action == 'delete') remove(task);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class StudioTaskEditor extends StatefulWidget {
  const StudioTaskEditor({
    super.key,
    required this.snapshot,
    this.task,
    required this.save,
  });
  final Map<String, dynamic> snapshot;
  final Map<String, dynamic>? task;
  final Future<void> Function(Map<String, dynamic>) save;
  @override
  State<StudioTaskEditor> createState() => _StudioTaskEditorState();
}

class _StudioTaskEditorState extends State<StudioTaskEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.task?['name'] as String? ?? '',
  );
  late final minutes = TextEditingController(
    text: '${(widget.task?['schedule'] as Map?)?['minutes'] ?? 60}',
  );
  late String pluginId =
      widget.task?['pluginId'] as String? ?? plugins.first['id'] as String;
  late String channelId =
      widget.task?['channelId'] as String? ??
      (studioItems(widget.snapshot['channels']).firstOrNull?['id'] as String? ??
          '');
  late String providerId = widget.task?['providerId'] as String? ?? '';
  late String scheduleType =
      (widget.task?['schedule'] as Map?)?['type'] as String? ?? 'manual';
  late bool enabled = widget.task?['enabled'] == true;
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
      studioItems(widget.snapshot['plugins']);
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
          values[key] = fields[key]!.text;
        }
      }
      await widget.save({
        if (widget.task != null) 'id': widget.task!['id'],
        'name': name.text.trim(),
        'pluginId': pluginId,
        'channelId': channelId,
        'providerId': pluginId == digestPluginId ? '' : providerId,
        'enabled': enabled,
        'onlyChanged': onlyChanged,
        'config': values,
        'schedule': {
          'type': scheduleType,
          if (scheduleType == 'interval') 'minutes': minutes.text,
          if (scheduleType == 'daily') 'times': times,
        },
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Studio 已保存设置')));
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
      padding: const EdgeInsets.only(bottom: 16),
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
      final sources = studioItems(
        widget.snapshot['tasks'],
      ).where((task) => task['pluginId'] != digestPluginId).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const Text('选择 1–8 个内容源。启用汇总后，所选来源停止独立定时，由汇总统一发送。'),
          if (sources.isEmpty) const Text('请先创建来源订阅，再配置汇总。'),
          for (final task in sources)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(task['name'] as String),
              value: selected.contains(task['id']),
              onChanged: (v) => setState(() {
                if (v == true) {
                  selected.add(task['id'] as String);
                } else {
                  selected.remove(task['id']);
                }
              }),
            ),
        ],
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
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        key: ValueKey('$pluginId/$key'),
        controller: fields[key],
        decoration: InputDecoration(labelText: label),
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
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.task == null ? '新增订阅' : '编辑订阅')),
      body: Form(
        key: form,
        child: AbsorbPointer(
          absorbing: busy,
          child: ListView(
            padding: pageInsets(context),
            children: [
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: '订阅名称'),
                maxLength: 200,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请填写订阅名称' : null,
              ),
              const SizedBox(height: 16),
              choice('订阅类型', pluginId, plugins, (v) {
                pluginId = v;
                resetConfig({});
              }, locked: widget.task != null),
              choice(
                '推送渠道',
                channelId,
                studioItems(widget.snapshot['channels']),
                (v) => channelId = v,
              ),
              if (pluginId != digestPluginId)
                choice(
                  'AI 配置',
                  providerId,
                  studioItems(widget.snapshot['providers']),
                  (v) => providerId = v,
                  optional: true,
                ),
              choice('执行方式', scheduleType, [
                {'id': 'manual', 'name': '仅手动'},
                {'id': 'interval', 'name': '固定间隔'},
                {'id': 'daily', 'name': '每天定点（北京时间）'},
              ], (v) => scheduleType = v),
              if (scheduleType == 'manual')
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('仅手动任务需在电脑端执行，也可以作为订阅汇总的内容源。'),
                ),
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
              const Divider(),
              const SizedBox(height: 16),
              for (final field in studioItems(plugin['fields']))
                pluginField(field),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : submit,
                child: Text(busy ? '等待 Studio 确认…' : '保存到 Studio'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
