import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../../data/inbox_repository.dart';
import 'document.dart';

class ImageViewer extends StatefulWidget {
  const ImageViewer({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.repository,
  });
  final List<EmbeddedImage> images;
  final int initialIndex;
  final InboxRepository repository;

  static ImageProvider imageProvider(EmbeddedImage image) => ResizeImage(
    MemoryImage(image.bytes),
    width: 2048,
    height: 2048,
    policy: ResizeImagePolicy.fit,
    allowUpscaling: false,
  );

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final pages = PageController(initialPage: widget.initialIndex);
  late int index = widget.initialIndex;
  bool saving = false;

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => saving = true);
    final image = widget.images[index];
    try {
      final saved = await widget.repository.saveImage(image.bytes, image.mime);
      if (saved && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('图片已保存')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请检查可用空间')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(
        '${index + 1} / ${widget.images.length}',
        style: const TextStyle(fontSize: 14, color: Colors.white),
      ),
      actions: [
        IconButton(
          tooltip: saving ? '正在保存' : '保存图片',
          onPressed: saving ? null : _save,
          icon: const Icon(Icons.download_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: PhotoViewGallery.builder(
        pageController: pages,
        itemCount: widget.images.length,
        onPageChanged: (value) => setState(() => index = value),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        builder: (context, position) => PhotoViewGalleryPageOptions(
          imageProvider: ImageViewer.imageProvider(widget.images[position]),
          initialScale: PhotoViewComputedScale.contained,
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.contained * 5,
          errorBuilder: (_, error, stack) => const Center(
            child: Text('无法显示这张图片', style: TextStyle(color: Colors.white)),
          ),
        ),
      ),
    ),
  );
}
