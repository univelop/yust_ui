import 'package:flutter/material.dart';

import '../yust_ui.dart';

class YustFocusHandler extends StatelessWidget {
  final Widget child;

  const YustFocusHandler({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        YustUi.helpers.unfocusCurrent();
      },
      child: child,
    );
  }
}
