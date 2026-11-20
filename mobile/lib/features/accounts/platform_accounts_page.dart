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
  String? busyAuthId;
  final Map<String, String> cardErrors = {};
  final Map<String, String> cardNotices = {};

  bool get busy => busyAuthId != null;

  Future<void> act(String action, Map<String, dynamic> entry) async {
    final authId = entry['id'] as String;
    final authType = entry['type'] as String? ?? 'web-cookie';
    final ready = entry['state'] == 'ready';
    if (busy) return;
    if (action == 'logout') {
      final confirmed = await showAppSheet<bool>(
        context: context,
        builder: (context) => SheetDialog(
          title: const Text('清除服务器凭据？'),
          content: const Text('依赖此凭据的任务将等待重新授权，已创建的任务会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清除凭据'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    String? tokenInput;
    if (action == 'login' && authType == 'token') {
      final controller = TextEditingController();
      tokenInput = await showAppSheet<String>(
        context: context,
        builder: (context) => SheetDialog(
          title: Text('配置 ${entry['name']} 凭据'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((entry['help'] as String? ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(entry['help'] as String),
                ),
              TextField(
                controller: controller,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Token / 密钥',
                  hintText: entry['placeholder'] as String?,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('保存并验证'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (tokenInput == null || tokenInput.isEmpty || !mounted) return;
    }
    setState(() {
      busyAuthId = authId;
      cardErrors.remove(authId);
      cardNotices.remove(authId);
    });
    try {
      if (action == 'login' && authType == 'token') {
        await InboxRepository.channel.invokeMethod<String>('platformAccounts', {
          'action': 'import',
          'authId': authId,
          'command': jsonEncode({'token': tokenInput}),
        });
        if (mounted) setState(() => cardNotices[authId] = '凭据已验证并加密保存');
      } else if (action == 'login') {
        final message = await InboxRepository.channel
            .invokeMethod<String>('platformLogin', {
              'authId': authId,
              'authName': entry['name'] as String? ?? authId,
              'loginUrl': entry['loginUrl'] as String? ?? '',
              'cookieDomains': (entry['cookieDomains'] as List? ?? [])
                  .map((e) => '$e')
                  .toList(),
              'requiredCookies': (entry['requiredCookies'] as List? ?? [])
                  .map((e) => '$e')
                  .toList(),
              'clearExisting': ready,
            });
        if (mounted) {
          setState(() => cardNotices[authId] = message ?? '已返回，尚未完成授权');
        }
      } else {
        await InboxRepository.channel.invokeMethod<String>('platformAccounts', {
          'action': action,
          'authId': authId,
        });
        if (mounted) {
          setState(
            () => cardNotices[authId] = action == 'logout'
                ? '已清除凭据，相关任务等待重新授权'
                : '凭据有效，相关任务可以执行',
          );
        }
      }
      await widget.onChanged?.call();
    } on PlatformException catch (failure) {
      if (mounted) {
        setState(() => cardErrors[authId] = failure.message ?? '凭据操作未完成，请重试');
      }
    } finally {
      if (mounted) setState(() => busyAuthId = null);
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
      await act(action, entry);
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
    final authType = entry['type'] as String? ?? 'web-cookie';
    final supported =
        authType == 'token' ||
        ((entry['loginUrl'] as String? ?? '').startsWith('https://') &&
            (entry['requiredCookies'] as List? ?? []).isNotEmpty);
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
    final authId = entry['id'] as String;
    final cardBusy = busyAuthId == authId;
    final cardError = cardErrors[authId];
    final cardNotice = cardNotices[authId];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cardBusy) const LinearProgressIndicator(minHeight: 2),
            ListTile(
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
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.onSurfaceVariant,
                  ),
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
                      cardBusy
                          ? '正在检查…'
                          : ready
                          ? '已登录'
                          : '等待登录',
                      if (tasks.length > 1) '${tasks.length} 个任务',
                    ].join(' · '),
                  ),
                  if (tasks.length == 1)
                    Text(
                      tasks.single['name'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (!ready && entry['message'] != null && cardError == null)
                    Text(
                      entry['message'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
              trailing: cardBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : supported
                  ? const Icon(Icons.chevron_right, size: 18)
                  : null,
            ),
            if (cardError != null || cardNotice != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                decoration: BoxDecoration(
                  color: cardError != null
                      ? colors.errorContainer.withValues(alpha: .45)
                      : colors.primaryContainer.withValues(alpha: .35),
                  border: Border(
                    top: BorderSide(
                      color: colors.outlineVariant.withValues(alpha: .45),
                    ),
                  ),
                ),
                child: Text(
                  cardError ?? cardNotice!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: cardError != null ? colors.error : colors.onSurface,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
