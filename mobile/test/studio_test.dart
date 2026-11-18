import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dingdong/data/inbox_repository.dart';
import 'package:dingdong/features/studio/studio_page.dart';

Map<String, dynamic> fixture() => {
  'revision': 'revision-one',
  'tasks': [
    {
      'id': 'task',
      'name': '我的订阅',
      'pluginId': 'x-interests',
      'channelId': 'phone',
      'providerId': 'ai',
      'enabled': true,
      'onlyChanged': true,
      'schedule': {
        'type': 'daily',
        'times': ['09:00', '18:00'],
      },
      'config': {'interests': '编程工具', 'maxItems': 5},
    },
  ],
  'plugins': [
    {
      'id': 'x-interests',
      'name': 'X 兴趣',
      'fields': [
        {
          'key': 'interests',
          'label': '兴趣说明',
          'type': 'textarea',
          'required': true,
        },
        {'key': 'maxItems', 'label': '推送条数', 'type': 'number', 'default': 5},
      ],
    },
    {
      'id': digestPluginId,
      'name': '订阅汇总',
      'fields': [
        {
          'key': 'sourceTaskIds',
          'label': '内容源',
          'type': 'tasks',
          'required': true,
        },
      ],
    },
  ],
  'channels': [
    {'id': 'phone', 'name': '我的手机', 'kind': 'dingdong'},
  ],
  'providers': [
    {'id': 'ai', 'name': '共享 AI'},
  ],
  'running': [],
};

class StudioRepository extends InboxRepository {
  bool online = true;
  Map<String, dynamic>? submitted;
  Completer<Map<String, dynamic>>? completion;
  @override
  Future<Map<String, dynamic>> studio([Map<String, dynamic>? command]) async {
    if (command != null) {
      submitted = command;
      return completion!.future;
    }
    return {
      'online': online,
      'session': online ? 'studio-one' : '',
      'snapshot': online ? fixture() : null,
    };
  }
}

void main() {
  testWidgets('offline Studio explains setup and disables editing', (
    tester,
  ) async {
    final repository = StudioRepository()..online = false;
    await tester.pumpWidget(
      MaterialApp(home: StudioPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Studio 未连接'), findsOneWidget);
    expect(find.text('新增订阅'), findsNothing);
    expect(find.textContaining('开启手机管理'), findsOneWidget);
  });

  testWidgets('enable change uses revision and waits for actual confirmation', (
    tester,
  ) async {
    final repository = StudioRepository()..completion = Completer();
    await tester.pumpWidget(
      MaterialApp(home: StudioPage(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(repository.submitted, {
      'session': 'studio-one',
      'revision': 'revision-one',
      'action': 'setEnabled',
      'payload': {'id': 'task', 'enabled': false},
    });
    expect(find.text('Studio 已保存设置'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    final saved = fixture();
    (saved['tasks'] as List).first['enabled'] = false;
    repository.completion!.complete({
      'ok': true,
      'session': 'studio-one',
      'snapshot': saved,
    });
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, false);
    expect(find.text('Studio 已保存设置'), findsOneWidget);
  });

  testWidgets('conflicting edits preserve the draft and never show success', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? submitted;
    final snapshot = fixture();
    await tester.pumpWidget(
      MaterialApp(
        home: StudioTaskEditor(
          snapshot: snapshot,
          task: (snapshot['tasks'] as List).first as Map<String, dynamic>,
          save: (input) async {
            submitted = input;
            throw PlatformException(code: 'studio', message: '订阅设置已变化，请刷新后重试');
          },
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '兴趣说明'),
      'AI 与开源',
    );
    await tester.ensureVisible(find.text('保存到 Studio'));
    await tester.tap(find.text('保存到 Studio'));
    await tester.pumpAndSettle();
    expect(submitted?['config'], {'interests': 'AI 与开源', 'maxItems': '5'});
    expect(submitted?['schedule'], {
      'type': 'daily',
      'times': ['09:00', '18:00'],
    });
    expect(submitted?['providerId'], 'ai');
    expect(find.textContaining('订阅设置已变化'), findsOneWidget);
    expect(find.text('AI 与开源'), findsOneWidget);
    expect(find.text('Studio 已保存设置'), findsNothing);
  });
}
