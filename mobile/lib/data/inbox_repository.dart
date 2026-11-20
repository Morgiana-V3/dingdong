import 'dart:convert';
import 'message_preview.dart';
import 'package:flutter/services.dart';

class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.source,
    required this.title,
    required this.summary,
    required this.format,
    required this.createdAt,
    required this.isRead,
    required this.starred,
    this.excerpt = '',
  });

  factory InboxMessage.fromMap(Map<dynamic, dynamic> value) => InboxMessage(
    id: value['id'] as String,
    source: value['source'] as String,
    title: value['title'] as String,
    summary: value['summary'] as String,
    format: value['format'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(value['createdAt'] as int),
    isRead: value['read'] as bool,
    starred: value['starred'] as bool,
    excerpt: value['excerpt'] as String? ?? '',
  );

  final String id;
  final String source;
  final String title;
  final String summary;
  final String format;
  final DateTime createdAt;
  final bool isRead;
  final bool starred;
  final String excerpt;
}

class InboxRepository {
  static const channel = MethodChannel('dingdong/inbox');

  // Message bodies are immutable for a scoped ID. Keep a bounded set of
  // card previews across refreshes, including messages without artwork.
  final _previews = <String, Future<MessagePreview?>>{};

  Future<MessagePreview?> preview(InboxMessage message) {
    if (message.format == 'text') return Future.value();
    final existing = _previews.remove(message.id);
    final result = existing ?? _loadPreview(message);
    _previews[message.id] = result;
    if (_previews.length > 48) _previews.remove(_previews.keys.first);
    return result;
  }

  Future<MessagePreview?> _loadPreview(InboxMessage message) async {
    try {
      final document = await channel.invokeMethod<String>('previewDocument', {
        'id': message.id,
      });
      if (document == null) return null;
      return await messagePreview(document, message.format);
    } on Exception {
      _previews.remove(message.id);
      return null;
    }
  }

  Future<bool> engineAvailable() async {
    try {
      return await channel.invokeMethod<bool>('engineAvailable') ?? false;
    } on Exception {
      return false;
    }
  }

  Future<Map<String, dynamic>> subscriptions([
    Map<String, dynamic>? command,
  ]) async {
    final response = await channel.invokeMethod<String>('subscriptions', {
      if (command != null) 'command': jsonEncode(command),
    });
    return jsonDecode(response!) as Map<String, dynamic>;
  }

  Future<bool> openExternalLink(String address) async =>
      await channel.invokeMethod<bool>('openExternalLink', {
        'address': address,
      }) ??
      false;

  Future<List<InboxMessage>> messages({
    String query = '',
    DateTime? after,
    DateTime? before,
  }) async {
    final values =
        await channel.invokeListMethod<dynamic>('list', {
          'query': query,
          'after': after?.millisecondsSinceEpoch,
          'before': before?.millisecondsSinceEpoch,
        }) ??
        [];
    return values.map((value) => InboxMessage.fromMap(value as Map)).toList();
  }

  Future<Map<String, dynamic>> settings() async => Map<String, dynamic>.from(
    await channel.invokeMapMethod('settings') ?? {},
  );

  Future<String> content(String id) async =>
      await channel.invokeMethod<String>('content', {'id': id}) ?? '';

  Future<void> update(String id, String action, [bool value = true]) async {
    await channel.invokeMethod('update', {
      'id': id,
      'action': action,
      'value': value,
    });
  }

  Future<Set<String>> mutedSources() async =>
      (await channel.invokeListMethod<String>('muted') ?? []).toSet();

  Future<void> mute(String source, bool enabled) async {
    await channel.invokeMethod('mute', {'source': source, 'enabled': enabled});
  }

  Future<void> connect(
    String endpoint,
    String token, {
    bool? directConnection,
  }) async {
    await channel.invokeMethod('connect', {
      'endpoint': endpoint,
      'token': token,
      'directConnection': ?directConnection,
    });
  }

  Future<void> batch(
    List<String> ids,
    String action, [
    bool value = true,
  ]) async {
    await channel.invokeMethod('batch', {
      'ids': ids,
      'action': action,
      'value': value,
    });
  }

  Future<Map<String, dynamic>?> restore() async {
    final response = await channel.invokeMapMethod<String, dynamic>('import');
    return response;
  }

  Future<String> diagnose() async =>
      await channel.invokeMethod<String>('diagnose') ?? '检查未完成';

  Future<bool> saveImage(Uint8List bytes, String mime) async =>
      await channel.invokeMethod<bool>('saveImage', {
        'bytes': bytes,
        'mime': mime,
      }) ??
      false;

  Future<void> disconnect() async => channel.invokeMethod('disconnect');
  Future<void> systemSettings() async => channel.invokeMethod('systemSettings');
  Future<bool> export() async =>
      await channel.invokeMethod<bool>('export') ?? false;
}

String normalizeEndpoint(String input) {
  final trimmed = input
      .trim()
      .replaceAll('：', ':')
      .replaceAll('。', '.')
      .replaceAll('．', '.')
      .replaceAll('／', '/')
      .replaceAll('、', '/')
      .replaceAll(RegExp(r'/+$'), '');
  final value = trimmed.contains('://') ? trimmed : 'http://$trimmed';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      !RegExp(r'^[a-zA-Z0-9.:[\]-]+$').hasMatch(uri.host) ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.path.isNotEmpty ||
      uri.port < 1 ||
      uri.port > 65535) {
    throw const FormatException('请输入服务器 IP 或域名，可附加端口');
  }
  return uri.toString();
}
