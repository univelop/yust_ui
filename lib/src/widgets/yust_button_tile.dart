import 'package:flutter/material.dart';

class YustButtonTile extends StatelessWidget {
  final String? label;
  final Color? color;
  final Color? textColor;
  final Widget? icon;
  final void Function()? onPressed;
  final Widget? above;
  final Widget? below;
  final bool elevated;
  final bool divider;
  final bool slimDesign;
  final bool inProgress;
  final Widget? suffixChild;
  final String? tooltipMessage;
  final double? maxWidth;

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
    this.elevated = true,
    this.divider = true,
    this.slimDesign = false,
    this.inProgress = false,
    this.tooltipMessage,
    this.maxWidth = 400,
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
                            child: _buildButton()),
                        if (inProgress)
                          const Padding(
                            padding: EdgeInsets.only(left: 12.0),
                            child: CircularProgressIndicator(),
                          ),
                      ],
                    ),
                    if (suffixChild != null)
                      Positioned(right: 0, child: suffixChild!)
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
    var button = elevated
        ? ElevatedButton.icon(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: textColor,
            ),
            icon: icon ?? const SizedBox(),
            label: Text(
              label!,
              overflow: TextOverflow.ellipsis,
            ),
          )
        : TextButton.icon(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: color,
            ),
            icon: icon ?? const SizedBox(),
            label: Text(
              label!,
              overflow: TextOverflow.ellipsis,
            ),
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
