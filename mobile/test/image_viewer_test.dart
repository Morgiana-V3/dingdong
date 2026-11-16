import 'dart:convert';
import 'package:dingdong/data/inbox_repository.dart';
import 'package:dingdong/features/reader/document.dart';
import 'package:dingdong/features/reader/image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('gallery swipes to the next image and saves that image', (
    tester,
  ) async {
    final images = [
      EmbeddedImage(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAIUlEQVR4nGP8z0AaYCJRPcOoBmIAE1GqkMCoBmIAyaEEAEAuAR9UPEsJAAAAAElFTkSuQmCC',
        ),
        'image/png',
        '第一张',
      ),
      EmbeddedImage(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAIAAACQkWg2AAAAI0lEQVR4nGNkYPjPQApgIkk1w6gG4gATkergYFQDMYDkUAIAPjABH26QQDYAAAAASUVORK5CYII=',
        ),
        'image/png',
        '第二张',
      ),
    ];
    Map? saved;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(InboxRepository.channel, (call) async {
          saved = call.arguments as Map;
          return true;
        });
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final context = tester.element(find.byType(Scaffold));
    await tester.runAsync(() async {
      for (final image in images) {
        await precacheImage(ImageViewer.imageProvider(image), context);
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ImageViewer(
          images: images,
          initialIndex: 0,
          repository: InboxRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('保存图片'));
    await tester.pumpAndSettle();
    expect(saved!['bytes'], images[1].bytes);
    expect(saved!['mime'], 'image/png');
    expect(find.text('图片已保存'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
