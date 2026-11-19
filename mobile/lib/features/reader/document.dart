import 'dart:convert';
import 'dart:typed_data';
import 'package:html/parser.dart' as html;
import 'package:html/dom.dart';
import 'package:markdown/markdown.dart' as markdown;
import 'external_link.dart';

Document parseMessageDocument(String content, String format) {
  var source = content;
  if (format == 'markdown') {
    source = markdown.markdownToHtml(
      content,
      extensionSet: markdown.ExtensionSet.gitHubFlavored,
    );
  } else if (format == 'text') {
    source = '<pre>${const HtmlEscape().convert(content)}</pre>';
  }
  return html.parse(source);
}

void _preparePostCards(Document document) {
  final articles = document.querySelectorAll('main > article.post');
  final scopes = articles.isEmpty
      ? [document.querySelector('main') ?? document.body!]
      : articles;
  var nextId = 0;
  for (final card in scopes) {
    final spans = card.querySelectorAll('span[data-dingdong-original]');
    if (spans.isEmpty) continue;
    var id = 'dingdong-language-${nextId++}';
    while (document.getElementById(id) != null) {
      id = 'dingdong-language-${nextId++}';
    }
    final header =
        card.children
            .where((e) => e.classes.contains('post-header'))
            .firstOrNull ??
        (Element.tag('header')..classes.add('post-header'));
    if (header.parent == null) card.nodes.insert(0, header);
    final bar =
        header.querySelector('.origin') ??
        (Element.tag('div')..classes.add('origin'));
    if (bar.parent == null) header.append(bar);
    header.classes.add('dd-language-header');
    // A native checkbox scoped to this card also works in a script-free WebView.
    card.nodes.insert(
      0,
      Element.tag('input')
        ..id = id
        ..classes.add('dd-language')
        ..attributes.addAll({'type': 'checkbox', 'aria-label': '显示本帖原文'}),
    );
    header.append(
      Element.tag('label')
        ..attributes['for'] = id
        ..classes.addAll(['platform', 'dd-language-label'])
        ..append(
          Element.tag('span')
            ..classes.add('dd-translation-view')
            ..text = '源',
        )
        ..append(
          Element.tag('span')
            ..classes.add('dd-original-view')
            ..text = '译',
        ),
    );
    for (final span in spans) {
      final original = span.attributes.remove('data-dingdong-original')!;
      final translated = span.text;
      span.nodes.clear();
      span.append(
        Element.tag('span')
          ..classes.add('dd-translation-view')
          ..text = translated,
      );
      span.append(
        Element.tag('span')
          ..classes.add('dd-original-view')
          ..text = original,
      );
    }
  }
  if (nextId == 0 &&
      document.querySelector('.post-content .quote > .more') == null) {
    return;
  }
  document.head!.append(
    Element.tag('style')
      ..text = '''
    .dd-language { position:absolute; width:1px; height:1px; clip-path:inset(50%); overflow:hidden; }
    .dd-language-header { display:grid; grid-template-columns:minmax(0,1fr) auto;
      align-items:center; gap:12px; padding-block-start:17px; }
    .dd-language-header .origin { padding-inline-end:0; }
    .dd-language-label { position:relative; min-width:36px; margin-inline-end:20px; padding-inline:8px;
      line-height:1.5; text-align:center; transform:none; cursor:pointer;
      -webkit-tap-highlight-color:transparent; }
    .dd-language-label::after { content:''; position:absolute; inset:-5px; }
    .dd-original-view, .dd-language:checked ~ * .dd-translation-view { display:none; }
    .dd-language:checked ~ * .dd-original-view { display:inline; }
    .dd-language:focus-visible ~ header .dd-language-label { outline:2px solid currentColor; outline-offset:2px; }
    .post-content .quote > details.more { margin-block-end:12px; }
    .post-content .quote > details.more .full-text > p:last-child { margin-bottom:0; }
  ''',
  );
}

String buildDocument(
  String content,
  String format, {
  String? title,
  List<EmbeddedImage>? images,
  required bool dark,
}) {
  final document = parseMessageDocument(content, format);
  if (format == 'html') _preparePostCards(document);
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
