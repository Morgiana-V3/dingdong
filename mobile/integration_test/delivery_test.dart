import 'dart:convert';
import 'dart:io';
import 'package:dingdong/data/inbox_repository.dart';
import 'package:dingdong/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<Map<String, dynamic>> request(
  String url, {
  String? token,
  Map<String, dynamic>? body,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final outgoing = await client.openUrl(
      body == null ? 'GET' : 'POST',
      Uri.parse(url),
    );
    if (token != null) outgoing.headers.set('Authorization', 'Bearer $token');
    if (body != null) {
      outgoing.headers.contentType = ContentType.json;
      outgoing.write(jsonEncode(body));
    }
    final response = await outgoing.close();
    final value = await utf8.decoder.bind(response).join();
    if (response.statusCode >= 400) {
      throw StateError('Request failed: ${response.statusCode}');
    }
    return jsonDecode(value) as Map<String, dynamic>;
  } finally {
    client.close(force: true);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'server delivery, duplicate retry, offline catch-up and HTML reading',
    (tester) async {
      final config = await request('http://127.0.0.1:18679/config');
      final endpoint = config['endpoint'] as String;
      final sendToken = config['sendToken'] as String;
      final repository = InboxRepository();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      app.main();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('打开菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), endpoint);
      await tester.enterText(
        find.byType(TextFormField).at(1),
        config['readToken'] as String,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存并连接'));
      await tester.tap(find.text('保存并连接'));
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(seconds: 3));

      final payload = {
        'id': 'device-html-$stamp',
        'source': '排版验证',
        'title': 'HTML 报告 · 收发验证',
        'summary': '自定义配色、表格与离线阅读',
        'format': 'html',
        'content': config['html'],
      };
      await request('$endpoint/v1/messages', token: sendToken, body: payload);
      final duplicate = await request(
        '$endpoint/v1/messages',
        token: sendToken,
        body: payload,
      );
      expect(duplicate['duplicate'], true);

      Future<List<InboxMessage>> waitFor(String title) async {
        for (var attempt = 0; attempt < 30; attempt++) {
          await tester.pump(const Duration(seconds: 1));
          final messages = await repository.messages();
          if (messages.any((message) => message.title == title)) {
            return messages;
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        throw StateError('Message did not reach the phone');
      }

      final messages = await waitFor(payload['title'] as String);
      expect(
        messages.where((message) => message.id.endsWith('device-html-$stamp')),
        hasLength(1),
      );
      final message = messages.firstWhere(
        (message) => message.id.endsWith('device-html-$stamp'),
      );
      expect(await repository.content(message.id), contains('脚本生成的报告'));
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(
        (await request(
          '$endpoint/v1/messages/device-html-$stamp/status',
          token: sendToken,
        ))['status'],
        'received',
      );

      await repository.disconnect();
      await Future<void>.delayed(const Duration(seconds: 2));
      final offline = {
        'id': 'device-offline-$stamp',
        'source': '服务监控',
        'title': '离线补收 · 收发验证',
        'summary': '在手机暂停接收时发送，恢复连接后自动补收。',
        'format': 'text',
        'content': '离线补收测试已完成。',
      };
      expect(
        (await request(
          '$endpoint/v1/messages',
          token: sendToken,
          body: offline,
        ))['status'],
        'queued',
      );
      await repository.connect(endpoint, config['readToken'] as String);
      await waitFor(offline['title']!);

      await request('http://127.0.0.1:18679/background');
      final background = {
        'id': 'device-background-$stamp',
        'source': '后台验证',
        'title': '退到桌面后接收消息',
        'format': 'text',
        'content': '前台服务在应用退到桌面后继续保存消息。',
      };
      await request(
        '$endpoint/v1/messages',
        token: sendToken,
        body: background,
      );
      await waitFor(background['title']!);
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(
        (await request(
          '$endpoint/v1/messages/device-background-$stamp/status',
          token: sendToken,
        ))['status'],
        'received',
      );
      await request('http://127.0.0.1:18679/foreground');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('打开菜单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部消息'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await request('http://127.0.0.1:18679/capture/02-inbox');
      await tester.tap(find.text('HTML 报告 · 收发验证').first);
      await tester.pumpAndSettle();
      await Future<void>.delayed(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await request('http://127.0.0.1:18679/capture/03-html');
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(
        (await repository.messages())
            .firstWhere((item) => item.id == message.id)
            .starred,
        true,
      );
      expect(find.text('阅读模式'), findsNothing);
      expect(await repository.diagnose(), contains('接收密钥有效'));
      expect(
        (await repository.messages(
          query: '脚本生成的报告',
        )).any((item) => item.id == message.id),
        true,
      );
      await repository.batch([message.id], 'delete');
      expect(
        (await repository.messages()).any((item) => item.id == message.id),
        false,
      );
      await repository.batch([message.id], 'restore');
      expect(await repository.content(message.id), contains('脚本生成的报告'));
      expect(tester.takeException(), isNull);
    },
  );
}
