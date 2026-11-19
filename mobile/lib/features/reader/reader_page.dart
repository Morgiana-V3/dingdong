import '../../ui/selection_sheet.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../data/inbox_repository.dart';
import '../../ui/content_route.dart';
import '../../ui/theme.dart';
import 'reader_frame.dart';
import 'document.dart';
import 'image_viewer.dart';
import 'external_link.dart';

class ReaderPage extends StatefulWidget {
  const ReaderPage({
    super.key,
    required this.message,
    required this.repository,
    required this.onReady,
    required this.onPreparationFailed,
  });
  final InboxMessage message;
  final InboxRepository repository;
  final VoidCallback onReady;
  final VoidCallback onPreparationFailed;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late final WebViewController controller;
  String? content;
  List<EmbeddedImage> images = [];
  String? error;
  bool preparationFinished = false;
  bool waitingForFrame = false;
  Timer? preparationTimeout;
  late bool starred = widget.message.starred;
  bool openingImage = false;
  bool preparingImage = false;
  bool documentRequested = false;
  bool openingLink = false;
  bool acting = false;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _prepareFrame(),
          onNavigationRequest: (request) {
            if (request.url == 'about:blank' ||
                request.url.startsWith('data:text/html')) {
              return NavigationDecision.navigate;
            }
            final uri = Uri.tryParse(request.url);
            if (uri?.scheme == 'dingdong-image') {
              final index = int.tryParse(uri!.pathSegments.lastOrNull ?? '');
              if (index != null &&
                  index >= 0 &&
                  index < images.length &&
                  mounted) {
                _openImage(index);
              }
              return NavigationDecision.prevent;
            }
            final link = externalLink(request.url);
            if (link != null && request.isMainFrame) {
              _openLink(link);
            }
            return NavigationDecision.prevent;
          },
          onWebResourceError: (failure) {
            if (mounted && failure.isForMainFrame == true) {
              _failPreparation();
            }
          },
        ),
      );
    preparationTimeout = Timer(const Duration(seconds: 15), _failPreparation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _load();
      }
    });
  }

  Future<void> _prepareFrame() async {
    if (!mounted ||
        !documentRequested ||
        waitingForFrame ||
        preparationFinished) {
      return;
    }
    waitingForFrame = true;
    try {
      await ReaderFrame.wait(controller);
      if (!mounted ||
          preparationFinished ||
          !(ModalRoute.of(context)?.isCurrent ?? false)) {
        return;
      }
      preparationFinished = true;
      preparationTimeout?.cancel();
      widget.onReady();
      await widget.repository.update(widget.message.id, 'read');
    } catch (_) {
      if (preparationFinished) {
        if (mounted) {
          setState(() => error = '未能更新已读状态，请重试');
        }
      } else {
        _failPreparation();
      }
    }
  }

  void _failPreparation() {
    if (!mounted || preparationFinished) {
      return;
    }
    preparationFinished = true;
    preparationTimeout?.cancel();
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      widget.onPreparationFailed();
    }
  }

  @override
  void dispose() {
    preparationTimeout?.cancel();
    unawaited(ReaderFrame.cancel(controller));
    super.dispose();
  }

  Future<void> _openImage(int index) async {
    if (openingImage || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    openingImage = true;
    final progressDelay = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() => preparingImage = true);
      }
    });
    try {
      await precacheImage(
        ImageViewer.imageProvider(images[index]),
        context,
        // The viewer supplies a visible fallback for a corrupt image.
        onError: (error, stack) {},
      );
      progressDelay.cancel();
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
        return;
      }
      setState(() => preparingImage = false);
      final route = imagePreviewRoute<void>(
        context,
        (_) => ImageViewer(
          images: images,
          initialIndex: index,
          repository: widget.repository,
        ),
      );
      await Navigator.of(context).push(route);
      await route.completed;
    } finally {
      progressDelay.cancel();
      openingImage = false;
      if (mounted) {
        setState(() => preparingImage = false);
      }
    }
  }

  Future<void> _openLink(Uri uri) async {
    if (openingLink ||
        !mounted ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return;
    }
    openingLink = true;
    try {
      final confirmed = await showAppSheet<bool>(
        context: context,
        builder: (context) => SheetDialog(
          title: const Text('打开外部链接'),
          content: Text(uri.toString()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('打开'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        try {
          final opened = await widget.repository.openExternalLink(
            uri.toString(),
          );
          if (!opened && mounted) setState(() => error = '没有可打开此链接的应用');
        } catch (_) {
          if (mounted) setState(() => error = '无法打开链接');
        }
      }
    } finally {
      openingLink = false;
    }
  }

  Future<void> _load() async {
    try {
      final loaded =
          content ?? await widget.repository.content(widget.message.id);
      if (!mounted) return;
      content = loaded;
      await controller.setBackgroundColor(
        Theme.of(context).colorScheme.surface,
      );
      if (!mounted) return;
      final embeddedImages = <EmbeddedImage>[];
      final document = buildDocument(
        loaded,
        widget.message.format,
        title: widget.message.title,
        images: embeddedImages,
        dark: Theme.of(context).brightness == Brightness.dark,
      );
      images = embeddedImages;
      documentRequested = true;
      await controller.loadHtmlString(document);
    } catch (_) {
      _failPreparation();
    }
  }

  Future<void> _action(String action) async {
    if (acting) return;
    setState(() => acting = true);
    try {
      if (action == 'delete') {
        final confirmed = await showAppSheet<bool>(
          context: context,
          builder: (context) => SheetDialog(
            title: const Text('删除这条消息？'),
            content: const Text('消息将从手机移除。服务器已确认送达的正文不会重新下载。'),
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
        await widget.repository.update(widget.message.id, 'delete');
        if (mounted) Navigator.pop(context, widget.message.id);
      } else if (action == 'read') {
        await widget.repository.update(widget.message.id, 'read', false);
        if (mounted) Navigator.pop(context);
      } else {
        await widget.repository.update(widget.message.id, 'starred', !starred);
        if (mounted) setState(() => starred = !starred);
      }
    } catch (_) {
      if (mounted) setState(() => error = '操作未完成，请重试');
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  Future<void> _showInfo() async {
    final message = widget.message;
    final date = message.createdAt;
    await showAppSheet<void>(
      context: context,
      builder: (context) => SheetDialog(
        title: const Text('消息信息'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              message.title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(message.source),
            const SizedBox(height: 6),
            Text(
              '${date.year}年${date.month}月${date.day}日 '
              '${date.hour.toString().padLeft(2, '0')}:'
              '${date.minute.toString().padLeft(2, '0')}',
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 48,
      title: Text(
        widget.message.source,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall,
      ),
      leading: BackButton(onPressed: () => Navigator.pop(context)),
      actions: [
        IconButton(
          tooltip: starred ? '取消收藏' : '收藏消息',
          onPressed: acting ? null : () => _action('starred'),
          icon: Icon(
            starred ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          ),
        ),
        SheetMenuButton<String>(
          tooltip: '更多',
          onSelected: (action) {
            if (action == 'info') {
              _showInfo();
            } else {
              _action(action);
            }
          },
          choices: [
            const SheetChoice(
              value: 'info',
              label: '消息信息',
              icon: Icons.info_outline,
            ),
            const SheetChoice(
              value: 'read',
              label: '标为未读',
              icon: Icons.mark_email_unread_outlined,
            ),
            const SheetChoice(
              value: 'delete',
              label: '删除消息',
              icon: Icons.delete_outline,
            ),
          ],
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          if (error != null)
            InlineNotice(error!, onDismiss: () => setState(() => error = null)),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: WebViewWidget(controller: controller)),
                if (preparingImage)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
