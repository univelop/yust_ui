import 'package:flutter/material.dart';

import '../yust_ui.dart';
import 'yust_focusable_builder.dart';

class YustListTile extends StatelessWidget {
  final String? label;

  /// If navigate is set, the SuffixChild will display a Navigation Icon
  final bool navigate;
  final bool center;

  /// If labelStyle is set, it will override heading
  final bool heading;

  /// If labelStyle is set, it will override largeHeading
  final bool largeHeading;
  final Widget? suffixChild;
  final TapCallback? onTap;
  final YustInputStyle style;

  /// If labelStyle is set, it will override heading and largeHeading
  final TextStyle? labelStyle;
  final bool labelOverflow;
  final Widget? prefixIcon;
  final Widget? below;
  final bool divider;
  final bool skipFocus;
  final bool showHighlightFocus;

  const YustListTile({
    super.key,
    this.label,
    this.navigate = false,
    this.center = false,
    this.heading = false,
    this.largeHeading = false,
    this.suffixChild,
    this.onTap,
    this.style = YustInputStyle.normal,
    this.labelStyle,
    this.labelOverflow = false,
    this.prefixIcon,
    this.below,
    this.divider = true,
    this.skipFocus = false,
    this.showHighlightFocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return YustFocusableBuilder(
      skipFocus: skipFocus,
      focusNodeDebugLabel: 'yust-list-tile-$label',
      builder: (focusContext){
if (style == YustInputStyle.outlineBorder) {
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4.0),
        ),
        child: _buildInner(focusContext),
      );
    } else {
      return Column(
        children: <Widget>[
          _buildInner(focusContext),
          below ?? const SizedBox(),
          if (divider && !(heading || largeHeading))
            const Divider(height: 1.0, thickness: 1.0, color: Colors.grey),
        ],
      );
    }
      },
    );
  }

  Widget _buildInner(BuildContext context) {
    EdgeInsets padding;
    if (style == YustInputStyle.normal) {
      if (label != null && prefixIcon != null) {
        padding = const EdgeInsets.only(
            left: 8.0, top: 8.0, right: 16.0, bottom: 8.0);
      } else {
        padding = const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0);
      }
    } else {
      padding = const EdgeInsets.symmetric(horizontal: 10.0, vertical: 0);
    }
    final text = Text(
      label ?? '',
      style: labelStyle ??
          ((heading || largeHeading)
              ? TextStyle(
                  fontSize: largeHeading ? 24 : 20,
                  color: Theme.of(context).primaryColor)
              : null),
      overflow: labelOverflow ? TextOverflow.ellipsis : null,
    );

    return YustFocusableBuilder(
      focusNodeDebugLabel: 'yust-list-tile-$label',
      shouldHighlightFocusedWidget: showHighlightFocus,
      onFocusAction: onTap,
      builder: (focusContext) => ListTile(
        title: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            if (prefixIcon != null)
              Padding(
                padding: const EdgeInsets.only(right: 10.0, left: 3.0),
                child: prefixIcon,
              ),
            Flexible(
              child: center
                  ? Center(
                      child: text,
                    )
                  : text,
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (navigate)
              const Icon(
                Icons.navigate_next,
              ),
            if (suffixChild != null) suffixChild!,
          ],
        ),
        onTap: onTap,
        contentPadding: padding,
      ),
    );
  }
}
