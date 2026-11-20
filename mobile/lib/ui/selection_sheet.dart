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
    showDragHandle: false,
    clipBehavior: Clip.antiAlias,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (context) => _SheetFrame(child: builder(context)),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .86,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: '关闭面板',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.maybePop(context),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: const SizedBox(width: 32, height: 4),
                    ),
                  ),
                ),
              ),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
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
    final colors = Theme.of(context).colorScheme;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
      child: Semantics(
        header: true,
        child: DefaultTextStyle.merge(
          style: TextStyle(
            fontSize: 16,
            height: 1.4,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
          child: title,
        ),
      ),
    );
    final body = ListTileTheme(
      data: ListTileThemeData(
        minTileHeight: 48,
        minVerticalPadding: 4,
        minLeadingWidth: 22,
        horizontalTitleGap: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        iconColor: colors.onSurfaceVariant,
        titleTextStyle: TextStyle(
          fontSize: 15,
          height: 1.3,
          color: colors.onSurface,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 12,
          height: 1.35,
          color: colors.onSurfaceVariant,
        ),
      ),
      child: Padding(padding: const EdgeInsets.only(bottom: 8), child: content),
    );
    final footer = Padding(
      padding: const EdgeInsets.only(top: 4),
      child: OverflowBar(
        spacing: 8,
        overflowSpacing: 4,
        alignment: MainAxisAlignment.end,
        overflowAlignment: OverflowBarAlignment.end,
        children: actions,
      ),
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
  builder: (context) {
    final colors = Theme.of(context).colorScheme;
    return SheetDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final choice in choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
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
                selectedTileColor: colors.primary.withValues(alpha: .09),
                selectedColor: colors.primary,
                enabled: choice.enabled,
                leading: choice.icon == null ? null : Icon(choice.icon),
                title: Text(
                  choice.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: choice.value == selected
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
                subtitle: choice.description == null
                    ? null
                    : Text(
                        choice.description!,
                        style: const TextStyle(fontSize: 12, height: 1.4),
                      ),
                trailing: choice.value == selected
                    ? Icon(Icons.check_rounded, color: colors.primary, size: 20)
                    : null,
                onTap: () => Navigator.pop(context, choice.value),
              ),
            ),
        ],
      ),
    );
  },
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
      final useGrid =
          choices.length >= 2 &&
          choices.length <= 4 &&
          choices.every((c) => c.icon != null && c.description == null);
      final Future<T?> pending = useGrid
          ? showAppSheet<T>(
              context: context,
              builder: (context) => SheetDialog(
                title: Text(tooltip),
                content: _SheetActionGrid<T>(choices: choices),
              ),
            )
          : showChoiceSheet(context: context, title: tooltip, choices: choices);
      final selected = await pending;
      if (selected != null && context.mounted) onSelected(selected);
    },
  );
}

class _SheetActionGrid<T> extends StatelessWidget {
  const _SheetActionGrid({required this.choices});
  final List<SheetChoice<T>> choices;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final scaledWidth =
            MediaQuery.textScalerOf(context).scale(14) / 14 * 92;
        final count = ((constraints.maxWidth + gap) / (scaledWidth + gap))
            .floor()
            .clamp(1, choices.length);
        final width = (constraints.maxWidth - gap * (count - 1)) / count;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final choice in choices)
              SizedBox(
                width: width,
                child: Opacity(
                  opacity: choice.enabled ? 1 : 0.42,
                  child: Material(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: choice.enabled
                          ? () => Navigator.pop(context, choice.value)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 12,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              choice.icon,
                              size: 22,
                              color: colors.onSurface,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              choice.label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                                color: colors.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
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
