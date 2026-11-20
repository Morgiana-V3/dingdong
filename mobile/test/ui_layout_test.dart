import 'dart:convert';
import 'package:dingdong/data/message_preview.dart';
import 'fixture_cover.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dingdong/data/inbox_repository.dart';
import 'package:dingdong/features/accounts/platform_accounts_page.dart';
import 'package:dingdong/features/inbox/inbox_page.dart';
import 'package:dingdong/features/settings/settings_page.dart';
import 'package:dingdong/features/subscriptions/subscription_editor.dart';
import 'package:dingdong/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'preview_fonts.dart';
import 'package:flutter_test/flutter_test.dart';

// Fictional data only. Optional previews stay outside the repository.
class PreviewRepository extends InboxRepository {
  @override
  Future<Map<String, dynamic>> settings() async => {
    'endpoint': 'https://relay.example',
    'status': '已连接',
    'hasToken': true,
    'enabled': true,
    'notifications': true,
  };

  final chart = base64Decode(chartPng);

  @override
  Future<MessagePreview?> preview(InboxMessage message) async =>
      switch (message.id) {
        '运行监控' => MessagePreview(
          headline: '服务运行正常',
          description: '所有服务均已恢复，暂无需要处理的告警。',
          cover: chart,
        ),
        '科技资讯' => const MessagePreview(
          headline: '本周值得关注的开源项目',
          description: '整理了三个新项目，以及它们的使用场景。',
        ),
        _ => null,
      };

  @override
  Future<Set<String>> mutedSources() async => {};

  @override
  Future<List<InboxMessage>> messages({
    String query = '',
    DateTime? after,
    DateTime? before,
  }) async => [
    for (final entry in [
      ('工作日报', '今日任务已完成', '构建与测试全部通过，查看今天的运行结果。', false, true),
      ('科技资讯', '本周值得关注的开源项目', '整理了三个新项目，以及它们的使用场景。', false, false),
      ('运行监控', '服务运行正常', '所有服务均已恢复，暂无需要处理的告警。', true, false),
    ])
      InboxMessage.fromMap({
        'id': entry.$1,
        'source': entry.$1,
        'title': entry.$1 == '工作日报' ? entry.$2 : '每日订阅',
        'summary': entry.$3,
        'format': entry.$1 == '工作日报' ? 'text' : 'html',
        'createdAt': DateTime(2026, 11, 18, 9, 30).millisecondsSinceEpoch,
        'read': entry.$4,
        'starred': entry.$5,
      }),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final (width, scale) in [(390.0, 1.0), (360.0, 1.8), (960.0, 1.0)]) {
    testWidgets(
      'primary screens remain readable at width $width and text scale $scale',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final output = Platform.environment['DINGDONG_LAYOUT_OUTPUT'];
        if (output != null && Platform.isWindows) {
          await tester.runAsync(loadPreviewFonts);
        }
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              InboxRepository.channel,
              (_) async => null,
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(InboxRepository.channel, null),
        );
        final repository = PreviewRepository();
        final settings = await repository.settings();
        final pages = <String, Widget>{
          'inbox': InboxPage(repository: repository),
          'settings': Scaffold(
            appBar: AppBar(title: const Text('设置')),
            body: SettingsPage(
              repository: repository,
              settings: settings,
              onChanged: () {},
            ),
          ),
          'connection': ServerConnectionPage(
            repository: repository,
            settings: settings,
          ),
          'editor': SubscriptionEditor(
            snapshot: const {
              'plugins': [
                {
                  'id': 'preview',
                  'name': '兴趣订阅',
                  'description': '按兴趣整理公开内容',
                  'fields': [
                    {
                      'key': 'interests',
                      'type': 'textarea',
                      'label': '兴趣规则',
                      'required': true,
                      'help': '填写你关注的主题，例如开源软件、摄影。',
                    },
                  ],
                },
              ],
              'providers': [],
            },
            save: (_) async {},
          ),
          'accounts': const PlatformAccountsPage(
            requiredAccounts: [
              {
                'id': 'bilibili',
                'name': '哔哩哔哩',
                'state': 'idle',
                'tasks': [
                  {'id': 'preview', 'name': '每日视频精选'},
                ],
              },
            ],
          ),
        };
        for (final page in pages.entries) {
          final boundaryKey = GlobalKey();
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundaryKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: inboxTheme(
                  scale == 1 ? Brightness.light : Brightness.dark,
                ),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: page.value,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: page.key);
          if (page.key == 'inbox') {
            await tester.runAsync(
              () => precacheImage(
                MemoryImage(repository.chart),
                tester.element(find.byType(InboxPage)),
              ),
            );
            await tester.pumpAndSettle();
            expect(
              tester.widget<RawImage>(find.byType(RawImage)).image,
              isNotNull,
            );
            final cover = find.byType(Image);
            expect(cover, findsOneWidget);
            final photo = tester.getRect(cover);
            final cardRect = tester.getRect(
              find.widgetWithText(Card, '服务运行正常'),
            );
            final timestamp = tester.getRect(
              find.descendant(
                of: find.widgetWithText(Card, '服务运行正常'),
                matching: find.text('09:30'),
              ),
            );
            expect(photo.top, greaterThan(cardRect.top));
            expect(photo.height / photo.width, closeTo(.72, .01));
            expect(timestamp.top, greaterThan(photo.bottom));
            expect(timestamp.right, closeTo(photo.right, .5));
            final plainCard = find.widgetWithText(Card, '今日任务已完成');
            final plainTime = tester.getRect(
              find.descendant(of: plainCard, matching: find.text('09:30')),
            );
            expect(plainTime.right, closeTo(timestamp.right, .5));
            expect(find.textContaining(RegExp(r'共\s*\d+\s*条')), findsNothing);
            expect(find.text('·'), findsNothing);

            expect(
              tester.getRect(find.text('服务运行正常')).right,
              lessThan(photo.left),
            );
            expect(
              tester
                  .renderObject<RenderBox>(find.text('今日任务已完成'))
                  .constraints
                  .maxWidth,
              greaterThan(
                tester
                    .renderObject<RenderBox>(find.text('服务运行正常'))
                    .constraints
                    .maxWidth,
              ),
            );
          }
          if (width >= 900 && page.key == 'connection') {
            final field = tester.getRect(
              find.widgetWithText(TextFormField, '服务器地址'),
            );
            expect(field.width, lessThanOrEqualTo(640));
            expect(field.center.dx, closeTo(width / 2, 1));
          }
          if (output != null) {
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$output/${page.key}${width >= 900 ? '-wide' : ''}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          if (page.key == 'inbox') {
            expect(find.text('每日订阅'), findsNWidgets(2));
            final card = find.widgetWithText(Card, '本周值得关注的开源项目');
            final normal = tester.widget<Card>(card);
            await tester.longPress(find.text('本周值得关注的开源项目'));
            await tester.pumpAndSettle();
            final selected = tester.widget<Card>(card);
            expect(selected.color, normal.color);
            expect(
              (selected.shape! as RoundedRectangleBorder).side,
              isNot((normal.shape! as RoundedRectangleBorder).side),
            );
            expect(find.byIcon(Icons.check_circle), findsOneWidget);
          }
          if (page.key == 'connection') {
            tester.view.viewInsets = const FakeViewPadding(bottom: 280);
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text('保存并连接'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            tester.view.resetViewInsets();
          }
          if (page.key == 'editor') {
            expect(find.text('填写你关注的主题，例如开源软件、摄影。'), findsNothing);
            await tester.ensureVisible(find.byTooltip('兴趣规则说明'));
            await tester.tap(find.byTooltip('兴趣规则说明'));
            await tester.pumpAndSettle();
            expect(find.text('填写你关注的主题，例如开源软件、摄影。'), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }
}
