import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A stateful widget that provides a focusable wrapper for its child widget.
///
/// This widget is useful for managing focus state and handling focus-related
/// events for its child widget. It ensures that the child widget can receive
/// focus and respond to focus changes appropriately.
///
/// Usage:
/// ```dart
/// YustFocusableBuilder(
///   builder: (context) => YourWidget(),
/// )
/// ```
///
/// The `YustFocusableBuilder` can be customized to handle specific focus
/// behaviors as needed.
class YustFocusableBuilder extends StatefulWidget {
  const YustFocusableBuilder({
    super.key,
    required this.builder,
    this.onFocusAction,
    this.actions,
    this.shortcuts,
    this.shouldHighlightFocusedWidget = false,
    this.skipFocus = false,
    String? focusNodeDebugLabel,
  }) : focusNodeDebugLabel =
           focusNodeDebugLabel ?? 'yust-focusable-builder-$key';

  ///  A callback function that is triggered when the widget has its focus and the action intent is triggered. But it is only triggered when no other action is defined.
  final Function()? onFocusAction;

  ///  A function that takes a `BuildContext` and returns the child widget.
  final Widget Function(BuildContext context) builder;

  ///  A map of custom actions that can be triggered by intents. Default to the enter action which call the onTap function.
  final Map<Type, Action<Intent>>? actions;

  /// A map of shortcut activators and their corresponding intents. Defaults to the Keyboard Enter Key activator thats calls an `ActivateIntent`.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// A boolean value that determines whether the focused widget should be highlighted.
  final bool shouldHighlightFocusedWidget;

  /// A string that is used to identify the focus node in the tree for debugging purposes.
  final String focusNodeDebugLabel;

  /// A boolean value that determines whether the focus should be skipped.
  final bool skipFocus;

  @override
  State<YustFocusableBuilder> createState() => _YustFocusableBuilderState();
}

class _YustFocusableBuilderState extends State<YustFocusableBuilder> {
  late final FocusNode _focusNode = FocusNode(
    debugLabel: widget.focusNodeDebugLabel,
    skipTraversal: widget.skipFocus,
  );

  @override
  void initState() {
    super.initState();
    if (widget.shouldHighlightFocusedWidget) {
      _focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    if (widget.shouldHighlightFocusedWidget) {
      _focusNode.removeListener(_handleFocusChange);
    }
    _focusNode.dispose();
    super.dispose();
  }

  // trigger a rebuild when the focus changes
  void _handleFocusChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: _focusNode,
      actions:
          widget.actions ??
          {
            ActivateIntent: CallbackAction<Intent>(
              onInvoke: (_) {
                if (widget.shouldHighlightFocusedWidget) _focusNode.unfocus();
                return widget.onFocusAction?.call();
              },
            ),
          },
      shortcuts:
          widget.shortcuts ??
          <LogicalKeySet, Intent>{
            LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
          },
      child: Stack(
        children: [
          if (widget.shouldHighlightFocusedWidget && _focusNode.hasFocus)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: .1),
              ),
            ),
          Builder(
            builder: widget.builder,
          ),
        ],
      ),
    );
  }
}
