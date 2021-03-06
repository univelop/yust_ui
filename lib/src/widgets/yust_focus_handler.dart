import 'package:flutter/material.dart';

import '../yust_ui.dart';

class YustFocusHandler extends StatelessWidget {
  final Widget child;

  YustFocusHandler({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        YustUi.helpers.unfocusCurrent(context);
      },
      child: child,
    );
  }
}
