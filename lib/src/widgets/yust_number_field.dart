import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
  final bool readOnly;
  final bool enabled;
  final YustInputStyle style;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool hideKeyboardOnAutofocus;
  final FormFieldValidator<num?>? validator;
  final bool divider;
  final TextStyle? valueStyle;
  final EdgeInsets contentPadding;
  final bool completeOnUnfocus;
  final bool skipFocus;

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
    this.enabled = true,
    this.readOnly = false,
    this.style = YustInputStyle.normal,
    this.prefixIcon,
    this.suffixIcon,
    this.focusNode,
    this.autofocus = false,
    this.hideKeyboardOnAutofocus = false,
    this.validator,
    this.divider = true,
    this.contentPadding = const EdgeInsets.all(20.0),
    this.completeOnUnfocus = true,
    this.skipFocus = false,
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
            value: numToString(value,
                decimalCount: decimalCount,
                thousandsSeparator: thousandsSeparator),
            controller: controller,
            onChanged: onChanged == null
                ? null
                : (value) => onChanged!(valueToNum(value?.trim() ?? '',
                    decimalCount: decimalCount)),
            onEditingComplete: onEditingComplete == null
                ? null
                : (value) => onEditingComplete!(valueToNum(value?.trim() ?? '',
                    decimalCount: decimalCount)),
            keyboardType: !allowDecimalInput
                ? TextInputType.number
                : usesSamsungKeyboard
                    ? null
                    : const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              allowDecimalInput
                  ? FilteringTextInputFormatter.allow(RegExp('[0-9.,-]'))
                  : FilteringTextInputFormatter.allow(RegExp('[0-9-]'))
            ],
            textInputAction: TextInputAction.next,
            onTap: onTap,
            readOnly: readOnly,
            enabled: enabled,
            autovalidateMode:
                validator != null ? AutovalidateMode.onUserInteraction : null,
            focusNode: focusNode,
            autofocus: autofocus,
            hideKeyboardOnAutofocus: hideKeyboardOnAutofocus,
            validator: validator == null
                ? null
                : (value) => validator!(valueToNum(value)),
            divider: divider,
            completeOnUnfocus: completeOnUnfocus,
            contentPadding: contentPadding,
          ),
        );
      },
    );
  }

  static String? numToString(num? value,
      {int? decimalCount, bool thousandsSeparator = false}) {
    if (value?.floorToDouble() == value) {
      value = value?.toInt();
    }
    var pattern = thousandsSeparator ? '#,##0' : '0';
    pattern += decimalCount == 0 ? '' : '.';
    pattern += decimalCount != null ? '0' * decimalCount : '#####';
    final format = NumberFormat(pattern, 'de-DE');
    return value != null ? format.format(value) : null;
  }

  static num? valueToNum(String? value, {int? decimalCount}) {
    if (value == '' || value == null) {
      return null;
    } else {
      final format = NumberFormat.decimalPattern('de-DE');
      num? numValue;
      try {
        numValue = format.parse(value);
      } catch (e) {
        return null;
      }
      if (numValue % 1 == 0 || decimalCount == 0) {
        numValue = numValue.toInt();
      }
      return numValue;
    }
  }
}
