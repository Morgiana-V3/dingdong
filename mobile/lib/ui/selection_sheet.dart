import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    clipBehavior: Clip.antiAlias,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .82,
        ),
        child: SafeArea(top: false, child: builder(context)),
      ),
    ),
  );
}

class SheetDialog extends StatelessWidget {
  const SheetDialog({
    super.key,
    required this.title,
    this.content,
    this.actions = const [],
  });
  final Widget title;
  final Widget? content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        Expanded(
          child: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            child: title,
          ),
        ),
        IconButton(
          tooltip: '关闭面板',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ],
    );
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: content,
    );
    final footer = OverflowBar(
      spacing: 8,
      overflowSpacing: 4,
      alignment: MainAxisAlignment.end,
      children: actions,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Short windows and tall text can leave no room between a fixed title
          // and stacked actions. Let the entire panel scroll in that case.
          if (constraints.maxHeight <
              MediaQuery.textScalerOf(context).scale(200)) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  if (content != null) body,
                  if (actions.isNotEmpty) footer,
                ],
              ),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (content != null)
                Flexible(child: SingleChildScrollView(child: body)),
              if (actions.isNotEmpty) footer,
            ],
          );
        },
      ),
    );
  }
}

class SheetChoice<T> {
  const SheetChoice({
    required this.value,
    required this.label,
    this.description,
    this.icon,
    this.enabled = true,
  });
  final T value;
  final String label;
  final String? description;
  final IconData? icon;
  final bool enabled;
}

Future<T?> showChoiceSheet<T>({
  required BuildContext context,
  required String title,
  required List<SheetChoice<T>> choices,
  T? selected,
}) => showAppSheet<T>(
  context: context,
  builder: (context) => SheetDialog(
    title: Text(title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final choice in choices)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              selected: choice.value == selected,
              selectedTileColor: Colors.transparent,
              enabled: choice.enabled,
              leading: choice.icon == null ? null : Icon(choice.icon),
              title: Text(
                choice.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: choice.description == null
                  ? null
                  : Text(
                      choice.description!,
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
              trailing: choice.value == selected
                  ? Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => Navigator.pop(context, choice.value),
            ),
          ),
      ],
    ),
  ),
);

class SheetSelectField extends StatelessWidget {
  const SheetSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.validator,
  });
  final String label;
  final String? value;
  final List<SheetChoice<String>> choices;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  @override
  Widget build(BuildContext context) => FormField<String>(
    initialValue: value,
    validator: validator,
    builder: (field) => Semantics(
      button: true,
      enabled: onChanged != null,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onChanged == null
            ? null
            : () async {
                final selected = await showChoiceSheet(
                  context: context,
                  title: label,
                  choices: choices,
                  selected: field.value,
                );
                if (selected != null && context.mounted) {
                  field.didChange(selected);
                  onChanged!(selected);
                }
              },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            enabled: onChanged != null,
            errorText: field.errorText,
            suffixIcon: const Icon(Icons.expand_more_rounded),
          ),
          child: Text(
            choices
                    .where((choice) => choice.value == field.value)
                    .firstOrNull
                    ?.label ??
                '请选择',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    ),
  );
}

class SheetMenuButton<T> extends StatelessWidget {
  const SheetMenuButton({
    super.key,
    required this.tooltip,
    required this.choices,
    required this.onSelected,
  });
  final String tooltip;
  final List<SheetChoice<T>> choices;
  final ValueChanged<T> onSelected;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    icon: const Icon(Icons.more_vert),
    onPressed: () async {
      final selected = await showChoiceSheet(
        context: context,
        title: tooltip,
        choices: choices,
      );
      if (selected != null && context.mounted) onSelected(selected);
    },
  );
}

Future<TimeOfDay?> showTimeSheet({
  required BuildContext context,
  required TimeOfDay initialTime,
}) {
  var selected = initialTime;
  return showAppSheet<TimeOfDay>(
    context: context,
    builder: (context) => SheetDialog(
      title: const Text('执行时间（北京时间）'),
      content: SizedBox(
        height: 200,
        child: CupertinoTheme(
          data: CupertinoThemeData(
            brightness: Theme.of(context).brightness,
            primaryColor: Theme.of(context).colorScheme.primary,
          ),
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.time,
            use24hFormat: true,
            initialDateTime: DateTime(
              2000,
              1,
              1,
              initialTime.hour,
              initialTime.minute,
            ),
            onDateTimeChanged: (time) =>
                selected = TimeOfDay.fromDateTime(time),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, selected),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

Future<DateTimeRange?> showDateRangeSheet({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
  String helpText = '选择日期',
  String saveText = '确定',
}) {
  var start = initialDateRange?.start ?? DateUtils.dateOnly(DateTime.now());
  var end = initialDateRange?.end ?? start;
  var editingStart = true;
  return showAppSheet<DateTimeRange>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => SheetDialog(
        title: Text(helpText),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 12,
              children: [
                ChoiceChip(
                  label: Text('开始 ${start.year}/${start.month}/${start.day}'),
                  selected: editingStart,
                  onSelected: (_) => update(() => editingStart = true),
                ),
                ChoiceChip(
                  label: Text('结束 ${end.year}/${end.month}/${end.day}'),
                  selected: !editingStart,
                  onSelected: (_) => update(() => editingStart = false),
                ),
              ],
            ),
            CalendarDatePicker(
              key: ValueKey(editingStart),
              initialDate: editingStart ? start : end,
              firstDate: firstDate,
              lastDate: lastDate,
              onDateChanged: (date) => update(() {
                if (editingStart) {
                  start = date;
                  if (end.isBefore(start)) end = start;
                  editingStart = false;
                } else {
                  end = date;
                  if (start.isAfter(end)) start = end;
                }
              }),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, DateTimeRange(start: start, end: end)),
            child: Text(saveText),
          ),
        ],
      ),
    ),
  );
}
