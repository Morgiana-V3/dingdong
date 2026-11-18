import '../../ui/selection_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/inbox_repository.dart';
import '../../ui/theme.dart';

bool isHttpsUpgrade(String previous, String next) {
  final old = Uri.tryParse(previous);
  final target = Uri.tryParse(next);
  return old != null &&
      target != null &&
      old.scheme == 'http' &&
      target.scheme == 'https' &&
      old.host.isNotEmpty &&
      old.host == target.host &&
      old.port == 80 &&
      target.port == 443 &&
      [old, target].every(
        (uri) =>
            uri.userInfo.isEmpty &&
            !uri.hasQuery &&
            !uri.hasFragment &&
            (uri.path.isEmpty || uri.path == '/'),
      );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.repository,
    required this.settings,
    required this.onChanged,
    this.connectionOnly = false,
  });
  final bool connectionOnly;
  final InboxRepository repository;
  final Map<String, dynamic> settings;
  final VoidCallback onChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final address = TextEditingController(
    text: widget.settings['endpoint'] as String? ?? '',
  );
  final token = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  bool reveal = false;
  late bool directConnection = widget.settings['directConnection'] == true;
  String? error;
  String? result;
  String? diagnostic;

  bool get usesSavedAddress {
    try {
      final next = normalizeEndpoint(address.text);
      final previous = widget.settings['endpoint'] as String? ?? '';
      return next == previous || isHttpsUpgrade(previous, next);
    } on FormatException {
      return false;
    }
  }

  @override
  void dispose() {
    address.dispose();
    token.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
      result = null;
    });
    try {
      final endpoint = normalizeEndpoint(address.text);
      address.text = endpoint;
      await widget.repository.connect(
        endpoint,
        token.text.trim(),
        directConnection: directConnection,
      );
      token.clear();
      widget.onChanged();
    } catch (_) {
      if (mounted) setState(() => error = '无法连接，请检查服务器地址和接收密钥');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      widget.onChanged();
    } on PlatformException catch (failure) {
      if (mounted) setState(() => error = failure.message ?? '操作未完成，请重试');
    } catch (_) {
      if (mounted) setState(() => error = '操作未完成，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _restore() async {
    final confirmed = await showAppSheet<bool>(
      context: context,
      builder: (context) => SheetDialog(
        title: const Text('导入备份？'),
        content: const Text('消息与现有内容合并，重复 ID 会跳过。不会覆盖服务器地址或密钥。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('选择备份'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _perform(() async {
      final imported = await widget.repository.restore();
      if (imported != null && mounted) {
        setState(
          () => result =
              '已导入 ${imported['inserted']} 条，跳过 ${imported['skipped']} 条重复消息',
        );
      }
    });
  }

  String _dateLabel(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = widget.settings['status'] as String? ?? '未连接';
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
      children: [
        if (widget.connectionOnly) ...[
          Row(
            children: [
              Icon(Icons.dns_outlined, color: colors.primary),
              const SizedBox(width: 10),
              const Text(
                '服务器',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if ((widget.settings['lastConnectedAt'] as int? ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '最近连接成功：${_dateLabel(widget.settings['lastConnectedAt'] as int)}',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ),
          if ((widget.settings['retryAt'] as int? ?? 0) >
              DateTime.now().millisecondsSinceEpoch)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '正在等待自动重试',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 22),
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: address,
                  onChanged: (_) => setState(() {}),
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'IP:端口 或 https://域名',
                  ),
                  validator: (value) {
                    try {
                      normalizeEndpoint(value ?? '');
                      return null;
                    } on FormatException catch (error) {
                      return error.message;
                    }
                  },
                ),
                if (Uri.tryParse(address.text)?.scheme == 'http' &&
                    Uri.tryParse(address.text)?.port == 80)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('改用 HTTPS 加密连接'),
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              final uri = Uri.parse(address.text);
                              address.text = Uri(
                                scheme: 'https',
                                host: uri.host,
                              ).toString();
                            }),
                    ),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: token,
                  obscureText: !reveal,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: '接收密钥',
                    hintText: widget.settings['hasToken'] == true
                        ? '留空保留当前密钥'
                        : '填写服务器的接收密钥',
                    suffixIcon: IconButton(
                      tooltip: reveal ? '隐藏密钥' : '显示密钥',
                      onPressed: busy
                          ? null
                          : () async {
                              if (token.text.isEmpty &&
                                  widget.settings['hasToken'] == true) {
                                await _perform(() async {
                                  await InboxRepository.channel
                                      .invokeMethod<void>('showSavedToken');
                                });
                              } else {
                                setState(() => reveal = !reveal);
                              }
                            },
                      icon: Icon(
                        reveal
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final entered = value?.trim() ?? '';
                    if (entered.isEmpty &&
                        widget.settings['hasToken'] == true &&
                        usesSavedAddress) {
                      return null;
                    }
                    return entered.length >= 32
                        ? null
                        : '接收密钥至少 32 个字符；更换服务器需重新填写';
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  '公网服务器支持 HTTPS 时，建议使用加密连接，避免代理或网络中间环节干扰消息长连接。同一服务器从 HTTP 升级到 HTTPS 可保留密钥和消息记录。',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('服务器直连'),
                  subtitle: const Text(
                    '开启后，仅叮咚服务器使用 Wi-Fi 或移动网络直连，外部 App 仍使用原有代理。修改后点击保存。',
                  ),
                  value: directConnection,
                  onChanged: busy
                      ? null
                      : (value) => setState(() => directConnection = value),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: busy ? null : _connect,
                  child: Text(busy ? '正在保存…' : '保存并连接'),
                ),
                if (widget.settings['enabled'] == true)
                  TextButton(
                    onPressed: () => _perform(widget.repository.disconnect),
                    child: const Text('暂停接收'),
                  ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: busy
                ? null
                : () => _perform(() async {
                    final checked = await widget.repository.diagnose();
                    if (mounted) setState(() => diagnostic = checked);
                  }),
            icon: const Icon(Icons.network_check),
            label: Text(busy ? '正在处理…' : '检查已保存的连接'),
          ),
          if (diagnostic != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(diagnostic!),
            ),
          if (error != null)
            InlineNotice(error!, onDismiss: () => setState(() => error = null)),
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
        ],
        if (!widget.connectionOnly) ...[
          if (error != null)
            InlineNotice(error!, onDismiss: () => setState(() => error = null)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_none_rounded),
            title: const Text('通知与后台运行'),
            subtitle: Text(
              widget.settings['notifications'] == false
                  ? '通知权限未开启，点击前往系统设置'
                  : '允许后台运行，并将省电策略设为不限制',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _perform(widget.repository.systemSettings),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('导出本地消息'),
            subtitle: const Text('包含正文、图片、收藏和来源静默设置，不包含密钥'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy
                ? null
                : () => _perform(() async {
                    final exported = await widget.repository.export();
                    if (exported && mounted) {
                      setState(() => result = '已导出到所选位置');
                    }
                  }),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.file_upload_outlined),
            title: const Text('导入备份'),
            subtitle: const Text('合并消息，跳过重复内容'),
            trailing: const Icon(Icons.chevron_right),
            onTap: busy ? null : _restore,
          ),
          if (result != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(result!),
            ),
          const SizedBox(height: 24),
          Text(
            '叮咚  0.1.0',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '消息保存到手机后，服务器清理正文。换机或卸载前请导出。已开启接收时，重启后会尝试自动恢复；小米系统需允许自启动和后台运行。',
            style: TextStyle(
              fontSize: 12,
              height: 1.7,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}
