import 'package:flutter/material.dart';

class YustBadge extends StatelessWidget {
  // The counter to display inside the badge
  final int counter;

  // The size of the badge. Symmetric width and height.
  final double size;

  // The text size of the counter inside the badge.
  final double textSize;

  // The shape of the badge: rectangle or circle.
  final BoxShape shape;

  // The alignment of the badge content.
  final Alignment? alignment;

  // The constraints of the badge. Can be used to override the default size and make it more flexible.
  final BoxConstraints? _constraints;

  YustBadge({
    super.key,
    required this.counter,
    this.size = 16,
    this.textSize = 12,
    this.shape = BoxShape.rectangle,
    this.alignment,
    BoxConstraints? constraints,
  }) : _constraints =
           constraints ??
           BoxConstraints(
             minWidth: size,
             minHeight: size,
           );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: Colors.red,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle
            ? BorderRadius.circular(8)
            : null,
      ),
      constraints: _constraints,
      alignment: alignment,
      child: Text(
        '$counter',
        style: TextStyle(
          color: Colors.white,
          fontSize: textSize,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
