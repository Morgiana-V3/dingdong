import 'dart:async';
import 'package:flutter/material.dart';

/// The reader stays mounted and paints behind the inbox until its native frame is ready.
class PreparedReaderTransition extends StatefulWidget {
  const PreparedReaderTransition({
    super.key,
    required this.ready,
    required this.background,
    required this.routeAnimation,
    required this.reducedMotion,
    required this.child,
  });

  final ValueNotifier<bool> ready;
  final Widget background;
  final Animation<double> routeAnimation;
  final bool reducedMotion;
  final Widget child;

  @override
  State<PreparedReaderTransition> createState() =>
      _PreparedReaderTransitionState();
}

class _PreparedReaderTransitionState extends State<PreparedReaderTransition>
    with SingleTickerProviderStateMixin {
  late final entrance = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.reducedMotion ? 0 : 280),
  );
  Timer? feedbackDelay;
  bool showFeedback = false;
  bool revealing = false;

  @override
  void initState() {
    super.initState();
    widget.ready.addListener(_reveal);
    feedbackDelay = Timer(const Duration(milliseconds: 700), () {
      if (mounted && !revealing) {
        setState(() => showFeedback = true);
      }
    });
    if (widget.ready.value) {
      _reveal();
    }
  }

  void _reveal() {
    if (!widget.ready.value || revealing || !mounted) {
      return;
    }
    feedbackDelay?.cancel();
    setState(() => revealing = true);
    entrance.forward();
  }

  @override
  void dispose() {
    feedbackDelay?.cancel();
    widget.ready.removeListener(_reveal);
    entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([entrance, widget.routeAnimation]),
    builder: (context, _) {
      final entering = Curves.easeOutCubic.transform(entrance.value);
      final returning = Curves.easeOutCubic.transform(
        widget.routeAnimation.value,
      );
      final offset = revealing ? 1 - entering * returning : 0.0;
      return ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(child: widget.background),
            FractionalTranslation(
              translation: Offset(offset, 0),
              child: ExcludeSemantics(
                excluding: !revealing,
                child: IgnorePointer(
                  ignoring: !revealing || !entrance.isCompleted,
                  child: widget.child,
                ),
              ),
            ),
            if (!revealing) ...[
              ExcludeSemantics(child: widget.background),
              if (showFeedback)
                Align(
                  alignment: Alignment.topCenter,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16, right: 4),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(child: Text('正在打开帖子')),
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('取消'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    },
  );
}
