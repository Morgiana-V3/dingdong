import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dingdong/data/inbox_repository.dart';
import 'package:dingdong/features/accounts/platform_accounts_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'account shows nickname and opens operations only after tapping the row',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PlatformAccountsPage(
            requiredAccounts: [
              {
                'id': 'custom-site',
                'name': '某网站',
                'type': 'web-cookie',
                'loginUrl': 'https://example.com/login',
                'cookieDomains': ['https://example.com'],
                'requiredCookies': ['sid'],
                'state': 'ready',
                'account': {'id': '42', 'name': '测试昵称'},
                'tasks': [],
              },
            ],
          ),
        ),
      );
      expect(find.text('测试昵称'), findsOneWidget);
      expect(find.text('重新登录'), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      await tester.tap(find.text('测试昵称'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('重新登录'), findsOneWidget);
      expect(find.text('退出账号'), findsOneWidget);
    },
  );
  testWidgets(
    'no standalone login action is shown before an enabled task needs an account',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PlatformAccountsPage()));
      await tester.pumpAndSettle();
      expect(find.text('当前没有需要登录的任务'), findsOneWidget);
      expect(find.text('登录并启用任务'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    },
  );
  testWidgets(
    'required generic web-cookie account passes plugin auth metadata to native login',
    (tester) async {
      MethodCall? login;
      bool refreshed = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(InboxRepository.channel, (call) async {
            login = call;
            return '服务器已验证并保存凭据';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(InboxRepository.channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlatformAccountsPage(
            requiredAccounts: const [
              {
                'id': 'v2ex',
                'name': 'V2EX',
                'type': 'web-cookie',
                'loginUrl': 'https://www.v2ex.com/signin',
                'cookieDomains': ['https://www.v2ex.com'],
                'requiredCookies': ['A2'],
                'state': 'idle',
                'tasks': [
                  {'id': 'one', 'name': '热门主题日报'},
                ],
              },
            ],
            onChanged: () async {
              refreshed = true;
            },
          ),
        ),
      );
      await tester.tap(find.text('V2EX'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('登录并启用任务'));
      await tester.pumpAndSettle();
      expect(login?.method, 'platformLogin');
      expect(login?.arguments, {
        'authId': 'v2ex',
        'authName': 'V2EX',
        'loginUrl': 'https://www.v2ex.com/signin',
        'cookieDomains': ['https://www.v2ex.com'],
        'requiredCookies': ['A2'],
        'clearExisting': false,
      });
      expect(refreshed, isTrue);
      expect(find.text('热门主题日报'), findsOneWidget);
      expect(find.text('服务器已验证并保存凭据'), findsOneWidget);
    },
  );
}
