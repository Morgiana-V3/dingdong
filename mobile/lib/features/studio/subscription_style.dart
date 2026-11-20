import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const digestPluginId = 'digest';

List<Map<String, dynamic>> studioItems(dynamic value) => (value as List? ?? [])
    .whereType<Map>()
    .map((item) => Map<String, dynamic>.from(item))
    .toList();

String studioError(Object error) =>
    error is PlatformException ? error.message ?? '无法连接插件引擎' : '操作未完成，请刷新后重试';

class SubscriptionStyle extends StatelessWidget {
  const SubscriptionStyle({
    super.key,
    required this.child,
    this.compact = false,
  });
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final colors = base.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    ButtonStyle button(Color? background) => TextButton.styleFrom(
      minimumSize: Size(48, compact ? 36 : 52),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 0 : 12,
      ),
      textStyle: base.textTheme.labelLarge?.copyWith(
        fontSize: compact ? 13 : 15,
        fontWeight: FontWeight.w600,
      ),
      shape: shape,
      backgroundColor: background,
    );
    return Theme(
      data: base.copyWith(
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
        textTheme: base.textTheme
            .copyWith(
              titleLarge: base.textTheme.titleLarge?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              titleMedium: base.textTheme.titleMedium?.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              bodyLarge: base.textTheme.bodyLarge?.copyWith(
                fontSize: 14,
                height: 1.4,
              ),
              bodyMedium: base.textTheme.bodyMedium?.copyWith(
                fontSize: 13,
                height: 1.4,
              ),
              bodySmall: base.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                height: 1.4,
              ),
            )
            .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface),
        appBarTheme: base.appBarTheme.copyWith(
          toolbarHeight: 48,
          titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        cardTheme: base.cardTheme.copyWith(
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: .55),
            ),
          ),
        ),
        listTileTheme: ListTileThemeData(
          dense: compact,
          minVerticalPadding: 6,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 2,
          ),
          titleTextStyle: base.textTheme.titleMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
          subtitleTextStyle: base.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            height: 1.4,
            color: colors.onSurfaceVariant,
          ),
        ),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          isDense: compact,
          constraints: compact ? null : const BoxConstraints(minHeight: 56),
          contentPadding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 12 : 17,
          ),
          labelStyle: TextStyle(
            fontSize: compact ? 13 : 15,
            color: colors.onSurfaceVariant,
          ),
        ),
        chipTheme: base.chipTheme.copyWith(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          labelStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(style: button(null)),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: button(null).copyWith(
            side: WidgetStatePropertyAll(
              BorderSide(color: colors.outlineVariant),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(style: button(null)),
      ),
      child: child,
    );
  }
}

class SubscriptionStatus extends StatelessWidget {
  const SubscriptionStatus(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: tint,
        ),
      ),
    );
  }
}
