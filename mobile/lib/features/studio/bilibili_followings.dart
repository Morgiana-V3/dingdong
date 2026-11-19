import '../../ui/theme.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/inbox_repository.dart';
import 'studio_page.dart';

class BilibiliFollowings extends StatefulWidget {
  const BilibiliFollowings({super.key, required this.selected});
  final String selected;
  @override
  State<BilibiliFollowings> createState() => _BilibiliFollowingsState();
}

class _BilibiliFollowingsState extends State<BilibiliFollowings> {
  late final selected = widget.selected
      .split(RegExp(r'[,，\s]+'))
      .where((id) => id.isNotEmpty)
      .toSet();
  final users = <Map<String, dynamic>>[];
  bool busy = false, more = true;
  int page = 1;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final raw = await InboxRepository.channel.invokeMethod<String>(
        'platformAccounts',
        {
          'action': 'followings',
          'platform': 'bilibili',
          'command': jsonEncode({'page': page}),
        },
      );
      final data = jsonDecode(raw!) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          users.addAll(studioItems(data['users']));
          page++;
          more = data['hasMore'] == true;
        });
      }
    } on PlatformException catch (failure) {
      if (mounted) setState(() => error = failure.message ?? '读取关注列表失败');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('选择 UP 主 · ${selected.length}/50'),
      actions: [
        TextButton(
          onPressed: selected.isEmpty || selected.length > 50
              ? null
              : () => Navigator.pop(context, selected.join(',')),
          child: const Text('完成'),
        ),
      ],
    ),
    body: ListView(
      padding: pageInsets(context),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (final user in users)
          Card(
            child: CheckboxListTile(
              value: selected.contains(user['mid']),
              title: Text(user['name'] as String),
              subtitle: Text('UID ${user['mid']}'),
              onChanged: (value) => setState(() {
                if (value == true) {
                  if (selected.length < 50) selected.add(user['mid'] as String);
                } else {
                  selected.remove(user['mid']);
                }
              }),
            ),
          ),
        if (more)
          OutlinedButton(
            onPressed: busy ? null : load,
            child: const Text('加载关注列表'),
          ),
      ],
    ),
  );
}
