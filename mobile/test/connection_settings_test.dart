import 'package:dingdong/data/inbox_repository.dart';
import 'package:dingdong/features/settings/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class ConnectionRepository extends InboxRepository {
  String? savedEndpoint;
  String? savedToken;
  bool? savedDirect;

  @override
  Future<void> connect(
    String endpoint,
    String token, {
    bool? directConnection,
  }) async {
    savedEndpoint = endpoint;
    savedToken = token;
    savedDirect = directConnection;
  }
}

void main() {
  test(
    'HTTPS upgrade never reuses credentials across hosts, custom ports or downgrades',
    () {
      expect(
        isHttpsUpgrade('http://relay.example', 'https://relay.example'),
        isTrue,
      );
      for (final next in [
        'https://other.example',
        'https://relay.example:8443',
        'https://relay.example/path',
        'https://user@relay.example',
        'https://relay.example?query=1',
        'http://relay.example',
      ]) {
        expect(isHttpsUpgrade('http://relay.example', next), isFalse);
      }
      expect(
        isHttpsUpgrade('https://relay.example', 'http://relay.example'),
        isFalse,
      );
      expect(
        isHttpsUpgrade('http://relay.example:8080', 'https://relay.example'),
        isFalse,
      );
    },
  );

  testWidgets(
    'HTTPS upgrade preserves the saved secret without revealing or entering it',
    (tester) async {
      final repository = ConnectionRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsPage(
              connectionOnly: true,
              repository: repository,
              settings: const {
                'endpoint': 'http://relay.example',
                'hasToken': true,
              },
              onChanged: () {},
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('改用 HTTPS 加密连接'));
      await tester.tap(find.text('改用 HTTPS 加密连接'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'https://relay.example',
      );
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).at(1))
            .controller!
            .text,
        isEmpty,
      );
      await tester.ensureVisible(find.text('保存并连接'));
      await tester.tap(find.text('保存并连接'));
      await tester.pumpAndSettle();
      expect(repository.savedEndpoint, 'https://relay.example');
      expect(repository.savedToken, '');
      expect(repository.savedDirect, false);
    },
  );
  testWidgets(
    'saved credential eye opens native secure viewer without filling the form',
    (tester) async {
      MethodCall? observed;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(InboxRepository.channel, (call) async {
            observed = call;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(InboxRepository.channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsPage(
              connectionOnly: true,
              repository: ConnectionRepository(),
              settings: const {
                'endpoint': 'https://relay.example',
                'hasToken': true,
              },
              onChanged: () {},
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.byTooltip('显示密钥'));
      await tester.tap(find.byTooltip('显示密钥'));
      await tester.pumpAndSettle();
      expect(observed?.method, 'showSavedToken');
      final input = tester.widget<TextFormField>(
        find.byType(TextFormField).at(1),
      );
      expect(input.controller!.text, isEmpty);
    },
  );
  testWidgets(
    'direct relay mode is opt-in and preserves the saved credential',
    (tester) async {
      final repository = ConnectionRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsPage(
              connectionOnly: true,
              repository: repository,
              settings: const {
                'endpoint': 'https://relay.example',
                'hasToken': true,
                'directConnection': false,
              },
              onChanged: () {},
            ),
          ),
        ),
      );
      final toggle = find.byType(SwitchListTile);
      expect(toggle, findsNothing);
      await tester.ensureVisible(find.text('网络与诊断'));
      await tester.tap(find.text('网络与诊断'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(toggle);
      expect(tester.widget<SwitchListTile>(toggle).value, false);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(repository.savedDirect, isNull);
      await tester.ensureVisible(find.text('保存并连接'));
      await tester.tap(find.text('保存并连接'));
      await tester.pumpAndSettle();
      expect(repository.savedEndpoint, 'https://relay.example');
      expect(repository.savedToken, '');
      expect(repository.savedDirect, true);
    },
  );
}
