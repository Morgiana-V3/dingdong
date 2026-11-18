import 'package:flutter/material.dart';

class SubscriptionStyle extends StatelessWidget {
  const SubscriptionStyle({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final colors = base.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    ButtonStyle button(Color? background) => TextButton.styleFrom(
      minimumSize: const Size(40, 36),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      shape: shape,
      backgroundColor: background,
    );
    return Theme(
      data: base.copyWith(
        visualDensity: VisualDensity.compact,
        textTheme: base.textTheme
            .copyWith(
              titleLarge: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              titleMedium: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              bodyLarge: const TextStyle(fontSize: 14, height: 1.4),
              bodyMedium: const TextStyle(fontSize: 13, height: 1.4),
              bodySmall: const TextStyle(fontSize: 12, height: 1.4),
            )
            .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface),
        appBarTheme: base.appBarTheme.copyWith(
          toolbarHeight: 48,
          titleTextStyle: TextStyle(
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
          dense: true,
          minVerticalPadding: 6,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 2,
          ),
          titleTextStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
          subtitleTextStyle: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: colors.onSurfaceVariant,
          ),
        ),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          labelStyle: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
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
