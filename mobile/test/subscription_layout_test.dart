import 'dart:io';
import 'dart:ui' as ui;
import 'package:dingdong/data/inbox_repository.dart';
import 'package:dingdong/features/studio/subscription_management_page.dart';
import 'package:dingdong/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'preview_fonts.dart';
import 'package:flutter_test/flutter_test.dart';

class LayoutRepository extends InboxRepository {
  @override
  Future<Map<String, dynamic>> settings() async => {
    'endpoint': 'https://relay.example',
    'status': '已连接',
  };

  @override
  Future<Map<String, dynamic>> subscriptions([
    Map<String, dynamic>? command,
  ]) async => {
    'revision': 1,
    'endpoint': 'https://relay.example',
    'plugins': [
      {'id': 'fixture', 'name': '兴趣订阅', 'fields': []},
    ],
    'tasks': [
      for (var i = 0; i < 4; i++)
        {
          'id': 'task-$i',
          'name': ['每日汇总', '科技资讯', '开源项目', '影像与设计'][i],
          'pluginId': 'fixture',
          'enabled': i != 3,
          'state': ['active', 'needs_ai', 'grouped', 'paused'][i],
          'schedule': {
            'type': 'daily',
            'times': ['09:00'],
          },
        },
    ],
    'accounts': [],
    'providers': [],
  };
}

void main() {
  for (final scale in [1.0, 1.8]) {
    testWidgets(
      'four compact tasks fit a small screen and scale accessibly: $scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final output = Platform.environment['DINGDONG_LAYOUT_OUTPUT'];
        if (output != null) {
          await tester.runAsync(loadPreviewFonts);
        }
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: inboxTheme(scale == 1 ? Brightness.light : Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundaryKey,
              child: SubscriptionManagementPage(repository: LayoutRepository()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (scale == 1) {
          final card = tester.getRect(
            find.byKey(const ValueKey('task-card/task-3')),
          );
          expect(card.bottom, lessThanOrEqualTo(740));
          expect(card.height, lessThanOrEqualTo(140));
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
              '$output/tasks-$scale.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.byTooltip('任务操作 · 每日汇总'));
        await tester.pumpAndSettle();
        expect(find.text('编辑'), findsOneWidget);
        expect(find.text('删除'), findsOneWidget);
        expect(find.text('执行记录'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
