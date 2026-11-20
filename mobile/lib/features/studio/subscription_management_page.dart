import '../../ui/selection_sheet.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/inbox_repository.dart';
import '../accounts/platform_accounts_page.dart';
import 'subscription_editor.dart';
import 'subscription_providers.dart';
import 'subscription_style.dart';
import '../settings/settings_page.dart';
import '../../ui/connection_badge.dart';
import '../../ui/theme.dart';

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

  Future<void> pickPluginAndCreate(List<Map<String, dynamic>> plugins) async {
    final available = plugins.where((p) => p['legacy'] != true).toList()
      ..sort((a, b) {
        final aDigest = a['id'] == digestPluginId ? 1 : 0;
        final bDigest = b['id'] == digestPluginId ? 1 : 0;
        return aDigest.compareTo(bDigest);
      });
    if (available.isEmpty) return;
    if (available.length == 1) {
      await edit(available.first);
      return;
    }
    final selected = await showAppSheet<Map<String, dynamic>>(
      context: context,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return SheetDialog(
          title: const Text('选择插件'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '以下为当前服务器已加载的插件，选择后按插件配置创建任务。',
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              for (final plugin in available)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(sheetContext, plugin),
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
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 20,
                                  color: colors.onSurfaceVariant,
                                ),
                              ],
                            ),
                            if ((plugin['description'] as String? ?? '')
                                .isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                plugin['description'] as String,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.4,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (plugin['authId'] != null)
                                  SubscriptionStatus(
                                    '需 ${plugin['authName'] ?? plugin['authId']} 登录',
                                    color: colors.primary,
                                  ),
                                if (studioItems(plugin['fields']).any(
                                  (f) =>
                                      f['type'] == 'aiProvider' &&
                                      f['required'] == true,
                                ))
                                  SubscriptionStatus(
                                    '需要 AI',
                                    color: colors.tertiary,
                                  ),
                                if (studioItems(plugin['fields']).any(
                                  (f) =>
                                      f['type'] == 'aiProvider' &&
                                      f['required'] != true,
                                ))
                                  const SubscriptionStatus('可选 AI'),
                                if (plugin['id'] == digestPluginId)
                                  const SubscriptionStatus('多源汇总'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (selected != null && mounted) {
      await edit(selected);
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
        builder: (_) => ServerConnectionPage(
          repository: widget.repository,
          settings: connection,
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
          revealKey: (id) async {
            final result = await widget.repository.subscriptions({
              'action': 'revealProviderKey',
              'revision': snapshot!['revision'],
              'id': id,
            });
            return result['key'] as String;
          },
          testConnection: (provider) async {
            return await widget.repository.subscriptions({
              'action': 'testProvider',
              'revision': snapshot!['revision'],
              'provider': provider,
            });
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
        onPressed: !busy && error == null ? () => tabs.animateTo(1) : null,
        child: const Text('去登录'),
      );
    } else if (state == 'needs_config') {
      action = TextButton(
        onPressed: available ? () => edit(plugin, task) : null,
        child: const Text('选择 UP 主'),
      );
    } else if (state == 'running') {
      action = TextButton(
        onPressed: !busy && error == null
            ? () => perform({'action': 'cancel', 'id': task['id']})
            : null,
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
                  Semantics(
                    label: '${task['name']} · 启用订阅',
                    child: Switch(
                      value: task['enabled'] == true,
                      onChanged: !busy && error == null
                          ? (value) => perform({
                              'action': 'toggle',
                              'id': task['id'],
                              'enabled': value,
                            })
                          : null,
                    ),
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
                              ? Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF8CD7AE)
                                    : const Color(0xFF32815B)
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
                        enabled: !busy && error == null,
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
      compact: true,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('订阅管理'),
          actions: [
            IconButton(
              tooltip: '服务器配置',
              onPressed: busy || snapshot == null ? null : configureServer,
              icon: const Icon(Icons.tune_rounded),
            ),
            IconButton(
              tooltip: '刷新订阅',
              onPressed: busy ? null : refresh,
              icon: const Icon(Icons.refresh),
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
                padding: pageInsets(context, top: 4),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (busy) const LinearProgressIndicator(),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const Icon(Icons.dns_outlined, size: 20),
                    minLeadingWidth: 20,
                    horizontalTitleGap: 8,
                    title: Text(
                      host.isEmpty ? '配置服务器连接' : host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: ConnectionBadge(
                      status: connection['status'] as String? ?? '未连接',
                    ),
                    onTap: configureConnection,
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  if (error != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InlineNotice(error!),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: busy ? null : refresh,
                            icon: const Icon(Icons.refresh),
                            label: const Text('重试'),
                          ),
                        ),
                      ],
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
                            : () => pickPluginAndCreate(plugins),
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
                          const Text('还没有订阅任务'),
                          const SizedBox(height: 8),
                          Text(
                            '添加任务，选择你想接收的内容。',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: colors.onSurfaceVariant),
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
