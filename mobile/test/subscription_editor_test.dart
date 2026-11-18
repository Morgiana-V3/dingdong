import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dingdong/features/studio/subscription_editor.dart';
import 'package:dingdong/ui/theme.dart';
import 'package:dingdong/features/studio/source_selection.dart';
import 'package:dingdong/ui/selection_sheet.dart';

void main() {
  testWidgets(
    'digest creates a plugin source and preserves its draft and revision',
    (tester) async {
      final snapshot = <String, dynamic>{
        'revision': 7,
        'plugins': [
          {
            'id': 'minipush-digest',
            'name': '统一推送',
            'studio': true,
            'fields': [
              {'key': 'sourceTaskIds', 'label': '内容源', 'type': 'tasks'},
            ],
          },
          {
            'id': 'x-interests',
            'name': 'X 兴趣精选',
            'studio': true,
            'fields': [
              {
                'key': 'interests',
                'label': '兴趣',
                'type': 'textarea',
                'required': true,
              },
            ],
          },
        ],
        'tasks': <Map<String, dynamic>>[],
        'providers': [],
        'channels': [],
      };
      Map<String, dynamic>? saved, source;
      await tester.pumpWidget(
        MaterialApp(
          theme: inboxTheme(Brightness.light),
          home: Builder(
            builder: (context) => TextButton(
              child: const Text('打开'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SubscriptionEditor(
                    snapshot: snapshot,
                    initialPluginId: 'minipush-digest',
                    save: (values) async {
                      saved = values;
                    },
                    saveSource: (values) async {
                      source = values;
                      return {
                        ...snapshot,
                        'revision': 8,
                        'tasks': [
                          {...values, 'id': 'new-source'},
                        ],
                      };
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '任务名称'),
        '我的汇总草稿',
      );
      Future<void> reveal(Finder target) async {
        final list = find
            .descendant(
              of: find.byKey(const ValueKey('subscription-form-list')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(target, 180, scrollable: list);
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(target), alignment: .5);
        await tester.pumpAndSettle();
      }

      await reveal(find.text('添加内容源'));
      await tester.tap(find.text('添加内容源'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('统一推送'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('X 兴趣精选'));
      await tester.pumpAndSettle();
      expect(find.text('配置内容源'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, '任务名称'),
        'X 内容源',
      );
      await reveal(find.byKey(const ValueKey('x-interests/interests')));
      await tester.enterText(
        find.byKey(const ValueKey('x-interests/interests')),
        '开源模型',
      );
      await reveal(find.text('保存任务'));
      await tester.tap(find.text('保存任务'));
      await tester.pumpAndSettle();
      expect(source?['enabled'], false);
      expect(source?['schedule'], {'type': 'manual'});
      expect(source?['revision'], 7);
      expect(find.text('X 内容源'), findsOneWidget);
      await reveal(find.text('保存任务'));
      await tester.tap(find.text('保存任务'));
      await tester.pumpAndSettle();
      expect(saved?['name'], '我的汇总草稿');
      expect(saved?['revision'], 8);
      expect(saved?['config'], {'sourceTaskIds': 'new-source'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source sheet supports legacy, blocks occupied sources and cancels without editing',
    (tester) async {
      final initial = <String>{};
      Set<String>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('选择'),
                onPressed: () async {
                  result = await selectDigestSources(
                    context: context,
                    selected: initial,
                    plugins: [
                      {'id': 'legacy', 'name': '旧版 B 站', 'digestSource': true},
                      {'id': 'x', 'name': 'X', 'studio': true},
                    ],
                    tasks: [
                      {'id': 'b', 'name': 'B 站来源', 'pluginId': 'legacy'},
                      {'id': 'x', 'name': 'X 来源', 'pluginId': 'x'},
                      {
                        'id': 'owner',
                        'name': '另一个汇总',
                        'pluginId': 'minipush-digest',
                        'enabled': true,
                        'config': {'sourceTaskIds': 'x'},
                      },
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'X 来源'),
            )
            .onChanged,
        isNull,
      );
      await tester.tap(find.text('B 站来源'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭面板'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(initial, isEmpty);
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B 站来源'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成（1/8）'));
      await tester.pumpAndSettle();
      expect(result, {'b'});
      expect(initial, isEmpty);
    },
  );

  testWidgets(
    'selection sheet scrolls with large text and returns the chosen value',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('选择'),
                onPressed: () async {
                  result = await showChoiceSheet(
                    context: context,
                    title: '选择来源插件',
                    choices: [
                      for (var i = 0; i < 12; i++)
                        SheetChoice(
                          value: '$i',
                          label: '插件 $i',
                          description: '这是插件的用途说明',
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('插件 11'),
        220,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('插件 11'));
      await tester.pumpAndSettle();
      expect(result, '11');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Studio forum, text, number and boolean fields save a complete task',
    (tester) async {
      Map<String, dynamic>? saved;
      final snapshot = <String, dynamic>{
        'plugins': [
          {
            'id': 'tieba-subscription',
            'name': '贴吧兴趣精选',
            'studio': true,
            'description': '按兴趣筛选公开帖子',
            'capabilities': ['tieba.read', 'ai.tools'],
            'fields': [
              {'key': 'globalFilter', 'label': '总过滤说明', 'type': 'textarea'},
              {
                'key': 'forums',
                'label': '贴吧配置',
                'type': 'forums',
                'required': true,
                'default': [
                  {'name': '', 'filter': ''},
                ],
              },
              {
                'key': 'maxItems',
                'label': '最多条数',
                'type': 'number',
                'default': 3,
              },
              {
                'key': 'includeImages',
                'label': '附上配图',
                'type': 'boolean',
                'default': true,
              },
            ],
          },
        ],
        'providers': [
          {'id': 'fixture', 'name': '测试模型'},
        ],
        'channels': [
          {'id': 'current-relay', 'name': '当前叮咚收件箱'},
        ],
        'tasks': [],
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: inboxTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => SubscriptionEditor(
                      snapshot: snapshot,
                      save: (value) async {
                        saved = value;
                      },
                    ),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '任务名称'),
        '动画精选',
      );
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('subscription-form-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      Future<void> scrollTo(Finder target) async {
        await tester.scrollUntilVisible(target, 200, scrollable: scrollable);
        await tester.pumpAndSettle();
      }

      await scrollTo(
        find.byKey(const ValueKey('tieba-subscription/globalFilter')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('tieba-subscription/globalFilter')),
        '动画讨论，排除广告',
      );
      await scrollTo(find.widgetWithText(TextFormField, '吧名'));
      await tester.enterText(find.widgetWithText(TextFormField, '吧名'), '动画');
      await scrollTo(find.byKey(const ValueKey('tieba-subscription/maxItems')));
      await tester.enterText(
        find.byKey(const ValueKey('tieba-subscription/maxItems')),
        '2',
      );
      await scrollTo(find.text('保存任务'));
      await tester.tap(find.text('保存任务'));
      await tester.pumpAndSettle();
      expect(saved?['pluginId'], 'tieba-subscription');
      expect(saved?['schedule'], {'type': 'manual'});
      expect(saved?['config'], {
        'globalFilter': '动画讨论，排除广告',
        'forums': [
          {'name': '动画', 'filter': ''},
        ],
        'maxItems': 2,
        'includeImages': true,
      });
      expect(tester.takeException(), isNull);
    },
  );
}
