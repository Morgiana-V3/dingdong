import 'package:flutter/material.dart';
import '../../ui/selection_sheet.dart';
import 'studio_page.dart';

Future<Set<String>?> selectDigestSources({
  required BuildContext context,
  required List<Map<String, dynamic>> tasks,
  required List<Map<String, dynamic>> plugins,
  required Set<String> selected,
  String? digestId,
}) {
  final draft = {...selected};
  String? ownerOf(String id) =>
      tasks
              .where(
                (task) =>
                    task['pluginId'] == digestPluginId &&
                    task['enabled'] == true &&
                    task['id'] != digestId &&
                    ((task['config'] as Map?)?['sourceTaskIds'] as String? ??
                            '')
                        .split(',')
                        .contains(id),
              )
              .firstOrNull?['name']
          as String?;
  final sources = tasks
      .where((task) => task['pluginId'] != digestPluginId)
      .toList();
  return showAppSheet<Set<String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => SheetDialog(
        title: const Text('选择内容源'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('选择已有任务，沿用它的插件、筛选规则和账号。最多 8 个；启用后由统一推送执行。'),
            const SizedBox(height: 16),
            if (sources.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('还没有来源任务，可返回点击“添加内容源”选择插件并配置。'),
              ),
            for (final source in sources)
              Builder(
                builder: (context) {
                  final id = source['id'] as String;
                  final plugin = plugins
                      .where((plugin) => plugin['id'] == source['pluginId'])
                      .firstOrNull;
                  final owner = ownerOf(id);
                  final supported =
                      plugin?['studio'] == true ||
                      plugin?['digestSource'] == true;
                  final reason = owner != null
                      ? '已由「$owner」统一推送'
                      : !supported
                      ? '此插件暂不支持汇总'
                      : plugin?['name'] as String? ?? '插件未安装';
                  final checked = draft.contains(id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      tileColor: checked
                          ? Theme.of(
                              context,
                            ).colorScheme.primaryContainer.withValues(alpha: .3)
                          : Theme.of(context).colorScheme.surfaceContainerLow,
                      title: Text(source['name'] as String),
                      subtitle: Text(reason),
                      value: checked,
                      onChanged:
                          !checked &&
                              (owner != null || !supported || draft.length >= 8)
                          ? null
                          : (value) => update(() {
                              if (value == true) {
                                draft.add(id);
                              } else {
                                draft.remove(id);
                              }
                            }),
                    ),
                  );
                },
              ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, draft),
            child: Text('完成（${draft.length}/8）'),
          ),
        ],
      ),
    ),
  );
}
