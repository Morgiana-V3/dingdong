import 'package:flutter/material.dart';
import 'prepared_reader_transition.dart';

PageRoute<T> readerRoute<T>(
  BuildContext context,
  WidgetBuilder builder, {
  required ValueNotifier<bool> ready,
  required Widget background,
}) {
  final reducedMotion = MediaQuery.disableAnimationsOf(context);
  return PageRouteBuilder<T>(
    // The surface manages entry only after the native document has drawn.
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration(milliseconds: reducedMotion ? 0 : 220),
    allowSnapshotting: false,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        PreparedReaderTransition(
          ready: ready,
          background: background,
          routeAnimation: animation,
          reducedMotion: reducedMotion,
          child: child,
        ),
  );
}

/// The gallery appears over the stationary document without moving it.
PageRoute<T> imagePreviewRoute<T>(BuildContext context, WidgetBuilder builder) {
  final reducedMotion = MediaQuery.disableAnimationsOf(context);
  return PageRouteBuilder<T>(
    transitionDuration: Duration(milliseconds: reducedMotion ? 0 : 180),
    reverseTransitionDuration: Duration(milliseconds: reducedMotion ? 0 : 140),
    allowSnapshotting: false,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
          child: child,
        ),
  );
}
