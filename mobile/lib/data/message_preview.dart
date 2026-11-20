import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart';
import '../features/reader/document.dart';

bool _isDecoration(Element image) {
  for (Element? node = image; node != null; node = node.parent) {
    if (node.attributes.containsKey('hidden') ||
        node.attributes['aria-hidden'] == 'true' ||
        node.attributes['role'] == 'presentation' ||
        node.classes.any(
          const {'avatar', 'emoji', 'tieba-emoticon'}.contains,
        ) ||
        node.localName == 'template' ||
        node.localName == 'noscript') {
      return true;
    }
  }
  return false;
}

class MessagePreview {
  const MessagePreview({
    this.headline = '',
    this.description = '',
    this.taskName = '',
    this.cover,
    this.hasTranslation = false,
  });
  final String headline;
  final String description;
  final String taskName;
  final Uint8List? cover;
  final bool hasTranslation;
}

String _plain(Element? element) =>
    (element?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

typedef _PreviewParts = ({
  String headline,
  String description,
  String taskName,
  bool hasTranslation,
  List<Uint8List> images,
});

_PreviewParts _previewParts((String, String) input) {
  final document = parseMessageDocument(input.$1, input.$2);
  final taskName = input.$2 == 'html'
      ? (document.head
                    ?.querySelector('meta[name="dingdong:task"]')
                    ?.attributes['content'] ??
                '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
      : '';
  final post = document
      .querySelectorAll('main > article.post')
      .where((post) => post.querySelector('.post-content') != null)
      .firstOrNull;
  final body = post?.querySelector('.post-content');
  final heading = body?.querySelector('h2, h1, h3');
  var headline = _plain(heading);
  final paragraph = body?.querySelector('.original p, p, pre');
  var description = _plain(paragraph);
  if (headline.isEmpty || const {'查看原帖', '无标题帖子'}.contains(headline)) {
    headline = description;
    description = '';
  }
  var hasTranslation = false;
  var metaCover = '';
  if (input.$2 == 'html') {
    final head = document.head;
    String meta(String selector) =>
        head?.querySelector(selector)?.attributes['content']?.trim() ?? '';
    final originalTitle = meta('meta[name="dingdong:original-title"]');
    final metaTitle = meta('meta[name="dingdong:title"]').isNotEmpty
        ? meta('meta[name="dingdong:title"]')
        : meta('meta[property="og:title"]');
    final metaDesc = meta('meta[name="dingdong:description"]').isNotEmpty
        ? meta('meta[name="dingdong:description"]')
        : meta('meta[property="og:description"]');
    metaCover = meta('meta[name="dingdong:cover"]');
    if (originalTitle.isNotEmpty && metaTitle.isNotEmpty) {
      hasTranslation = true;
    }
    if (metaTitle.isNotEmpty) {
      headline = metaTitle;
    }
    if (metaDesc.isNotEmpty) {
      description = metaDesc;
    }
  }
  // Keep the photograph paired with the same post as the headline.
  final root = post ?? document;
  final images = root.querySelectorAll('img');
  final result = <Uint8List>[];
  final seen = <String>{};
  void addImageSrc(String src) {
    final trimmed = src.trim();
    if (!trimmed.startsWith('data:image/') || !seen.add(trimmed)) return;
    final embedded = EmbeddedImage.fromDataUri(trimmed, '');
    if (embedded != null) result.add(embedded.bytes);
  }

  if (metaCover.isNotEmpty) {
    if (metaCover.startsWith('data:image/')) {
      addImageSrc(metaCover);
    } else {
      final explicit = document.getElementById(metaCover);
      if (explicit != null && explicit.localName == 'img') {
        addImageSrc(explicit.attributes['src'] ?? '');
      }
    }
  }
  // Studio wraps article photos in figures. Prefer editorial images over
  // decorative artwork, keeping document order within each group.
  final preferred = root
      .querySelectorAll('figure img, img.video-cover')
      .toSet();
  for (final image in [
    ...preferred,
    ...images.where((img) => !preferred.contains(img)),
  ]) {
    if (_isDecoration(image)) continue;
    addImageSrc(image.attributes['src'] ?? '');
  }
  return (
    headline: String.fromCharCodes(headline.runes.take(180)),
    description: String.fromCharCodes(description.runes.take(320)),
    taskName: String.fromCharCodes(taskName.runes.take(80)),
    hasTranslation: hasTranslation,
    images: result,
  );
}

Future<MessagePreview> messagePreview(String content, String format) async {
  final parts = await compute(_previewParts, (content, format));
  return MessagePreview(
    headline: parts.headline,
    description: parts.description,
    taskName: parts.taskName,
    hasTranslation: parts.hasTranslation,
    cover: await _thumbnail(parts.images),
  );
}

Future<Uint8List?> _thumbnail(List<Uint8List> candidates) async {
  for (final bytes in candidates) {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? frame;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (math.min(width, height) < 24 || width * height > 50000000) continue;
      final scale = math.min(1.0, 280 / math.max(width, height));
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (width * scale).round()),
        targetHeight: math.max(1, (height * scale).round()),
      );
      frame = (await codec.getNextFrame()).image;
      final png = await frame.toByteData(format: ui.ImageByteFormat.png);
      if (png != null) {
        return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
      }
    } on Exception {
      // A damaged embedded image need not hide a later valid photo.
      continue;
    } finally {
      frame?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
  return null;
}
