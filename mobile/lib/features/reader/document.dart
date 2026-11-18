import 'dart:convert';
import 'dart:typed_data';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'external_link.dart';

String buildDocument(
  String content,
  String format, {
  String? title,
  List<EmbeddedImage>? images,
  required bool dark,
}) {
  var source = content;
  if (format == 'markdown') {
    source = markdown.markdownToHtml(
      content,
      extensionSet: markdown.ExtensionSet.gitHubFlavored,
    );
  } else if (format == 'text') {
    source = '<pre>${const HtmlEscape().convert(content)}</pre>';
  }
  final document = html.parse(source);
  for (final anchor in document.querySelectorAll('a')) {
    // Keep all clicks in the existing WebView so navigation is intercepted even
    // for target=_blank links. App/intent handling never executes page scripts.
    anchor.attributes.remove('target');
    anchor.attributes.remove('download');
    final address = anchor.attributes['href'];
    if (address != null && !address.startsWith('#')) {
      final link = externalLink(address);
      if (link == null) {
        anchor.attributes.remove('href');
      } else {
        anchor.attributes['href'] = link.toString();
      }
    }
  }
  for (final element in document.querySelectorAll(
    'script, iframe, object, embed, base, link, meta[http-equiv]',
  )) {
    element.remove();
  }
  if (format != 'html') {
    for (final element in document.querySelectorAll('style')) {
      element.remove();
    }
    for (final element in document.querySelectorAll('[style], [class]')) {
      element.attributes.remove('style');
      element.attributes.remove('class');
    }
    if (title != null && title.isNotEmpty) {
      document.body!.nodes.insert(0, Element.tag('h1')..text = title);
    }
    document.head!.append(
      Element.tag('style')
        ..text =
            '''
      :root { color-scheme: ${dark ? 'dark' : 'light'}; }
      body { margin: 0; padding: 24px 22px 48px; font: 17px/1.85 sans-serif;
        color: ${dark ? '#e8e7e3' : '#272a30'}; background: ${dark ? '#181a1d' : '#fafaf8'}; }
      h1,h2,h3 { line-height: 1.4; margin: 1.3em 0 .6em; }
      h1 { font-size: 26px; } h2 { font-size: 22px; } h3 { font-size: 19px; }
      img,svg,video { max-width: 100%; height: auto; } a { color: #d66044; }
      pre { white-space: pre-wrap; overflow-wrap: anywhere; }
      code { font-size: .9em; } table { display:block; overflow-x:auto; border-collapse: collapse; }
      td,th { border: 1px solid #8886; padding: 8px 12px; }
      blockquote { border-left: 3px solid #e36547; padding-left: 16px; margin-left: 0; }
    ''',
    );
  }
  if (images != null) {
    for (final element in document.querySelectorAll('img')) {
      final source = element.attributes['src'] ?? '';
      final image = EmbeddedImage.fromDataUri(
        source,
        element.attributes['alt'] ?? '图片',
      );
      if (image == null) continue;
      final index = images.length;
      images.add(image);
      final address = 'dingdong-image://open/$index';
      if (element.parent?.localName == 'a') {
        element.parent!.attributes['href'] = address;
        element.parent!.attributes.remove('target');
      } else {
        final link = Element.tag('a')..attributes['href'] = address;
        element.replaceWith(link);
        link.append(element);
      }
    }
  }
  document.head!.nodes.insert(
    0,
    Element.tag('meta')
      ..attributes['http-equiv'] = 'Content-Security-Policy'
      ..attributes['content'] =
          "default-src 'none'; img-src data:; media-src data:; style-src 'unsafe-inline'; font-src data:; base-uri 'none'; form-action 'none'",
  );
  document.head!.append(Element.tag('meta')..attributes['charset'] = 'utf-8');
  if (document.querySelector('meta[name=viewport]') == null) {
    document.head!.append(
      Element.tag('meta')
        ..attributes.addAll({
          'name': 'viewport',
          'content': 'width=device-width, initial-scale=1',
        }),
    );
  }
  return document.outerHtml;
}

class EmbeddedImage {
  const EmbeddedImage(this.bytes, this.mime, this.label);
  final Uint8List bytes;
  final String mime;
  final String label;

  static EmbeddedImage? fromDataUri(String source, String label) {
    if (!source.startsWith('data:') || source.length > 1500000) return null;
    try {
      final data = Uri.parse(source).data;
      if (data == null ||
          ![
            'image/png',
            'image/jpeg',
            'image/webp',
            'image/gif',
          ].contains(data.mimeType)) {
        return null;
      }
      final bytes = data.contentAsBytes();
      if (bytes.isEmpty || bytes.length > 1000000) return null;
      return EmbeddedImage(bytes, data.mimeType, label);
    } on FormatException {
      return null;
    }
  }
}
