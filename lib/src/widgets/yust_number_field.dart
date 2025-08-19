import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yust/yust.dart';

import '../yust_ui.dart';
import 'yust_focusable_builder.dart';
import 'yust_text_field.dart';

typedef ChangeCallback = void Function(num?);

class YustNumberField extends StatelessWidget {
  final String? label;
  final num? value;
  final int? decimalCount;
  final bool thousandsSeparator;
  final ChangeCallback? onChanged;
  final ChangeCallback? onEditingComplete;
  final TextEditingController? controller;
  final TapCallback? onTap;
  final bool expands;
  final bool readOnly;
  final bool enabled;
  final YustInputStyle style;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool hideKeyboardOnAutofocus;
  final bool slimDesign;
  final FormFieldValidator<num?>? validator;
  final bool divider;
  final TextStyle? valueStyle;
  final EdgeInsets contentPadding;
  final bool completeOnUnfocus;
  final bool skipFocus;
  final String? forceErrorText;

  const YustNumberField({
    super.key,
    this.label,
    this.value,
    this.valueStyle,
    this.decimalCount,
    this.thousandsSeparator = false,
    this.onChanged,
    this.onEditingComplete,
    this.controller,
    this.onTap,
    this.expands = false,
    this.enabled = true,
    this.readOnly = false,
    this.style = YustInputStyle.normal,
    this.prefixIcon,
    this.suffixIcon,
    this.focusNode,
    this.autofocus = false,
    this.hideKeyboardOnAutofocus = false,
    this.slimDesign = false,
    this.validator,
    this.divider = true,
    this.contentPadding = const EdgeInsets.fromLTRB(16.0, 20.0, 20.0, 20.0),
    this.completeOnUnfocus = true,
    this.skipFocus = false,
    this.forceErrorText,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      // Remove this, when the Samsung Keyboard Bug
      // (github.com/flutter/flutter/issues/61175) is resolved
      future: YustUi.helpers.usesSamsungKeyboard(),
      builder: (context, snapshot) {
        final usesSamsungKeyboard = snapshot.data ?? false;
        final allowDecimalInput = decimalCount != 0;

        return YustFocusableBuilder(
          skipFocus: skipFocus,
          focusNodeDebugLabel: 'yust-number-field-$label',
          builder: (focusContext) => YustTextField(
            style: style,
            textStyle: valueStyle,
            label: label,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            value: value == null
                ? null
                : Yust.helpers.numToString(
                    value!,
                    decimalDigitCount: decimalCount ?? 5,
                    padDecimalDigits: decimalCount != null,
                    thousandsSeparator: thousandsSeparator,
                  ),
            controller: controller,
            onChanged: onChanged == null
                ? null
                : (value) => onChanged!(
                    Yust.helpers.stringToNumber(
                      value?.trim() ?? '',
                      precision: decimalCount,
                    ),
                  ),
            onEditingComplete: onEditingComplete == null
                ? null
                : (value) => onEditingComplete!(
                    Yust.helpers.stringToNumber(
                      value?.trim() ?? '',
                      precision: decimalCount,
                    ),
                  ),
            keyboardType: !allowDecimalInput
                ? TextInputType.number
                : usesSamsungKeyboard
                ? null
                : const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              allowDecimalInput
                  ? FilteringTextInputFormatter.allow(RegExp('[0-9.,-]'))
                  : FilteringTextInputFormatter.allow(RegExp('[0-9-]')),
            ],
            textInputAction: TextInputAction.next,
            onTap: onTap,
            expands: expands,
            readOnly: readOnly,
            enabled: enabled,
            autovalidateMode: validator != null
                ? AutovalidateMode.onUserInteraction
                : null,
            focusNode: focusNode,
            autofocus: autofocus,
            hideKeyboardOnAutofocus: hideKeyboardOnAutofocus,
            slimDesign: slimDesign,
            validator: validator == null
                ? null
                : (value) => validator!(
                    Yust.helpers.stringToNumber(
                      value?.trim() ?? '',
                      precision: decimalCount,
                    ),
                  ),
            divider: divider,
            completeOnUnfocus: completeOnUnfocus,
            contentPadding: contentPadding,
            forceErrorText: forceErrorText,
          ),
        );
      },
    );
  }
}
