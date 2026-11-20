import 'package:dingdong/features/accounts/platform_accounts_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dingdong/data/inbox_repository.dart';
import 'package:dingdong/ui/theme.dart';
import 'package:dingdong/features/subscriptions/subscription_management_page.dart';

class SubscriptionRepository extends InboxRepository {
  @override
  Future<Map<String, dynamic>> settings() async => {
    'endpoint': 'https://relay.example',
    'status': '已连接',
  };

  Map<String, dynamic>? task;
  Map<String, dynamic>? saved;
  int revision = 0;
  final plugin = <String, dynamic>{
    'id': 'server-plugin',
    'name': '服务器提供的插件',
    'description': '来自服务器的订阅能力',
    'accountId': 'bilibili',
    'accountName': '哔哩哔哩',
    'fields': <Map<String, dynamic>>[],
  };
  @override
  Future<Map<String, dynamic>> subscriptions([
    Map<String, dynamic>? command,
  ]) async {
    if (command != null) {
      saved = command;
      if (command['action'] == 'save') {
        task = {...command, 'id': 'task-1', 'state': 'needs_login'};
      }
      if (command['action'] == 'toggle') {
        task!['enabled'] = command['enabled'];
        task!['state'] = command['enabled'] == true ? 'needs_login' : 'paused';
      }
      revision++;
    }
    return {
      'revision': revision,
      'endpoint': 'https://relay.example',
      'plugins': [plugin],
      'tasks': [if (task != null) task],
      'accounts': [
        if (task?['enabled'] == true)
          {
            'id': 'my-site',
            'name': '自定义网站',
            'type': 'web-cookie',
            'loginUrl': 'https://example.com/login',
            'cookieDomains': ['https://example.com'],
            'requiredCookies': ['sid'],
            'state': 'idle',
            'tasks': [
              {'id': 'task-1', 'name': task!['name']},
            ],
          },
      ],
    };
  }
}

void main() {
  testWidgets(
    'subscription header owns actual receiver status and connection configuration',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: inboxTheme(Brightness.light),
          home: SubscriptionManagementPage(
            repository: SubscriptionRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('已连接'), findsOneWidget);
      await tester.tap(find.text('relay.example'));
      await tester.pumpAndSettle();
      expect(find.text('服务器连接'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '服务器地址'), findsOneWidget);
      expect(find.text('导出本地消息'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('AI blocked tasks open server configuration directly', (
    tester,
  ) async {
    final repository = SubscriptionRepository();
    repository.plugin['capabilities'] = ['ai.tools'];
    repository.task = {
      'id': 'task-1',
      'name': '等待模型的任务',
      'pluginId': 'server-plugin',
      'enabled': true,
      'state': 'needs_ai',
      'config': {},
      'schedule': {'type': 'manual'},
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: inboxTheme(Brightness.light),
        home: SubscriptionManagementPage(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('去配置 AI'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('subscription-task-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('去配置 AI')),
      alignment: .5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('去配置 AI'));
    await tester.pumpAndSettle();
    expect(find.text('服务器配置'), findsOneWidget);
    expect(find.text('任务关联'), findsOneWidget);
    expect(find.text('添加 AI 配置'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'server plugin -> enabled task -> required account; pausing removes login requirement',
    (tester) async {
      final repository = SubscriptionRepository();
      await tester.pumpWidget(
        MaterialApp(
          theme: inboxTheme(Brightness.light),
          home: SubscriptionManagementPage(repository: repository),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('服务器提供的插件'), findsNothing);
      expect(find.text('我的任务'), findsOneWidget);
      await tester.tap(find.text('所需账号'));
      await tester.pumpAndSettle();
      expect(find.text('当前没有需要登录的任务'), findsOneWidget);
      await tester.tap(find.text('订阅任务'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加任务'));
      await tester.pumpAndSettle();
      expect(find.text('服务器提供的插件'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, '任务名称'),
        '测试任务',
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('保存任务'),
        250,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('subscription-form-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('保存任务'));
      await tester.pumpAndSettle();
      expect(repository.saved?['pluginId'], 'server-plugin');
      expect(repository.saved?['enabled'], true);
      await tester.scrollUntilVisible(
        find.text('去登录'),
        220,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('subscription-task-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('去登录'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(PlatformAccountsPage),
          matching: find.text('测试任务'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('自定义网站'));
      await tester.pumpAndSettle();
      expect(find.text('登录并启用任务'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭面板'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('订阅任务'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('所需账号'));
      await tester.pumpAndSettle();
      expect(find.text('当前没有需要登录的任务'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
