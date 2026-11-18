import 'package:dingdong/features/studio/subscription_providers.dart';
import 'package:dingdong/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'vendor preset and live model search save with only a typed API key',
    (tester) async {
      Map<String, dynamic>? query;
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: inboxTheme(Brightness.light),
          home: ServerConfigurationPage(
            load: () => {
              'revision': 2,
              'providers': [],
              'tasks': [],
              'plugins': [],
            },
            models: (provider) async {
              query = provider;
              return ['fixture-large', 'fixture-small'];
            },
            save: (values) async {
              saved = values;
            },
          ),
        ),
      );
      await tester.tap(find.text('添加 AI 配置'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'API Key'),
        'fictional-key',
      );
      await tester.ensureVisible(find.text('读取并选择模型'));
      await tester.tap(find.text('读取并选择模型'));
      await tester.pumpAndSettle();
      expect(query?['baseUrl'], 'https://api.openai.com/v1');
      expect(query?['key'], 'fictional-key');
      await tester.enterText(find.widgetWithText(TextField, '搜索模型'), 'small');
      await tester.pumpAndSettle();
      expect(find.text('fixture-large'), findsNothing);
      await tester.tap(find.text('fixture-small'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存配置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存配置'));
      await tester.pumpAndSettle();
      expect(
        (saved?['provider'] as Map?)?['baseUrl'],
        'https://api.openai.com/v1',
      );
      expect((saved?['provider'] as Map?)?['model'], 'fixture-small');
      expect((saved?['provider'] as Map?)?['name'], 'OpenAI');
      expect((saved?['provider'] as Map?)?['maxOutputTokens'], 8000);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'server configuration assigns AI while preserving task settings and reports conflicts',
    (tester) async {
      var conflict = true;
      Map<String, dynamic>? saved;
      final task = <String, dynamic>{
        'id': 'source',
        'name': '测试推特',
        'pluginId': 'x',
        'enabled': false,
        'onlyChanged': true,
        'providerId': '',
        'config': {'interests': '开源项目', 'useSearch': true},
        'schedule': {
          'type': 'daily',
          'times': ['09:00', '18:00'],
        },
      };
      final snapshot = <String, dynamic>{
        'revision': 10,
        'endpoint': 'https://relay.example',
        'providers': [
          {
            'id': 'model-1',
            'name': '我的模型',
            'model': 'fixture',
            'baseUrl': 'https://ai.example/v1',
          },
        ],
        'plugins': [
          {
            'id': 'x',
            'name': 'X 兴趣发现',
            'capabilities': ['ai.tools'],
          },
        ],
        'tasks': [task],
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: inboxTheme(Brightness.light),
          home: ServerConfigurationPage(
            load: () => snapshot,
            save: (values) async {
              saved = values;
              if (conflict) {
                throw PlatformException(
                  code: 'conflict',
                  message: '任务已变化，请刷新后重试',
                );
              }
              task['providerId'] = values['providerId'];
              snapshot['revision'] = 11;
            },
          ),
        ),
      );
      expect(find.text('服务器配置'), findsOneWidget);
      await tester.tap(find.text('任务关联'));
      await tester.pumpAndSettle();
      Future<void> choose() async {
        await tester.ensureVisible(find.text('选择 AI 配置'));
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(find.text('选择 AI 配置')),
          alignment: .5,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('选择 AI 配置'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        await tester.tap(find.text('我的模型').last);
        await tester.pumpAndSettle();
      }

      await choose();
      expect(task['providerId'], '');
      await tester.pumpAndSettle();
      expect(find.text('任务已变化，请刷新后重试'), findsOneWidget);
      conflict = false;
      await choose();
      expect(saved?['action'], 'save');
      expect(saved?['revision'], 10);
      expect(saved?['enabled'], false);
      expect(saved?['schedule'], task['schedule']);
      expect(saved?['config'], task['config']);
      expect(saved?['providerId'], 'model-1');
      expect(find.text('等待 AI 配置'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
