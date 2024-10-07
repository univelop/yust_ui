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
  });

  ///  A callback function that is triggered when the widget is tapped.
  final Function()? onTap;
  ///  A function that takes a `BuildContext` and returns the child widget.
  final Function(BuildContext context) builder;
  ///  A map of custom actions that can be triggered by intents. Default to the enter action which call the onTap function. 
  final Map<Type, Action<Intent>>? actions;
  /// A map of shortcut activators and their corresponding intents. Defaults to the Keyboard Enter Key activator thats calls an `ActivateIntent`.
  final Map<ShortcutActivator, Intent>? shortcuts;

  @override
  State<YustFocusableWrapper> createState() => _YustFucusableWrapperState();
}

class _YustFucusableWrapperState extends State<YustFocusableWrapper> {
  late final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: _focusNode,
      actions: widget.actions ?? {
        ActivateIntent: CallbackAction<Intent>(
          onInvoke: (_) => widget.onTap?.call(),
        ),
      },
      shortcuts: widget.shortcuts ?? <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
      },
      child: Builder(
        builder: (builderContext) {
          return widget.builder(builderContext);
        },
      ),
    );
  }
}
