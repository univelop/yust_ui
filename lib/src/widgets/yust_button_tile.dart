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

  const YustButtonTile({
    Key? key,
    this.label = '',
    this.color,
    this.textColor = Colors.white,
    this.icon,
    this.onPressed,
    this.above,
    this.below,
    this.elevated = true,
    this.divider = true,
    this.slimDesign = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (slimDesign) return _buildButton();

    return Column(
      children: [
        above ?? const SizedBox(),
        Padding(
          padding: const EdgeInsets.all(10),
          child: _buildButton(),
        ),
        below ?? const SizedBox(),
        if (divider)
          const Divider(height: 1.0, thickness: 1.0, color: Colors.grey),
      ],
    );
  }

  Widget _buildButton() {
    return elevated
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
  }
}
