import 'package:flutter/material.dart';

class YustBadge extends StatelessWidget {
  final int counter;
  final double size;
  final double textSize;
  final BoxShape shape;
  final Alignment? alignment;
  final BoxConstraints? _constraints;

  YustBadge({
    super.key,
    required this.counter,
    this.size = 16,
    this.textSize = 12,
    this.shape = BoxShape.rectangle,
    this.alignment,
    constraints,
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
