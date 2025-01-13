
import 'package:flutter/material.dart';

/// A widget that wraps a child widget and displays a semi-transparent overlay
/// when the specified focus context has focus.
///
/// The `YustFocusedHighlightWrapper` widget takes a `focusContext` and a `child` widget.
/// When the `focusContext` has focus, a semi-transparent black overlay is
/// displayed on top of the `child` widget.
///
/// Example usage:
/// ```dart
/// YustFocusedHighlightWrapper(
///   focusContext: someBuildContext,
///   child: SomeWidget(),
/// )
/// ```
class YustFocusedHighlightWrapper extends StatelessWidget {
  const YustFocusedHighlightWrapper({
    super.key,
    required this.focusContext,
    required this.child,
  });

  /// The context to check for focus.
  final BuildContext focusContext;

  /// The widget to be wrapped and displayed.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (Focus.of(focusContext).hasFocus)
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withOpacity(0.1)),
          ),
        child,
      ],
    );
  }
}
