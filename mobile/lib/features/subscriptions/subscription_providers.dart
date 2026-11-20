import '../../ui/theme.dart';
import '../../ui/selection_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'subscription_style.dart';
import 'ai_vendors.dart';

class ServerConfigurationPage extends StatefulWidget {
  const ServerConfigurationPage({
    super.key,
    required this.load,
    required this.save,
    this.models,
    this.revealKey,
    this.testConnection,
  });
  final Map<String, dynamic> Function() load;
  final Future<List<String>> Function(Map<String, dynamic>)? models;
  final Future<String> Function(String id)? revealKey;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
  testConnection;
  final Future<void> Function(Map<String, dynamic>) save;
  @override
  State<ServerConfigurationPage> createState() =>
      _ServerConfigurationPageState();
}

class _ServerConfigurationPageState extends State<ServerConfigurationPage> {
  String? error;
  Future<void> edit([Map<String, dynamic>? provider]) async {
    final revision = widget.load()['revision'];
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _ProviderEditor(
          provider: provider,
          models: widget.models,
          revealKey: widget.revealKey,
          testConnection: widget.testConnection,
          save: (values) => widget.save({
            'action': 'saveProvider',
            'revision': revision,
            'provider': values,
          }),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> remove(Map<String, dynamic> provider) async {
    final confirmed = await showAppSheet<bool>(
      context: context,
      builder: (context) => SheetDialog(
        title: const Text('删除 AI 配置？'),
        content: Text(provider['name'] as String),
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
    if (confirmed != true) return;
    try {
      await widget.save({'action': 'deleteProvider', 'id': provider['id']});
      if (mounted) setState(() => error = null);
    } on PlatformException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    }
  }

  bool needsAI(Map<String, dynamic> task) {
    final plugin = studioItems(
      widget.load()['plugins'],
    ).where((plugin) => plugin['id'] == task['pluginId']).firstOrNull;
    final caps = plugin?['capabilities'] as List? ?? [];
    return caps.contains('ai.required') ||
        caps.contains('ai.optional') ||
        caps.contains('ai.tools') ||
        (task['config'] as Map?)?['useAI'] == true;
  }

  Future<void> assign(Map<String, dynamic> task) async {
    final snapshot = widget.load();
    final providers = studioItems(snapshot['providers']);
    final selected = await showChoiceSheet<String>(
      context: context,
      title: '选择 AI 配置',
      selected: task['providerId'] as String?,
      choices: [
        for (final provider in providers)
          SheetChoice(
            value: provider['id'] as String,
            label: provider['name'] as String,
            description: provider['model'] as String?,
          ),
      ],
    );
    if (selected == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save({
        'action': 'save',
        'revision': snapshot['revision'],
        'id': task['id'],
        'name': task['name'],
        'pluginId': task['pluginId'],
        'config': task['config'],
        'schedule': task['schedule'],
        'minutes': task['minutes'],
        'enabled': task['enabled'],
        'onlyChanged': task['onlyChanged'] != false,
        'providerId': selected,
      });
    } on PlatformException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool busy = false;

  void help() {
    showAppSheet<void>(
      context: context,
      builder: (context) => const SheetDialog(
        title: Text('服务器配置说明'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('手机负责管理，服务器保存配置并执行任务。API Key 加密保存在服务器。'),
            SizedBox(height: 12),
            Text('AI 服务需要支持 Responses API 与工具调用，调用按服务商规则计费。'),
            SizedBox(height: 12),
            Text('添加服务后，在“任务关联”中选择使用它的任务。统一推送沿用各来源的 AI 配置。'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.load();
    final providers = studioItems(snapshot['providers']);
    final tasks = studioItems(snapshot['tasks']).where(needsAI).toList();
    final plugins = studioItems(
      snapshot['plugins'],
    ).where((p) => p['legacy'] != true).toList();
    final colors = Theme.of(context).colorScheme;
    return SubscriptionStyle(
      child: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('服务器配置'),
            actions: [
              IconButton(
                tooltip: '配置说明',
                onPressed: help,
                icon: const Icon(Icons.help_outline_rounded),
              ),
            ],
            bottom: TabBar(
              isScrollable: MediaQuery.textScalerOf(context).scale(14) > 20,
              tabAlignment: MediaQuery.textScalerOf(context).scale(14) > 20
                  ? TabAlignment.center
                  : TabAlignment.fill,
              tabs: const [
                Tab(text: 'AI 服务'),
                Tab(text: '任务关联'),
                Tab(text: '插件'),
              ],
            ),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: pageInsets(context, top: 10, bottom: 6),
                child: Text(
                  snapshot['endpoint'] as String? ?? '当前叮咚服务器',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              if (busy) const LinearProgressIndicator(minHeight: 2),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Text(
                    error!,
                    style: TextStyle(color: colors.error, fontSize: 12),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    ListView(
                      padding: pageInsets(context, top: 4),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${providers.length} 项服务',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: busy ? null : edit,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('添加 AI 配置'),
                            ),
                          ],
                        ),
                        if (providers.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text('尚未添加 AI 服务。添加后，在“任务关联”中分配给订阅任务。'),
                          ),
                        for (final provider in providers)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              child: ListTile(
                                title: Text(provider['name'] as String),
                                subtitle: Text(
                                  '${provider['model']} · ${Uri.tryParse(provider['baseUrl'] as String? ?? '')?.host ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: busy ? null : () => edit(provider),
                                trailing: SheetMenuButton<String>(
                                  tooltip: 'AI 服务操作 · ${provider['name']}',
                                  choices: [
                                    SheetChoice(
                                      value: 'edit',
                                      label: '编辑',
                                      enabled: !busy,
                                    ),
                                    SheetChoice(
                                      value: 'delete',
                                      label: '删除',
                                      enabled: !busy,
                                    ),
                                  ],
                                  onSelected: (value) {
                                    if (value == 'edit') {
                                      edit(provider);
                                    } else {
                                      remove(provider);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    ListView(
                      padding: pageInsets(context, top: 10),
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text('统一推送使用各来源任务关联的 AI 服务。'),
                        ),
                        if (tasks.isEmpty) const Text('当前没有需要 AI 的任务。'),
                        if (providers.isEmpty && tasks.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text('请先在“AI 服务”页添加配置。'),
                          ),
                        for (final task in tasks)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              child: ListTile(
                                onTap: busy || providers.isEmpty
                                    ? null
                                    : () => assign(task),
                                title: Text(task['name'] as String),
                                subtitle: Text(
                                  providers
                                              .where(
                                                (p) =>
                                                    p['id'] ==
                                                    task['providerId'],
                                              )
                                              .firstOrNull?['name']
                                          as String? ??
                                      '等待 AI 配置',
                                ),
                                trailing: providers.isEmpty
                                    ? null
                                    : const Icon(Icons.chevron_right),
                              ),
                            ),
                          ),
                      ],
                    ),
                    ListView(
                      padding: pageInsets(context, top: 10),
                      children: [
                        for (final plugin in plugins)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              child: ListTile(
                                title: Text(plugin['name'] as String),
                                subtitle: plugin['description'] == null
                                    ? null
                                    : Text(plugin['description'] as String),
                                trailing:
                                    (plugin['capabilities'] as List? ?? [])
                                        .contains('ai.tools')
                                    ? const SubscriptionStatus('需要 AI')
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderEditor extends StatefulWidget {
  const _ProviderEditor({
    this.provider,
    required this.save,
    this.models,
    this.revealKey,
    this.testConnection,
  });
  final Future<List<String>> Function(Map<String, dynamic>)? models;
  final Future<String> Function(String id)? revealKey;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)?
  testConnection;
  final Map<String, dynamic>? provider;
  final Future<void> Function(Map<String, dynamic>) save;
  @override
  State<_ProviderEditor> createState() => _ProviderEditorState();
}

class _ProviderEditorState extends State<_ProviderEditor> {
  static const _savedKeyMask = '••••••••••••••••';
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.provider?['name'] as String? ?? '',
  );
  late final endpoint = TextEditingController(
    text: widget.provider?['baseUrl'] as String? ?? '',
  );
  late final model = TextEditingController(
    text: widget.provider?['model'] as String? ?? '',
  );
  late final limit = TextEditingController(
    text: '${widget.provider?['maxOutputTokens'] ?? 8000}',
  );
  late final bool hasSavedKey = widget.provider?['hasKey'] == true;
  late bool usingSavedMask = hasSavedKey;
  late final key = TextEditingController(
    text: hasSavedKey ? _savedKeyMask : '',
  );
  bool busy = false, visible = false, testing = false;
  String? error;
  String? testSuccess;

  String get effectiveKey => usingSavedMask ? '' : key.text.trim();

  @override
  void dispose() {
    for (final controller in [name, endpoint, model, limit, key]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> toggleKeyVisibility() async {
    if (visible) {
      setState(() => visible = false);
      return;
    }
    if (usingSavedMask &&
        widget.revealKey != null &&
        widget.provider?['id'] != null) {
      setState(() {
        busy = true;
        error = null;
      });
      try {
        final realKey = await widget.revealKey!(
          widget.provider!['id'] as String,
        );
        if (!mounted) return;
        setState(() {
          usingSavedMask = false;
          key.text = realKey;
          visible = true;
        });
      } on PlatformException catch (failure) {
        if (mounted) setState(() => error = failure.message ?? '无法读取已保存密钥');
      } catch (_) {
        if (mounted) setState(() => error = '无法读取已保存密钥');
      } finally {
        if (mounted) setState(() => busy = false);
      }
      return;
    }
    setState(() => visible = true);
  }

  Future<void> testAI() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (effectiveKey.isEmpty && !hasSavedKey) {
      setState(() => error = '请先输入 API Key');
      return;
    }
    if (model.text.trim().isEmpty) {
      setState(() => error = '请先选择或填写模型 ID');
      return;
    }
    if (widget.testConnection == null) return;
    setState(() {
      testing = true;
      error = null;
      testSuccess = null;
    });
    try {
      final result = await widget.testConnection!({
        'id': widget.provider?['id'],
        'baseUrl': endpoint.text.trim(),
        'model': model.text.trim(),
        'key': effectiveKey,
      });
      if (!mounted) return;
      final ms = result['latencyMs'];
      setState(
        () => testSuccess = ms != null ? '连接成功（响应耗时 $ms ms）' : '连接成功，模型已响应',
      );
    } on PlatformException catch (failure) {
      if (mounted) setState(() => error = failure.message ?? '测试连接失败');
    } catch (_) {
      if (mounted) setState(() => error = '测试连接失败，请检查地址、密钥与模型 ID');
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save({
        'id': widget.provider?['id'],
        'name': name.text.trim(),
        'baseUrl': endpoint.text.trim(),
        'model': model.text.trim(),
        'maxOutputTokens': int.parse(limit.text),
        'key': effectiveKey,
      });
      if (mounted) Navigator.pop(context);
    } on PlatformException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  late String vendorId =
      aiVendors.where((v) => v.baseUrl == endpoint.text).firstOrNull?.id ??
      (widget.provider == null ? 'openai' : 'custom');
  List<String> availableModels = [];

  @override
  void initState() {
    super.initState();
    if (widget.provider == null) {
      endpoint.text = aiVendors.first.baseUrl;
      name.text = aiVendors.first.name;
    }
  }

  void changeVendor(String id) {
    final vendor = aiVendors.firstWhere((v) => v.id == id);
    setState(() {
      vendorId = id;
      endpoint.text = vendor.baseUrl;
      name.text = vendor.name;
      usingSavedMask = false;
      key.clear();
      model.clear();
      availableModels = [];
      error = null;
      testSuccess = null;
    });
  }

  Future<void> chooseModel() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (effectiveKey.isEmpty &&
        !(hasSavedKey && endpoint.text == widget.provider?['baseUrl'])) {
      setState(() => error = '请先输入当前厂商的 API Key');
      return;
    }
    if (widget.models == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      availableModels = await widget.models!({
        'id': widget.provider?['id'],
        'baseUrl': endpoint.text.trim(),
        'key': effectiveKey,
      });
      if (!mounted) return;
      setState(() => busy = false);
      final selected = await showAppSheet<String>(
        context: context,
        builder: (context) => _ModelPicker(models: availableModels),
      );
      if (selected != null && mounted) setState(() => model.text = selected);
    } on PlatformException catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) setState(() => error = '读取模型列表失败，请检查服务地址和网络');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SubscriptionStyle(
    child: PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.provider == null ? '添加 AI 配置' : '编辑 AI 配置'),
        ),
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
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                SheetSelectField(
                  key: ValueKey('vendor/$vendorId'),
                  label: '模型厂商',
                  value: vendorId,
                  choices: [
                    for (final vendor in aiVendors)
                      SheetChoice(value: vendor.id, label: vendor.name),
                  ],
                  onChanged: changeVendor,
                ),
                const SizedBox(height: 12),
                if (vendorId != 'custom')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      endpoint.text,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (vendorId == 'custom')
                  TextFormField(
                    controller: endpoint,
                    decoration: const InputDecoration(labelText: 'API 基础地址'),
                    onChanged: (_) {
                      availableModels = [];
                    },
                    validator: (value) =>
                        Uri.tryParse(value ?? '')?.scheme == 'https'
                        ? null
                        : '请填写 HTTPS 地址',
                  ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: key,
                  obscureText: !visible,
                  autocorrect: false,
                  enableSuggestions: false,
                  onTap: () {
                    if (usingSavedMask) {
                      setState(() {
                        usingSavedMask = false;
                        key.clear();
                      });
                    }
                  },
                  onChanged: (_) {
                    if (usingSavedMask) usingSavedMask = false;
                    availableModels = [];
                    testSuccess = null;
                  },
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    helperText: hasSavedKey && usingSavedMask
                        ? '已加密保存，点击右侧眼睛可明文查看，或点击重新输入'
                        : '加密保存在服务器',
                    suffixIcon: IconButton(
                      tooltip: visible ? '隐藏密钥' : '明文查看密钥',
                      onPressed: busy ? null : toggleKeyVisibility,
                      icon: Icon(
                        visible ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                  validator: (value) =>
                      !hasSavedKey && (value == null || value.trim().isEmpty)
                      ? '请填写 API Key'
                      : null,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: chooseModel,
                  icon: const Icon(Icons.manage_search, size: 18),
                  label: Text(model.text.isEmpty ? '读取并选择模型' : model.text),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 6, bottom: 12),
                  child: Text(
                    '请选择支持工具调用的文本模型。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                SheetSelectField(
                  key: ValueKey('limit/${limit.text}'),
                  label: '最大输出 Token',
                  value: limit.text,
                  choices: [
                    for (final value in {
                      ...['2048', '4096', '8000', '16000', '32000'],
                      limit.text,
                    })
                      SheetChoice(value: value, label: value),
                  ],
                  onChanged: (value) => setState(() => limit.text = value),
                ),
                const SizedBox(height: 12),
                SettingsExpansion(
                  title: const Text('高级设置'),
                  children: [
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: '配置名称'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '请填写名称'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: model,
                      decoration: const InputDecoration(
                        labelText: '手动填写模型 ID',
                        helperText: '厂商未提供模型列表时可手动填写',
                      ),
                      onChanged: (_) => setState(() {}),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '请选择模型'
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (testSuccess != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(testSuccess!)),
                        ],
                      ),
                    ),
                  ),
                if (widget.testConnection != null) ...[
                  OutlinedButton.icon(
                    onPressed: busy || testing || model.text.trim().isEmpty
                        ? null
                        : testAI,
                    icon: testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check_rounded, size: 18),
                    label: Text(testing ? '正在测试连接…' : '测试连接'),
                  ),
                  const SizedBox(height: 10),
                ],
                FilledButton(
                  onPressed: busy || testing || model.text.trim().isEmpty
                      ? null
                      : submit,
                  child: const Text('保存配置'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.models});
  final List<String> models;
  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final items = widget.models
        .where((model) => model.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .65,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '选择模型',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭面板',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            PinnedHeaderSliver(
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: TextField(
                  autocorrect: false,
                  decoration: const InputDecoration(
                    hintText: '搜索模型',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => query = value.trim()),
                ),
              ),
            ),
            if (items.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('没有匹配的模型')),
                ),
              )
            else
              SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, index) => ListTile(
                  title: Text(
                    items[index],
                    style: const TextStyle(fontSize: 13),
                  ),
                  onTap: () => Navigator.pop(context, items[index]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
