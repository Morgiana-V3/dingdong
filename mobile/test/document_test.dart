import 'package:dingdong/data/inbox_repository.dart';
import 'package:dingdong/features/reader/document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart';

void main() {
  test(
    'original HTML preserves CSS but removes scripts and refresh navigation',
    () {
      final result = parse(
        buildDocument(
          '<html><head><style>.report{color:red}</style>'
              '<meta http-equiv="refresh" content="0;url=https://example.com"></head>'
              '<body><div class="report" style="padding:20px">正文</div><script>alert(1)</script>'
              '<iframe src="https://example.com"></iframe></body></html>',
          'html',
          dark: false,
        ),
      );
      expect(result.querySelector('style')!.text, contains('color:red'));
      expect(
        result.querySelector('.report')!.attributes['style'],
        'padding:20px',
      );
      expect(
        result.querySelectorAll('script, iframe, meta[http-equiv=refresh]'),
        isEmpty,
      );
      expect(
        result
            .querySelector('meta[http-equiv=Content-Security-Policy]')!
            .attributes['content'],
        contains("default-src 'none'"),
      );
    },
  );

  test('text cannot inject HTML and Markdown retains table structure', () {
    final text = parse(buildDocument('<img src=x>', 'text', dark: false));
    expect(text.querySelectorAll('img'), isEmpty);
    expect(text.body!.text, contains('<img src=x>'));
    final table = parse(
      buildDocument('|a|b|\n|---|---|\n|1|2|', 'markdown', dark: true),
    );
    expect(table.querySelectorAll('td'), hasLength(2));
  });

  test('text titles scroll with content while HTML keeps its own heading', () {
    final text = parse(buildDocument('正文', 'text', title: '<标题>', dark: false));
    expect(text.body!.children.first.localName, 'h1');
    expect(text.querySelector('h1')!.text, '<标题>');
    expect(text.querySelectorAll('标题'), isEmpty);
    final rich = parse(
      buildDocument('<h1>作者标题</h1>', 'html', title: '消息标题', dark: false),
    );
    expect(rich.querySelectorAll('h1'), hasLength(1));
    expect(rich.body!.text, '作者标题');
  });

  test(
    'embedded images get local viewer links without enabling scripts or remote images',
    () {
      final images = <EmbeddedImage>[];
      final result = parse(
        buildDocument(
          '<style>img{width:100%}</style><a href="https://example.com"><img src="data:image/png;base64,aGVsbG8="></a><img src="https://example.com/image.jpg"><img src="data:image/jpeg;base64,aGVsbG8=">',
          'html',
          dark: false,
          images: images,
        ),
      );
      expect(images, hasLength(2));
      expect(
        result.querySelectorAll('a[href^="dingdong-image:"]'),
        hasLength(2),
      );
      expect(result.querySelector('script'), isNull);
      expect(result.querySelector('style')!.text, contains('width:100%'));
      expect(
        EmbeddedImage.fromDataUri('data:image/svg+xml,<svg/>', '图片'),
        isNull,
      );
      expect(
        EmbeddedImage.fromDataUri('data:image/png;base64,????', '图片'),
        isNull,
      );
    },
  );

  test('server addresses support IP ports and reject embedded credentials', () {
    expect(normalizeEndpoint('192.0.2.10:8080/'), 'http://192.0.2.10:8080');
    expect(normalizeEndpoint('http：、、192。0。2。10'), 'http://192.0.2.10');
    expect(
      normalizeEndpoint('https：／／push．example．com／'),
      'https://push.example.com',
    );
    expect(
      normalizeEndpoint('[2001:db8::1]:8080'),
      'http://[2001:db8::1]:8080',
    );
    expect(
      normalizeEndpoint('https://push.example.com'),
      'https://push.example.com',
    );
    for (final invalid in [
      '',
      'ftp://host',
      'http://user:pass@host',
      'http://host/path',
      'http://host?key=secret',
      'http://host name',
      'http://example，com',
    ]) {
      expect(() => normalizeEndpoint(invalid), throwsFormatException);
    }
  });
}
