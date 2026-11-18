import '../../ui/selection_sheet.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/inbox_repository.dart';
import '../accounts/platform_accounts_page.dart';
import 'studio_page.dart';
import 'subscription_editor.dart';
import 'subscription_providers.dart';
import 'subscription_style.dart';
import '../settings/settings_page.dart';
import '../../ui/connection_badge.dart';

class SubscriptionManagementPage extends StatefulWidget {
  const SubscriptionManagementPage({super.key, required this.repository});
  final InboxRepository repository;
  @override
  State<SubscriptionManagementPage> createState() =>
      _SubscriptionManagementPageState();
}

class _SubscriptionManagementPageState extends State<SubscriptionManagementPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final tabs = TabController(length: 2, vsync: this);
  Map<String, dynamic>? snapshot;
  Map<String, dynamic> connection = {};
  String? error;
  bool busy = false;
  bool polling = false;
  bool active = true;
  int generation = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (active && !busy) refresh(quiet: true);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    tabs.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) refresh(quiet: true);
  }

  String failure(Object value) =>
      value is PlatformException ? value.message ?? '无法连接订阅服务' : '操作未完成，请刷新后重试';
  Future<void> refresh({bool quiet = false}) async {
    if (polling || busy) return;
    polling = true;
    final started = generation;
    if (!quiet) setState(() => busy = true);
    try {
      try {
        final saved = await widget.repository.settings();
        if (mounted && started == generation) {
          setState(() => connection = saved);
        }
      } catch (_) {
        if (mounted && started == generation) {
          setState(() => connection = {...connection, 'status': '无法读取连接状态'});
        }
      }
      final data = await widget.repository.subscriptions();
      if (mounted && started == generation) {
        setState(() {
          snapshot = data;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && started == generation) setState(() => error = failure(e));
    } finally {
      polling = false;
      if (mounted && !quiet) setState(() => busy = false);
    }
  }

  Future<void> command(Map<String, dynamic> data) async {
    if (busy || snapshot == null) {
      throw PlatformException(code: 'busy', message: '请等待当前操作完成');
    }
    setState(() => busy = true);
    generation++;
    try {
      final result = await widget.repository.subscriptions({
        'revision': snapshot!['revision'],
        ...data,
      });
      if (mounted) {
        setState(() {
          snapshot = result;
          error = null;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> perform(Map<String, dynamic> data) async {
    try {
      await command(data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure(e))));
      }
    }
  }

  Future<void> edit(
    Map<String, dynamic> plugin, [
    Map<String, dynamic>? task,
  ]) async {
    active = false;
    final revision = snapshot!['revision'];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SubscriptionEditor(
          snapshot: snapshot!,
          saveSource: (values) async {
            await command({'action': 'save', ...values});
            return snapshot!;
          },
          initialPluginId: plugin['id'] as String,
          task: task,
          save: (values) =>
              command({'action': 'save', 'revision': revision, ...values}),
        ),
      ),
    );
    active = true;
    if (mounted) await refresh();
  }

  Future<void> configureConnection() async {
    active = false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StatefulBuilder(
          builder: (context, update) => SubscriptionStyle(
            child: Scaffold(
              appBar: AppBar(title: const Text('服务器连接')),
              body: SettingsPage(
                repository: widget.repository,
                settings: connection,
                connectionOnly: true,
                onChanged: () async {
                  await refresh();
                  if (context.mounted) update(() {});
                },
              ),
            ),
          ),
        ),
      ),
    );
    active = true;
    if (mounted) await refresh();
  }

  Future<void> configureServer() async {
    active = false;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ServerConfigurationPage(
          load: () => snapshot!,
          save: command,
          models: (provider) async {
            final result = await widget.repository.subscriptions({
              'action': 'models',
              'revision': snapshot!['revision'],
              'provider': provider,
            });
            return (result['models'] as List).cast<String>();
          },
        ),
      ),
    );
    active = true;
    if (mounted) await refresh();
  }

  Future<void> remove(Map<String, dynamic> task) async {
    final confirmed = await showAppSheet<bool>(
      context: context,
      builder: (context) => SheetDialog(
        title: const Text('删除订阅任务？'),
        content: Text('「${task['name']}」将停止运行，已有消息和平台账号会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除任务'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await perform({'action': 'delete', 'id': task['id']});
    }
  }

  String scheduleLabel(Map<String, dynamic> task) {
    final schedule = task['schedule'] as Map?;
    if (schedule?['type'] == 'manual') return '仅手动';
    if (schedule?['type'] == 'daily') {
      return '每天 ${(schedule?['times'] as List? ?? []).join('、')}';
    }
    return '每 ${schedule?['minutes'] ?? task['minutes']} 分钟';
  }

  String stateLabel(String? state) =>
      const {
        'paused': '已暂停',
        'needs_login': '等待登录',
        'running': '正在检查',
        'error': '执行失败',
        'unavailable': '插件未安装',
        'active': '已开启',
        'needs_ai': '等待 AI 配置',
        'needs_config': '请选择 UP 主',
        'grouped': '由统一推送执行',
      }[state] ??
      '准备中';

  Future<void> taskDetails(Map<String, dynamic> task) => showAppSheet<void>(
    context: context,
    builder: (context) => SheetDialog(
      title: Text(task['name'] as String),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('状态 · ${stateLabel(task['state'] as String?)}'),
          if (task['lastRunAt'] != null)
            Text('上次新增 ${task['lastCount'] ?? 0} 条'),
          if (task['lastError'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(task['lastError'] as String),
            ),
          if (task['lastDetail'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(task['lastDetail'] as String),
            ),
          for (final entry in studioItems(task['trace']))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(entry['detail'] as String),
              subtitle: Text(entry['tool'] as String),
            ),
          if (task['lastRunAt'] == null) const Text('还没有执行记录'),
        ],
      ),
    ),
  );

  Widget taskCard(
    Map<String, dynamic> task,
    List<Map<String, dynamic>> plugins,
  ) {
    final colors = Theme.of(context).colorScheme;
    final plugin = plugins
        .where((p) => p['id'] == task['pluginId'])
        .firstOrNull;
    final state = task['state'] as String?;
    final available = !busy && error == null && plugin != null;
    final blocked = [
      'needs_login',
      'needs_ai',
      'needs_config',
      'error',
      'unavailable',
    ].contains(state);
    Widget action;
    if (state == 'needs_ai') {
      action = TextButton(
        onPressed: available ? configureServer : null,
        child: const Text('去配置 AI'),
      );
    } else if (state == 'needs_login') {
      action = TextButton(
        onPressed: () => tabs.animateTo(1),
        child: const Text('去登录'),
      );
    } else if (state == 'needs_config') {
      action = TextButton(
        onPressed: available ? () => edit(plugin, task) : null,
        child: const Text('选择 UP 主'),
      );
    } else if (state == 'running') {
      action = TextButton(
        onPressed: () => perform({'action': 'cancel', 'id': task['id']}),
        child: const Text('停止执行'),
      );
    } else if (state == 'grouped') {
      action = TextButton(
        onPressed: available ? () => edit(plugin, task) : null,
        child: const Text('编辑来源'),
      );
    } else {
      action = TextButton(
        onPressed: available
            ? () => perform({'action': 'run', 'id': task['id']})
            : null,
        child: const Text('立即运行'),
      );
    }
    return Padding(
      key: ValueKey('task-card/${task['id']}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task['name'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${plugin?['name'] ?? '未安装的插件'} · ${scheduleLabel(task)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: task['enabled'] == true,
                    onChanged: available
                        ? (value) => perform({
                            'action': 'toggle',
                            'id': task['id'],
                            'enabled': value,
                          })
                        : null,
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SubscriptionStatus(
                          stateLabel(state),
                          color: blocked
                              ? colors.error
                              : state == 'active'
                              ? const Color(0xFF32815B)
                              : null,
                        ),
                        if (task['lastRunAt'] != null)
                          Text(
                            '+${task['lastCount'] ?? 0} 条',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  action,
                  SheetMenuButton<String>(
                    tooltip: '任务操作 · ${task['name']}',
                    choices: [
                      SheetChoice(
                        value: 'edit',
                        label: '编辑',
                        icon: Icons.edit_outlined,
                        enabled: available,
                      ),
                      const SheetChoice(
                        value: 'details',
                        label: '执行记录',
                        icon: Icons.history,
                      ),
                      SheetChoice(
                        value: 'delete',
                        label: '删除',
                        icon: Icons.delete_outline,
                        enabled: !busy,
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'edit') edit(plugin!, task);
                      if (value == 'details') taskDetails(task);
                      if (value == 'delete') remove(task);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plugins = studioItems(snapshot?['plugins']);
    final tasks = studioItems(snapshot?['tasks']);
    final accounts = studioItems(snapshot?['accounts']);
    final host =
        Uri.tryParse(connection['endpoint'] as String? ?? '')?.host ?? '';
    final colors = Theme.of(context).colorScheme;
    return SubscriptionStyle(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('订阅管理'),
          actions: [
            IconButton(
              tooltip: '刷新订阅',
              onPressed: busy ? null : refresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: '服务器配置',
              onPressed: busy || snapshot == null ? null : configureServer,
              icon: const Icon(Icons.tune_rounded),
            ),
            SheetMenuButton<String>(
              tooltip: '更多',
              onSelected: (value) async {
                if (value == 'server') {
                  await configureServer();
                  return;
                }
                active = false;
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StudioPage(repository: widget.repository),
                  ),
                );
                active = true;
                if (mounted) await refresh();
              },
              choices: [
                if (snapshot != null)
                  const SheetChoice(
                    value: 'server',
                    label: '服务器配置',
                    description: 'AI 服务、任务配置与可用插件',
                    icon: Icons.dns_outlined,
                  ),
                const SheetChoice(
                  value: 'studio',
                  label: '电脑 Studio 管理',
                  icon: Icons.computer_outlined,
                ),
              ],
            ),
          ],
          bottom: TabBar(
            controller: tabs,
            tabs: [
              const Tab(text: '订阅任务'),
              Tab(
                text: accounts.isEmpty ? '所需账号' : '所需账号 · ${accounts.length}',
              ),
            ],
          ),
        ),
        body: TabBarView(
          controller: tabs,
          children: [
            RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                key: const ValueKey('subscription-task-list'),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (busy) const LinearProgressIndicator(),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: configureConnection,
                          icon: const Icon(Icons.dns_outlined, size: 16),
                          label: Text(
                            host.isEmpty ? '配置服务器连接' : host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      ConnectionBadge(
                        status: connection['status'] as String? ?? '未连接',
                      ),
                    ],
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '我的任务',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed:
                            busy ||
                                error != null ||
                                plugins
                                    .where((p) => p['legacy'] != true)
                                    .isEmpty
                            ? null
                            : () => edit(
                                plugins.firstWhere((p) => p['legacy'] != true),
                              ),
                        icon: const Icon(Icons.add),
                        label: const Text('添加任务'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (tasks.isEmpty && snapshot != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Column(
                        children: [
                          Icon(
                            Icons.subscriptions_outlined,
                            size: 36,
                            color: colors.outline,
                          ),
                          const SizedBox(height: 12),
                          const Text('点击「添加任务」，选择插件并配置订阅内容。'),
                          const SizedBox(height: 6),
                          Text(
                            '任务需要登录时，会在右侧「所需账号」提醒。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final task in tasks) taskCard(task, plugins),
                ],
              ),
            ),
            PlatformAccountsPage(
              embedded: true,
              requiredAccounts: accounts,
              serverError: error,
              onChanged: () => refresh(quiet: true),
              onAddTask: () => tabs.animateTo(0),
            ),
          ],
        ),
      ),
    );
  }
}
