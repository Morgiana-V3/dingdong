import 'package:dingdong/ui/content_route.dart';
import 'package:dingdong/ui/prepared_reader_transition.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'reader paints behind inbox until ready, then slides from right',
    (tester) async {
      final ready = ValueNotifier(false);
      var taps = 0;
      const readerKey = ValueKey('reader');
      await tester.pumpWidget(
        MaterialApp(
          home: PreparedReaderTransition(
            ready: ready,
            background: const ColoredBox(color: Colors.blue),
            routeAnimation: const AlwaysStoppedAnimation(1),
            reducedMotion: false,
            child: Scaffold(
              key: readerKey,
              body: TextButton(
                onPressed: () => taps++,
                child: const Text('正文链接'),
              ),
            ),
          ),
        ),
      );
      final readerElement = tester.element(find.byKey(readerKey));
      expect(find.byKey(readerKey), findsOneWidget);
      await tester.tapAt(tester.getCenter(find.text('正文链接')));
      expect(taps, 0);
      await tester.pump(const Duration(milliseconds: 260));
      expect(find.text('正在打开帖子'), findsOneWidget);
      ready.value = true;
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(readerKey)).dx, 800);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getTopLeft(find.byKey(readerKey)).dx,
        inExclusiveRange(0, 800),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(readerKey)).dx, 0);
      expect(tester.element(find.byKey(readerKey)), same(readerElement));
      expect(find.text('正在打开帖子'), findsNothing);
      await tester.tap(find.text('正文链接'));
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
      ready.dispose();
    },
  );

  testWidgets('cancel preparation returns without revealing the reader', (
    tester,
  ) async {
    final ready = ValueNotifier(false);
    var returned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final route = readerRoute<void>(
                  context,
                  (_) => const Scaffold(body: Text('尚未绘制的正文')),
                  ready: ready,
                  background: const ColoredBox(color: Colors.blue),
                );
                await Navigator.of(context).push(route);
                await route.completed;
                returned = true;
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(find.text('尚未绘制的正文'), findsNothing);
    ready.value = true;
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    ready.dispose();
  });

  for (final reducedMotion in [false, true]) {
    testWidgets(
      'prepared reader preserves return result, reduced=$reducedMotion',
      (tester) async {
        final ready = ValueNotifier(false);
        String? returned;
        var removed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reducedMotion),
              child: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      final route = readerRoute<String>(
                        context,
                        (context) => Scaffold(
                          body: TextButton(
                            onPressed: () =>
                                Navigator.pop(context, 'deleted-id'),
                            child: const Text('关闭'),
                          ),
                        ),
                        ready: ready,
                        background: const ColoredBox(color: Colors.blue),
                      );
                      returned = await Navigator.of(context).push(route);
                      await route.completed;
                      removed = true;
                    },
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pump();
        ready.value = true;
        await tester.pump();
        if (reducedMotion) {
          expect(tester.getTopLeft(find.byType(Scaffold).last).dx, 0);
        }
        await tester.pumpAndSettle();
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        expect(returned, 'deleted-id');
        expect(removed, isTrue);
        await tester.pumpWidget(const SizedBox());
        ready.dispose();
      },
    );
  }
}
