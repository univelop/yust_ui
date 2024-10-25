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
/// YustFocusableWrapper(
///   builder: (context) => YourWidget(),
/// )
/// ```
///
/// The `YustFocusableWrapper` can be customized to handle specific focus
/// behaviors as needed.
class YustFocusableWrapper extends StatefulWidget {
  const YustFocusableWrapper({
    super.key,
    required this.builder,
    this.onTap,
    this.actions,
    this.shortcuts,
    this.shouldHighlightFocusedWidget = false,
  });

  ///  A callback function that is triggered when the widget is tapped.
  final Function()? onTap;

  ///  A function that takes a `BuildContext` and returns the child widget.
  final Function(BuildContext context) builder;

  ///  A map of custom actions that can be triggered by intents. Default to the enter action which call the onTap function.
  final Map<Type, Action<Intent>>? actions;

  /// A map of shortcut activators and their corresponding intents. Defaults to the Keyboard Enter Key activator thats calls an `ActivateIntent`.
  final Map<ShortcutActivator, Intent>? shortcuts;

  /// A boolean value that determines whether the focused widget should be highlighted.
  final bool shouldHighlightFocusedWidget;

  @override
  State<YustFocusableWrapper> createState() => _YustFucusableWrapperState();
}

class _YustFucusableWrapperState extends State<YustFocusableWrapper> {
  late final FocusNode _focusNode = FocusNode();

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
  void _handleFocusChange() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: _focusNode,
      actions: widget.actions ??
          {
            ActivateIntent: CallbackAction<Intent>(onInvoke: (_) {
              if (widget.shouldHighlightFocusedWidget) _focusNode.unfocus();
              return widget.onTap?.call();
            }),
          },
      shortcuts: widget.shortcuts ??
          <LogicalKeySet, Intent>{
            LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
          },
      child: Stack(
        children: [
          if (widget.shouldHighlightFocusedWidget && _focusNode.hasFocus)
            Positioned.fill(
                child: ColoredBox(
              color: Colors.black.withOpacity(0.1),
            )),
          Builder(
            builder: (builderContext) {
              return widget.builder(builderContext);
            },
          ),
        ],
      ),
    );
  }
}
