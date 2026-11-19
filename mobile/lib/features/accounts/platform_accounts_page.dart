import '../../ui/theme.dart';
import '../../ui/selection_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/inbox_repository.dart';
import 'dart:convert';

class PlatformAccountsPage extends StatefulWidget {
  const PlatformAccountsPage({
    super.key,
    this.embedded = false,
    this.requiredAccounts = const [],
    this.serverError,
    this.onChanged,
    this.onAddTask,
  });
  final bool embedded;
  final List<Map<String, dynamic>> requiredAccounts;
  final String? serverError;
  final Future<void> Function()? onChanged;
  final VoidCallback? onAddTask;
  @override
  State<PlatformAccountsPage> createState() => _PlatformAccountsPageState();
}

class _PlatformAccountsPageState extends State<PlatformAccountsPage> {
  bool busy = false;
  String? error;
  String? notice;

  Future<void> act(String action, String platform) async {
    if (busy) return;
    if (action == 'logout') {
      final confirmed = await showAppSheet<bool>(
        context: context,
        builder: (context) => SheetDialog(
          title: const Text('退出服务器账号？'),
          content: const Text('依赖此账号的任务将等待重新登录，已创建的任务会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('退出账号'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      if (action == 'login') {
        final message = await InboxRepository.channel.invokeMethod<String>(
          'platformLogin',
          {'platform': platform},
        );
        if (mounted) setState(() => notice = message ?? '已返回，尚未完成授权');
      } else {
        await InboxRepository.channel.invokeMethod<String>('platformAccounts', {
          'action': action,
          'platform': platform,
        });
        if (mounted) {
          setState(
            () => notice = action == 'logout'
                ? '已退出账号，相关任务等待登录'
                : '账号可用，相关任务可以执行',
          );
        }
      }
      await widget.onChanged?.call();
    } on PlatformException catch (failure) {
      if (mounted) setState(() => error = failure.message ?? '账号操作未完成，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('所需账号')),
      body: RefreshIndicator(
        onRefresh: () async {
          await widget.onChanged?.call();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: pageInsets(context),
          children: [
            if (busy) const LinearProgressIndicator(),
            if (widget.serverError != null)
              Text(widget.serverError!, style: TextStyle(color: colors.error)),
            if (widget.requiredAccounts.isEmpty && widget.serverError == null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        Icons.checklist_rounded,
                        size: 40,
                        color: colors.outline,
                      ),
                      const SizedBox(height: 16),
                      const Text('当前没有需要登录的任务'),
                      const SizedBox(height: 8),
                      Text(
                        '开启订阅后，需要授权的账号会出现在这里。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          height: 1.6,
                        ),
                      ),
                      if (widget.onAddTask != null) ...[
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: widget.onAddTask,
                          child: const Text('去添加订阅'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            for (final entry in widget.requiredAccounts) accountCard(entry),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(error!, style: TextStyle(color: colors.error)),
              ),
            if (notice != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(notice!),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> accountActions(Map<String, dynamic> entry) async {
    final ready = entry['state'] == 'ready';
    final action = await showChoiceSheet<String>(
      context: context,
      title: entry['name'] as String,
      choices: [
        SheetChoice(
          value: 'login',
          label: ready ? '重新登录' : '登录并启用任务',
          description: ready ? null : '授权后，已开启的任务会继续执行',
          icon: Icons.login,
        ),
        if (ready)
          const SheetChoice(
            value: 'verify',
            label: '检查账号',
            icon: Icons.refresh,
          ),
        if (ready)
          const SheetChoice(value: 'logout', label: '退出账号', icon: Icons.logout),
        if (tasksFor(entry).isNotEmpty)
          SheetChoice(
            value: 'tasks',
            label: '关联任务',
            description: '查看全部 ${tasksFor(entry).length} 个任务',
            icon: Icons.checklist_rounded,
          ),
      ],
    );
    if (action == 'tasks' && mounted) {
      await showAppSheet<void>(
        context: context,
        builder: (_) => SheetDialog(
          title: Text('${entry['name']} · 关联任务'),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final name in tasksFor(entry))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(name),
                ),
            ],
          ),
        ),
      );
    } else if (action != null && mounted) {
      await act(action, entry['id'] as String);
    }
  }

  List<String> tasksFor(Map<String, dynamic> entry) =>
      (entry['tasks'] as List? ?? [])
          .cast<Map>()
          .map((task) => task['name'] as String)
          .toList();

  Widget accountCard(Map<String, dynamic> entry) {
    final colors = Theme.of(context).colorScheme;
    final ready = entry['state'] == 'ready';
    final tasks = (entry['tasks'] as List? ?? []).cast<Map>();
    final supported = ['bilibili', 'x', 'xiaohongshu'].contains(entry['id']);
    final account = entry['account'] as Map?;
    final name = account?['name'] as String?;
    final avatar = account?['avatar'] as String?;
    ImageProvider? photo;
    if (avatar != null &&
        RegExp(r'^data:image/(png|jpeg|webp|gif);base64,').hasMatch(avatar)) {
      try {
        photo = MemoryImage(base64Decode(avatar.split(',').last));
      } catch (_) {
        photo = null;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          onTap: busy || widget.serverError != null || !supported
              ? null
              : () => accountActions(entry),
          leading: CircleAvatar(
            radius: 19,
            backgroundColor: colors.surfaceContainerHighest,
            foregroundImage: photo,
            onForegroundImageError: photo == null ? null : (_, _) {},
            child: Text(
              (entry['name'] as String).characters.firstOrNull ?? '？',
              style: TextStyle(fontSize: 14, color: colors.onSurfaceVariant),
            ),
          ),
          title: Text(
            ready && name != null && name.trim().isNotEmpty
                ? name
                : entry['name'] as String,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  if (ready) entry['name'],
                  ready ? '已登录' : '等待登录',
                  if (tasks.length > 1) '${tasks.length} 个任务',
                ].join(' · '),
              ),
              if (tasks.length == 1)
                Text(
                  tasks.single['name'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (!ready && entry['message'] != null)
                Text(
                  entry['message'] as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          trailing: supported
              ? const Icon(Icons.chevron_right, size: 18)
              : null,
        ),
      ),
    );
  }
}
