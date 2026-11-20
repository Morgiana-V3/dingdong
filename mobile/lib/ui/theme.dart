import 'package:flutter/material.dart';

const accent = Color(0xFFE36547);

/// Keeps list items and form fields comfortably readable on wider windows.
EdgeInsets pageInsets(
  BuildContext context, {
  double side = 16,
  double top = 12,
  double bottom = 24,
}) {
  final inset = (MediaQuery.sizeOf(context).width - 640) / 2;
  final horizontal = inset > side ? inset : side;
  return EdgeInsets.fromLTRB(horizontal, top, horizontal, bottom);
}

ThemeData inboxTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: dark ? const Color(0xFFFFAD95) : const Color(0xFFAC462B),
        surfaceContainerLow: dark ? const Color(0xFF222428) : Colors.white,
        surfaceContainerHighest: dark
            ? const Color(0xFF34363A)
            : const Color(0xFFECEDE9),
        surface: dark ? const Color(0xFF181A1D) : const Color(0xFFFAFAF8),
      );
  final fieldShape = BorderRadius.circular(14);
  OutlineInputBorder fieldBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: fieldShape,
        borderSide: BorderSide(color: color, width: width),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        color: scheme.onSurface,
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -.5,
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: .45),
      thickness: .6,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      constraints: const BoxConstraints(minHeight: 56),
      fillColor: dark ? const Color(0xFF22252A) : const Color(0xFFF0F1EE),
      border: fieldBorder(Colors.transparent),
      enabledBorder: fieldBorder(scheme.outlineVariant.withValues(alpha: .45)),
      disabledBorder: fieldBorder(Colors.transparent),
      focusedBorder: fieldBorder(scheme.primary, 1.5),
      errorBorder: fieldBorder(scheme.error),
      focusedErrorBorder: fieldBorder(scheme.error, 1.5),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: .65),
        fontSize: 14,
      ),
      helperStyle: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
      helperMaxLines: 3,
      errorMaxLines: 3,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: false,
      dragHandleColor: scheme.outlineVariant,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    timePickerTheme: TimePickerThemeData(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary.withValues(alpha: .10),
      height: 68,
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    chipTheme: ChipThemeData(
      labelStyle: TextStyle(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      selectedColor: scheme.primary.withValues(alpha: .12),
    ),
    tabBarTheme: const TabBarThemeData(
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      unselectedLabelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

class SettingsExpansion extends StatelessWidget {
  const SettingsExpansion({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final Widget title;
  final Widget? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(highlightColor: Colors.transparent),
      child: ExpansionTile(
        splashColor: Colors.transparent,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.only(
          top: MediaQuery.textScalerOf(context).scale(12),
          bottom: 4,
        ),
        title: title,
        subtitle: subtitle,
        children: children,
      ),
    );
  }
}

class InlineNotice extends StatelessWidget {
  const InlineNotice(this.text, {super.key, this.onDismiss});
  final String text;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8, right: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Expanded(child: Text(text)),
        if (onDismiss != null)
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
            tooltip: '关闭提示',
          ),
      ],
    ),
  );
}
