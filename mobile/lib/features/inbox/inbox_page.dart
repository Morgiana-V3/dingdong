import 'dart:async';
import 'dart:ui' as ui;
import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../data/inbox_repository.dart';
import '../../ui/content_route.dart';
import '../../ui/theme.dart';
import '../reader/reader_page.dart';
import '../settings/settings_page.dart';
import 'message_tile.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({super.key, required this.repository});
  final InboxRepository repository;
  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> with WidgetsBindingObserver {
  List<InboxMessage> messages = [];
  Map<String, dynamic> settings = {};
  Set<String> muted = {};
  Timer? timer;
  Timer? searchDebounce;
  int searchRevision = 0;
  List<InboxMessage> searchResults = [];
  DateTimeRange? dateRange;
  bool searching = false;
  bool acting = false;
  final selectedIds = <String>{};
  bool refreshing = false;
  bool openingMessage = false;
  bool loading = true;
  String? error;
  int page = 0;
  int filter = 0;
  String query = '';
  String? source;
  final searchController = TextEditingController();
  final inboxCaptureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    InboxRepository.channel.setMethodCallHandler((call) async {
      if (call.method == 'openMessage') await _openId(call.arguments as String);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initialize();
      }
    });
    timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  Future<void> _initialize() async {
    await _refresh();
    final id = await InboxRepository.channel.invokeMethod<String>(
      'launchMessage',
    );
    if (id != null) await _openId(id);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    timer?.cancel();
    if (state == AppLifecycleState.resumed) {
      _refresh();
      timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    InboxRepository.channel.setMethodCallHandler(null);
    timer?.cancel();
    searchDebounce?.cancel();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (refreshing ||
        openingMessage ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    refreshing = true;
    try {
      final loaded = await widget.repository.messages();
      final config = await widget.repository.settings();
      final sources = await widget.repository.mutedSources();
      if (mounted) {
        setState(() {
          messages = loaded;
          settings = config;
          muted = sources;
          loading = false;
          selectedIds.retainAll(loaded.map((message) => message.id));
        });
        if (query.trim().isNotEmpty || dateRange != null) await _search();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = '无法读取消息，请稍后重试';
          loading = false;
        });
      }
    } finally {
      refreshing = false;
    }
  }

  Future<void> _openId(String id) async {
    final loaded = await widget.repository.messages();
    final matches = loaded.where((message) => message.id == id);
    if (matches.isNotEmpty && mounted) await _open(matches.first);
  }

  Future<void> _open(InboxMessage message) async {
    if (openingMessage) {
      return;
    }
    openingMessage = true;
    FocusManager.instance.primaryFocus?.unfocus();
    ui.Image? inboxFrame;
    final ready = ValueNotifier(false);
    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) {
        return;
      }
      final boundary =
          inboxCaptureKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      inboxFrame = await boundary.toImage(
        pixelRatio: MediaQuery.devicePixelRatioOf(context).clamp(1, 2),
      );
      if (!mounted) {
        return;
      }
      String? preparationError;
      final route = readerRoute<String>(
        context,
        (readerContext) => ReaderPage(
          message: message,
          repository: widget.repository,
          onReady: () => ready.value = true,
          onPreparationFailed: () {
            preparationError = '帖子未能打开，请重试';
            Navigator.of(readerContext).pop();
          },
        ),
        ready: ready,
        background: RawImage(image: inboxFrame, fit: BoxFit.fill),
      );
      final deletedId = await Navigator.of(context).push(route);
      // Keep the underlying list still until the reader has disappeared.
      await route.completed;
      if (!mounted) {
        return;
      }
      openingMessage = false;
      await _refresh();
      if (preparationError != null && mounted) {
        setState(() => error = preparationError);
      }
      if (deletedId != null && mounted) {
        _offerUndo([deletedId]);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = '帖子未能打开，请重试');
      }
    } finally {
      inboxFrame?.dispose();
      ready.dispose();
      openingMessage = false;
    }
  }

  void _navigate(int destination, {int messageFilter = 0}) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop();
    setState(() {
      page = destination;
      filter = messageFilter;
      source = null;
      selectedIds.clear();
    });
  }

  Future<void> _search() async {
    final revision = ++searchRevision;
    try {
      final matches = await widget.repository.messages(
        query: query.trim(),
        after: dateRange?.start,
        before: dateRange == null
            ? null
            : DateTime(
                dateRange!.end.year,
                dateRange!.end.month,
                dateRange!.end.day + 1,
              ),
      );
      if (mounted && revision == searchRevision) {
        setState(() {
          searchResults = matches;
          searching = false;
        });
      }
    } catch (_) {
      if (mounted && revision == searchRevision) {
        setState(() {
          error = '搜索失败，请重试';
          searching = false;
        });
      }
    }
  }

  void _queryChanged(String value) {
    searchDebounce?.cancel();
    searchRevision++;
    setState(() {
      query = value;
      selectedIds.clear();
      searching = true;
      searchResults = [];
    });
    searchDebounce = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _pickDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: dateRange,
      helpText: '按接收日期筛选',
      saveText: '确定',
    );
    if (range == null || !mounted) return;
    setState(() {
      dateRange = range;
      selectedIds.clear();
      searching = true;
    });
    await _search();
  }

  List<InboxMessage> get visibleMessages {
    final candidates = query.trim().isNotEmpty || dateRange != null
        ? searchResults
        : messages;
    return candidates
        .where(
          (message) =>
              (filter != 1 || !message.isRead) &&
              (filter != 2 || message.starred) &&
              (source == null || message.source == source),
        )
        .toList();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!selectedIds.add(id)) selectedIds.remove(id);
    });
  }

  void _offerUndo(List<String> ids) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已删除 ${ids.length} 条消息'),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            try {
              await widget.repository.batch(ids, 'restore');
              await _refresh();
            } catch (_) {
              if (mounted) setState(() => error = '未能撤销，请重试');
            }
          },
        ),
      ),
    );
  }

  Future<void> _batch(
    String action, {
    List<String>? targets,
    bool value = true,
  }) async {
    final ids = targets ?? selectedIds.toList();
    if (ids.isEmpty || acting) return;
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('删除 ${ids.length} 条消息？'),
          content: const Text('删除后可短暂撤销。已送达的正文不能从服务器重新下载。'),
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
      if (confirmed != true || !mounted) return;
    }
    setState(() => acting = true);
    try {
      await widget.repository.batch(ids, action, value);
      if (!mounted) return;
      setState(selectedIds.clear);
      await _refresh();
      if (action == 'delete') _offerUndo(ids);
    } catch (_) {
      if (mounted) setState(() => error = '操作未完成，请重试');
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Widget _drawer() {
    final colors = Theme.of(context).colorScheme;
    final unread = messages.where((message) => !message.isRead).length;
    final starred = messages.where((message) => message.starred).length;
    Widget destination(
      String label,
      IconData icon,
      int target, {
      int messageFilter = 0,
      int? count,
    }) {
      final selected =
          page == target &&
          (target != 0 || (filter == messageFilter && source == null));
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          selected: selected,
          selectedColor: colors.primary,
          selectedTileColor: colors.primary.withValues(alpha: .10),
          leading: Icon(icon, size: 22),
          title: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          trailing: count == null ? null : Text('$count'),
          onTap: () => _navigate(target, messageFilter: messageFilter),
        ),
      );
    }

    return Drawer(
      width: MediaQuery.sizeOf(context).width.clamp(0, 360) - 40,
      backgroundColor: colors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 24, 20),
              child: Text('消息', style: Theme.of(context).textTheme.titleLarge),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  destination(
                    '全部消息',
                    Icons.inbox_outlined,
                    0,
                    count: messages.length,
                  ),
                  destination(
                    '未读',
                    Icons.mark_email_unread_outlined,
                    0,
                    messageFilter: 1,
                    count: unread,
                  ),
                  destination(
                    '收藏',
                    Icons.bookmark_border_rounded,
                    0,
                    messageFilter: 2,
                    count: starred,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Divider(height: 1),
                  ),
                  destination('来源', Icons.grid_view_outlined, 1),
                ],
              ),
            ),
            destination('设置', Icons.tune_rounded, 2),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 6, 24, 12),
              child: Text(
                settings['status'] as String? ?? '未连接',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = page == 0
        ? (source ?? ['收件箱', '未读消息', '收藏'][filter])
        : ['收件箱', '来源', '设置'][page];
    return PopScope(
      canPop: selectedIds.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selectedIds.isNotEmpty) setState(selectedIds.clear);
      },
      child: RepaintBoundary(
        key: inboxCaptureKey,
        child: Scaffold(
          drawer: selectedIds.isEmpty ? _drawer() : null,
          drawerEnableOpenDragGesture: false,
          appBar: AppBar(
            leading: selectedIds.isNotEmpty
                ? IconButton(
                    tooltip: '取消多选',
                    onPressed: () => setState(selectedIds.clear),
                    icon: const Icon(Icons.close),
                  )
                : Builder(
                    builder: (context) => IconButton(
                      tooltip: '打开菜单',
                      icon: const Icon(Icons.menu_rounded),
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Scaffold.of(context).openDrawer();
                      },
                    ),
                  ),
            title: Text(
              selectedIds.isEmpty ? title : '已选 ${selectedIds.length} 条',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (selectedIds.isNotEmpty)
                IconButton(
                  tooltip: '全选当前列表',
                  icon: const Icon(Icons.select_all),
                  onPressed: () => setState(
                    () => selectedIds.addAll(
                      visibleMessages.map((message) => message.id),
                    ),
                  ),
                ),
              if (page == 0 && selectedIds.isEmpty)
                PopupMenuButton<String>(
                  tooltip: '消息操作',
                  onSelected: (_) => _batch(
                    'read',
                    targets: visibleMessages
                        .map((message) => message.id)
                        .toList(),
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'read', child: Text('当前列表全部已读')),
                  ],
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                if (error != null)
                  InlineNotice(
                    error!,
                    onDismiss: () => setState(() => error = null),
                  ),
                Expanded(
                  child: PageTransitionSwitcher(
                    duration: Duration(
                      milliseconds: MediaQuery.disableAnimationsOf(context)
                          ? 0
                          : 240,
                    ),
                    transitionBuilder: (child, animation, secondaryAnimation) =>
                        FadeThroughTransition(
                          animation: animation,
                          secondaryAnimation: secondaryAnimation,
                          fillColor: colors.surface,
                          child: child,
                        ),
                    child: KeyedSubtree(
                      key: ValueKey('$page/$filter/$source'),
                      child: switch (page) {
                        0 => ColoredBox(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? colors.surface
                              : const Color(0xFFF3F4F5),
                          child: _inbox(),
                        ),
                        1 => _sources(),
                        _ => SettingsPage(
                          repository: widget.repository,
                          settings: settings,
                          onChanged: _refresh,
                        ),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: selectedIds.isEmpty
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceEvenly,
                      children: [
                        TextButton.icon(
                          onPressed: acting ? null : () => _batch('read'),
                          icon: const Icon(Icons.done_all),
                          label: const Text('已读'),
                        ),
                        TextButton.icon(
                          onPressed: acting ? null : () => _batch('starred'),
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: const Text('收藏'),
                        ),
                        TextButton.icon(
                          onPressed: acting
                              ? null
                              : () => _batch('starred', value: false),
                          icon: const Icon(Icons.bookmark_remove_outlined),
                          label: const Text('取消收藏'),
                        ),
                        TextButton.icon(
                          onPressed: acting ? null : () => _batch('delete'),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('删除'),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _inbox() {
    final colors = Theme.of(context).colorScheme;
    final visible = visibleMessages;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: '搜索消息正文、标题或来源',
              suffixIcon: IconButton(
                tooltip: '按日期筛选',
                icon: const Icon(Icons.date_range_outlined),
                onPressed: _pickDates,
              ),
              prefixIcon: Icon(Icons.search, size: 21),
            ),
            onChanged: _queryChanged,
          ),
        ),
        if (dateRange != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InputChip(
                label: Text(
                  '${dateRange!.start.month}/${dateRange!.start.day} — ${dateRange!.end.month}/${dateRange!.end.day}',
                ),
                onDeleted: () {
                  setState(() => dateRange = null);
                  _search();
                },
              ),
            ),
          ),
        Expanded(
          child: loading || searching
              ? const Center(child: CircularProgressIndicator())
              : visible.isEmpty
              ? _empty(
                  messages.isEmpty ? '还没有消息' : '没有符合条件的消息',
                  messages.isEmpty ? '连接服务器后，脚本发送的内容会出现在这里。' : '试试其他关键词或筛选条件。',
                  action: messages.isEmpty
                      ? () => setState(() => page = 2)
                      : null,
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final message = visible[index];
                      final date = DateUtils.dateOnly(message.createdAt);
                      final showDate =
                          index == 0 ||
                          date !=
                              DateUtils.dateOnly(visible[index - 1].createdAt);
                      return Column(
                        key: ValueKey(message.id),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showDate)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
                              child: Text(
                                date == DateUtils.dateOnly(DateTime.now())
                                    ? '今天'
                                    : '${date.month}月${date.day}日',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            child: MessageTile(
                              key: ValueKey(message.id),
                              message: message,
                              onTap: () {
                                if (selectedIds.isEmpty) {
                                  _open(message);
                                } else {
                                  _toggleSelection(message.id);
                                }
                              },
                              onLongPress: () => _toggleSelection(message.id),
                              selecting: selectedIds.isNotEmpty,
                              selected: selectedIds.contains(message.id),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _empty(String title, String subtitle, {VoidCallback? action}) {
    final child = Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 40,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.7,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 22),
                FilledButton(onPressed: action, child: const Text('连接服务器')),
              ],
            ],
          ),
        ),
      ),
    );
    return MediaQuery.disableAnimationsOf(context)
        ? child
        : child.animate().fadeIn(duration: 180.ms);
  }

  Widget _sources() {
    final sources = messages.map((message) => message.source).toSet().toList()
      ..sort();
    if (sources.isEmpty) return _empty('还没有来源', '收到消息后，按脚本填写的来源自动分组。');
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      itemCount: sources.length,
      separatorBuilder: (_, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final name = sources[index];
        final count = messages
            .where((message) => message.source == name)
            .length;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          leading: SourceAvatar(name),
          title: Text(name),
          subtitle: Text('$count 条消息'),
          trailing: IconButton(
            tooltip: muted.contains(name) ? '开启此来源通知' : '静默接收此来源',
            icon: Icon(
              muted.contains(name)
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_none,
            ),
            onPressed: () async {
              try {
                await widget.repository.mute(name, !muted.contains(name));
                await _refresh();
              } catch (_) {
                if (mounted) setState(() => error = '无法修改通知设置');
              }
            },
          ),
          onTap: () => setState(() {
            source = name;
            filter = 0;
            page = 0;
          }),
        );
      },
    );
  }
}
