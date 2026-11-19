import 'package:dingdong/data/message_preview.dart';
import 'package:dingdong/data/inbox_repository.dart';
import 'package:dingdong/features/inbox/message_tile.dart';
import 'package:dingdong/features/reader/document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fixture_cover.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const image = 'data:image/png;base64,$chartPng';
  const bilingual =
      '<html><head>'
      '<meta property="og:title" content="新版已发布">'
      '<meta property="og:description" content="修复了备份问题">'
      '<meta name="dingdong:original-title" content="New release">'
      '<meta name="dingdong:original-description" content="Fixes backups">'
      '<meta name="dingdong:task" content="更新订阅">'
      '</head><body><main><article class="post"><div class="post-content">'
      '<h2><a href="https://example.test/post"><span data-dingdong-original="New release">新版已发布</span></a></h2>'
      '<p><span data-dingdong-original="Fixes backups">修复了备份问题</span></p>'
      '</div></article></main></body></html>';

  test(
    'each bilingual post owns its own header control, including previously saved posts',
    () async {
      final preview = await messagePreview(bilingual, 'html');
      expect(preview.headline, '新版已发布');
      expect(preview.taskName, '更新订阅');
      final doc = parseMessageDocument(bilingual, 'html');
      final main = doc.querySelector('main')!;
      main.append(main.children.first.clone(true));
      main.append(
        parseMessageDocument(
          '<article class="post">中文帖子</article>',
          'html',
        ).body!.children.first,
      );
      final rendered = parseMessageDocument(
        buildDocument(doc.outerHtml, 'html', dark: false),
        'html',
      );
      final posts = rendered.querySelectorAll('article.post');
      final ids = <String>{};
      for (final post in posts.take(2)) {
        final toggle = post.querySelector('input[type=checkbox]')!;
        expect(ids.add(toggle.id), isTrue);
        final button = post.querySelector(
          '.post-header > label.platform.dd-language-label',
        )!;
        expect(button.attributes['for'], toggle.id);
        expect(button.querySelector('.dd-translation-view')?.text, '源');
        expect(button.querySelector('.dd-original-view')?.text, '译');
        expect(
          post.querySelector('h2 a .dd-original-view')?.text,
          'New release',
        );
        expect(post.querySelector('h2 a .dd-translation-view')?.text, '新版已发布');
        expect(
          post.querySelector('h2 a')?.attributes['href'],
          'https://example.test/post',
        );
      }
      expect(posts.last.querySelector('label'), isNull);
    },
  );
  testWidgets('inbox keeps the translated summary without language controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageTile(
            message: InboxMessage(
              id: 'fixture',
              title: '新版已发布',
              source: '订阅任务',
              summary: '修复了备份问题',
              excerpt: '收件箱里的原始摘录',
              format: 'html',
              createdAt: DateTime(2026, 11, 18),
              isRead: false,
              starred: false,
            ),
            preview: Future.value(
              const MessagePreview(
                headline: '新版已发布',
                description: '修复了备份问题',
                taskName: '更新订阅',
                hasTranslation: true,
              ),
            ),
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('修复了备份问题'), findsOneWidget);
    expect(find.text('源'), findsNothing);
    expect(find.text('译'), findsNothing);
  });
  test('task metadata stays separate from the post headline', () async {
    final preview = await messagePreview(
      '<html><head><meta name="dingdong:task" content="每日 &amp; 科技"></head>'
          '<body><main><article class="post"><div class="post-content">'
          '<h2>新款设备发布</h2><p>发布详情</p></div></article></main></body></html>',
      'html',
    );
    expect(preview.taskName, '每日 & 科技');
    expect(preview.headline, '新款设备发布');
    expect((await messagePreview('<p>普通消息</p>', 'html')).taskName, isEmpty);
  });
  testWidgets('task tag uses metadata and preserves legacy task labels', (
    tester,
  ) async {
    for (final hasMetadata in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageTile(
              message: InboxMessage(
                id: 'fixture',
                source: '订阅任务',
                title: hasMetadata ? '内容概括标题' : '每日科技',
                summary: '推送摘要',
                format: 'html',
                createdAt: DateTime(2026, 11, 18),
                isRead: false,
                starred: false,
              ),
              preview: Future.value(
                MessagePreview(
                  headline: '新款设备发布',
                  taskName: hasMetadata ? '每日科技' : '',
                ),
              ),
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('每日科技'), findsOneWidget);
      expect(find.text('新款设备发布'), findsOneWidget);
      expect(find.text('内容概括标题'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
  test(
    'digest shows the opening post, even if only a later post has a cover',
    () async {
      final preview = await messagePreview(
        '<main><article class="post x"><div class="post-content"><h2>第一篇</h2><div class="original"><p>要点一</p></div></div></article>'
            '<article class="post"><div class="post-content"><h2>第二篇</h2><img src="$image"></div></article></main>',
        'html',
      );
      expect(preview.headline, '第一篇');
      expect(preview.description, '要点一');
      expect(preview.cover, isNull);
      expect(
        (await messagePreview('<h2>普通报告</h2><p>内容</p>', 'html')).headline,
        isEmpty,
      );
    },
  );
  test(
    'HTML and Markdown yield real thumbnails and skip corrupt candidates',
    () async {
      expect(
        (await messagePreview(
          '<figure><img src="data:image/png;base64,aGVsbG8="></figure><img src="$image">',
          'html',
        )).cover,
        isNotEmpty,
      );
      expect(
        (await messagePreview('![趋势]($image)', 'markdown')).cover,
        isNotEmpty,
      );
    },
  );
  test(
    'decorations, external URLs, fenced samples and text do not become covers',
    () async {
      expect(
        (await messagePreview(
          '<img src="https://example.test/image.jpg"><span class="avatar"><img src="$image"></span>',
          'html',
        )).cover,
        isNull,
      );
      expect(
        (await messagePreview(
          '```html\n<img src="$image">\n```',
          'markdown',
        )).cover,
        isNull,
      );
      expect(
        (await messagePreview('<img src="$image">', 'text')).cover,
        isNull,
      );
    },
  );
}
