import 'package:flutter/material.dart';

class YustBadge extends StatelessWidget {
  final int counter;

  const YustBadge({super.key, required this.counter});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(8),
      ),
      constraints: const BoxConstraints(
        minWidth: 16,
        minHeight: 16,
      ),
      child: Text(
        '$counter',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
