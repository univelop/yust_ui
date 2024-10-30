import 'package:flutter/material.dart';

import '../yust_ui.dart';
import 'yust_focusable_builder.dart';
import 'yust_text_field.dart';

class YustInputTile extends StatelessWidget {
  final String? label;
  final String? text;
  final TextStyle? textStyle;
  final TextStyle? labelStyle;
  final Widget? prefixIcon;
  final YustInputStyle style;
  final TapCallback? onTap;
  final DeleteCallback? onDelete;
  final Widget? suffixChild;
  final FormFieldValidator<String>? validator;
  final bool divider;
  final int? maxLines;
  final int? minLines;
  final AutovalidateMode? autovalidateMode;
  final bool excludeFocus;
  final bool showHighlightFocus;

  const YustInputTile({
    super.key,
    this.label,
    this.text,
    this.textStyle,
    this.labelStyle,
    this.prefixIcon,
    this.style = YustInputStyle.normal,
    this.onTap,
    this.onDelete,
    this.suffixChild,
    this.validator,
    this.divider = true,
    this.maxLines,
    this.minLines,
    this.autovalidateMode,
    this.excludeFocus = false,
    this.showHighlightFocus = false,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeFocus(
      excluding: excludeFocus,
      child: YustFocusableBuilder(
        shouldHighlightFocusedWidget: showHighlightFocus,
        onFocusAction: onTap,
        builder: (focusContext) => YustTextField(
          label: label,
          labelStyle: labelStyle,
          value: text,
          textStyle: textStyle,
          style: style,
          readOnly: true,
          divider: divider,
          maxLines: maxLines,
          minLines: minLines,
          prefixIcon: prefixIcon,
          suffixIcon: suffixChild,
          onTap: onTap,
          onDelete: onDelete == null
              ? null
              : () async {
                  await onDelete!();
                },
          validator: validator,
          autovalidateMode: autovalidateMode,
        ),
      ),
    );
  }
}
