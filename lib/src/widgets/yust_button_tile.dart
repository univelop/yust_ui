import 'dart:async';

import 'package:flutter/material.dart';

/// Button styles for [YustButtonTile].
enum YustButtonStyle {
  primary,
  secondary,
  link;

  /// Returns the appropriate [YustButtonStyle] based on json value [value].
  ///
  /// Use [defaultStyle] to set a default value if the json value is not found.
  static YustButtonStyle fromJson(
    String value, {
    YustButtonStyle defaultStyle = YustButtonStyle.primary,
  }) => YustButtonStyle.values.firstWhere(
    (e) => e.name == value,
    orElse: () => defaultStyle,
  );

  /// Returns the json value of this enum.
  String toJson() => name;
}

class YustButtonTile extends StatelessWidget {
  final String? label;
  final Color? color;
  final Color? textColor;
  final Widget? icon;

  /// Called when the button is pressed.
  ///
  /// May return a [Future]. Together with [allowDoubleClick] set to false the
  /// button then stays disabled until that Future completes, so the work it
  /// starts cannot be started a second time while it is still running.
  final FutureOr<void> Function()? onPressed;
  final Widget? above;
  final Widget? below;
  final bool divider;
  final bool slimDesign;
  final bool inProgress;
  final Widget? suffixChild;
  final String? tooltipMessage;
  final double? maxWidth;
  final YustButtonStyle buttonStyle;

  /// Whether the button accepts a press while a previous press is still
  /// being handled.
  ///
  /// Only has an effect when [onPressed] returns a [Future]: while it is
  /// pending the button is disabled. A synchronous callback has finished by
  /// the time the next press can arrive, so there is nothing to guard.
  final bool allowDoubleClick;

  const YustButtonTile({
    super.key,
    this.label = '',
    this.color,
    this.textColor = Colors.white,
    this.icon,
    this.onPressed,
    this.suffixChild,
    this.above,
    this.below,
    this.divider = true,
    this.slimDesign = false,
    this.inProgress = false,
    this.tooltipMessage,
    this.maxWidth = 400,
    this.buttonStyle = YustButtonStyle.primary,
    this.allowDoubleClick = true,
  });

  @override
  Widget build(BuildContext context) {
    if (slimDesign) return _buildButton();

    return Column(
      children: [
        above ?? const SizedBox(),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          constraints: maxWidth == null
                              ? null
                              : BoxConstraints(
                                  maxWidth: maxWidth!,
                                ),
                          child: _buildButton(),
                        ),
                        if (inProgress)
                          const Padding(
                            padding: EdgeInsets.only(left: 12.0),
                            child: CircularProgressIndicator(),
                          ),
                      ],
                    ),
                    if (suffixChild != null)
                      Positioned(right: 0, child: suffixChild!),
                  ],
                ),
              ),
            ],
          ),
        ),
        below ?? const SizedBox(),
        if (divider)
          const Divider(height: 1.0, thickness: 1.0, color: Colors.grey),
      ],
    );
  }

  Widget _buildButton() {
    final button = _StyledButtonTile(
      buttonStyle: buttonStyle,
      onPressed: onPressed,
      color: color,
      textColor: textColor,
      icon: icon,
      label: label,
      allowDoubleClick: allowDoubleClick,
    );

    if (tooltipMessage != null) {
      return Tooltip(
        message: tooltipMessage!,
        child: button,
      );
    }

    return button;
  }
}

class _StyledButtonTile extends StatefulWidget {
  final String? label;
  final Color? color;
  final Color? textColor;
  final Widget? icon;
  final FutureOr<void> Function()? onPressed;
  final YustButtonStyle buttonStyle;
  final bool allowDoubleClick;

  const _StyledButtonTile({
    required this.buttonStyle,
    required this.onPressed,
    required this.color,
    required this.textColor,
    required this.icon,
    required this.label,
    required this.allowDoubleClick,
  });

  @override
  State<StatefulWidget> createState() => _StyledButtonTileState();
}

class _StyledButtonTileState extends State<_StyledButtonTile> {
  /// Whether a Future returned by [onPressed] is still pending.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return _buildButtonWithoutTooltip();
  }

  Widget _buildButtonWithoutTooltip() {
    switch (widget.buttonStyle) {
      case YustButtonStyle.primary:
        return ElevatedButton.icon(
          onPressed: onPressed(),
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.color,
            foregroundColor: widget.textColor,
          ),
          icon: widget.icon ?? const SizedBox(),
          label: Text(
            widget.label ?? '',
            style: TextStyle(color: widget.textColor),
            overflow: TextOverflow.ellipsis,
          ),
        );
      case YustButtonStyle.secondary:
        return FilledButton.tonalIcon(
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.color,
            foregroundColor: widget.textColor,
          ),
          onPressed: onPressed(),
          icon: widget.icon ?? const SizedBox(),
          label: Text(
            widget.label ?? '',
            style: TextStyle(color: widget.textColor),
            overflow: TextOverflow.ellipsis,
          ),
        );
      default:
        return TextButton.icon(
          onPressed: onPressed(),
          style: TextButton.styleFrom(
            foregroundColor: widget.color,
          ),
          icon: widget.icon ?? const SizedBox(),
          label: Text(
            widget.label ?? '',
            style: TextStyle(decorationColor: widget.color),
            overflow: TextOverflow.ellipsis,
          ),
        );
    }
  }

  VoidCallback? onPressed() {
    final callback = widget.onPressed;
    if (callback == null) return null;
    if (_busy && !widget.allowDoubleClick) return null;

    return () {
      final result = callback();
      if (result is! Future<void> || widget.allowDoubleClick) return;

      setState(() => _busy = true);
      result
          .then<void>(
            (_) {},
            // The error is the callback's, not the button's: surface it the
            // same way an unhandled async error would be, but keep going so
            // the button is released below.
            onError: (Object error, StackTrace stack) =>
                FlutterError.reportError(
                  FlutterErrorDetails(
                    exception: error,
                    stack: stack,
                    library: 'yust_ui',
                    context: ErrorDescription(
                      'while running the onPressed callback of a YustButtonTile',
                    ),
                  ),
                ),
          )
          .whenComplete(() {
            if (mounted) setState(() => _busy = false);
          });
    };
  }
}
