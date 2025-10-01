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
  final bool skipFocus;
  final bool showHighlightFocus;
  // The Icon to be displayed in front of the label
  final IconData? prefixLabelIcon;

  /// The color of the prefix label icon
  final Color? prefixLabelIconColor;

  /// Whether the InputTile should use the decoration from [InputDecoration.filled] with [InputDecoration.fillColor] from the current Theme
  final bool useFilledInputDecoration;
  
  /// The color to be used for [InputDecoration.fillColor] if [useFilledInputDecoration] is true
  /// If null, the default color from the current Theme will be used
  final Color? filledInputDecorationColor;

    /// The optional helper text below the text field
  final String? helperText;

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
    this.skipFocus = false,
    this.showHighlightFocus = false,
    this.prefixLabelIcon,
    this.prefixLabelIconColor,
    this.useFilledInputDecoration = false,
    this.filledInputDecorationColor,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    return YustFocusableBuilder(
      skipFocus: skipFocus,
      focusNodeDebugLabel: 'yust-input-tile-$label',
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
        prefixLabelIcon: prefixLabelIcon,
        prefixLabelIconColor: prefixLabelIconColor,
        useFilledInputDecoration: useFilledInputDecoration,
        filledInputDecorationColor: filledInputDecorationColor,
        helperText: helperText,
      ),
    );
  }
}
