import 'package:dingdong/data/inbox_repository.dart';
import 'package:dingdong/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var messages = <Map<String, Object>>[];
  setUp(() {
    messages = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(InboxRepository.channel, (call) async {
          final arguments = call.arguments as Map? ?? {};
          switch (call.method) {
            case 'list':
              final query = arguments['query'] as String? ?? '';
              return messages
                  .where(
                    (message) =>
                        message['deleted'] != true &&
                        '${message['title']} ${message['summary']} ${message['source']} ${message['content']}'
                            .contains(query),
                  )
                  .toList();
            case 'batch':
              final ids = arguments['ids'] as List;
              for (final message in messages.where(
                (message) => ids.contains(message['id']),
              )) {
                switch (arguments['action']) {
                  case 'read':
                    message['read'] = arguments['value'] as bool;
                  case 'starred':
                    message['starred'] = arguments['value'] as bool;
                  case 'delete':
                    message['deleted'] = true;
                  case 'restore':
                    message['deleted'] = false;
                }
              }
              return ids.length;
            case 'muted':
              return <String>[];
            case 'settings':
              return {'endpoint': '', 'enabled': false, 'status': '未连接'};
            default:
              return null;
          }
        });
  });

  testWidgets(
    'empty inbox and settings remain usable with large text and keyboard',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(const DingdongApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
      await tester.tap(find.byTooltip('打开菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('long messages fit narrow screens with enlarged text', (
    tester,
  ) async {
    messages = [
      {
        'id': 'layout-message',
        'source': '来源' * 32,
        'title': '长标题' * 53,
        'summary': '长摘要' * 160,
        'format': 'markdown',
        'createdAt': 1794787200000,
        'read': false,
        'starred': true,
      },
    ];
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const DingdongApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('长标题' * 53), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('drawer filters messages and preserves search across pages', (
    tester,
  ) async {
    messages = [
      for (final entry in [('未读测试', false, false), ('收藏测试', true, true)])
        {
          'id': entry.$1,
          'source': '测试来源',
          'title': entry.$1,
          'summary': '摘要',
          'format': 'html',
          'createdAt': 1794787200000,
          'read': entry.$2,
          'starred': entry.$3,
        },
    ];
    await tester.pumpWidget(const DingdongApp());
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(2));
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.descendant(of: find.byType(Card), matching: find.byType(IconButton)),
      findsNothing,
    );

    Future<void> navigate(String label) async {
      await tester.tap(find.byTooltip('打开菜单'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(Drawer), matching: find.text(label)),
      );
      await tester.pumpAndSettle();
    }

    await navigate('未读');
    expect(find.text('未读测试'), findsOneWidget);
    expect(find.text('收藏测试'), findsNothing);
    await navigate('收藏');
    expect(find.text('收藏测试'), findsOneWidget);
    expect(find.text('未读测试'), findsNothing);
    await navigate('全部消息');
    await tester.enterText(find.byType(TextField), '收藏测试');
    await tester.pumpAndSettle();
    await navigate('来源');
    await navigate('全部消息');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '收藏测试',
    );
    expect(find.text('未读测试'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('body search and bulk deletion can be undone', (tester) async {
    messages = [
      {
        'id': 'one',
        'source': '来源',
        'title': '第一条',
        'summary': '',
        'content': '正文山谷',
        'format': 'text',
        'createdAt': 1794787200000,
        'read': false,
        'starred': false,
      },
      {
        'id': 'two',
        'source': '来源',
        'title': '第二条',
        'summary': '',
        'content': '正文海边',
        'format': 'text',
        'createdAt': 1794787200000,
        'read': false,
        'starred': false,
      },
    ];
    await tester.pumpWidget(const DingdongApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '山谷');
    await tester.pumpAndSettle();
    expect(find.text('第一条'), findsOneWidget);
    expect(find.text('第二条'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.longPress(find.text('第一条'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 条'), findsOneWidget);
    await tester.tap(find.byTooltip('全选当前列表'));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 条'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('第一条'), findsNothing);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('第一条'), findsOneWidget);
    expect(find.text('第二条'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
