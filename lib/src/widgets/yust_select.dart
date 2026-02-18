import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:yust_ui/src/extensions/string_translate_extension.dart';
import 'package:yust_ui/yust_ui.dart';

import '../generated/locale_keys.g.dart';

class YustSelect<T> extends StatelessWidget {
  final String? label;
  final T value;

  /// The label to be displayed for unknown options.
  final String? unknownOptionLabel;
  final List<T> optionValues;
  final List<String> optionLabels;

  /// Optional list of widgets to be displayed before the label.
  final List<Widget>? prefixWidgets;
  final void Function(T)? onSelected;
  final DeleteCallback? onDelete;
  final YustInputStyle style;
  final Widget? prefixIcon;
  final Widget? suffixChild;
  final FormFieldValidator<String>? validator;
  final bool readOnly;
  final bool divider;
  final int? maxLines;
  final int? minLines;
  final bool allowSearch;
  final AutovalidateMode? autovalidateMode;
  final bool showHighlightFocus;

  /// A function to compare two values of type [T].
  /// It is used to find the index of the value in the optionValues list.
  /// If null, the default equality check is used.
  final bool Function(T a, T b)? optionEquals;
  final bool Function(T) _isSelectable;
  // The Icon to be displayed in front of the selected value
  final IconData? prefixValueIcon;

  /// The color of the prefix value icon
  final Color? prefixValueIconColor;

  /// Whether the InputTile should use the decoration from [InputDecoration.filled] with [InputDecoration.fillColor] from the current Theme
  final bool useFilledInputDecoration;

  /// The color to be used for [InputDecoration.fillColor] if [useFilledInputDecoration] is true
  /// If null, the default color from the current Theme will be used
  final Color? filledInputDecorationColor;

  /// The optional helper text below the text field
  final String? helperText;

  static const maxVisibleOptions = 10;

  YustSelect({
    super.key,
    this.label,
    required this.value,
    this.unknownOptionLabel,
    required this.optionValues,
    required this.optionLabels,
    this.prefixWidgets,
    bool Function(T)? isSelectable,
    this.onSelected,
    this.onDelete,
    this.style = YustInputStyle.normal,
    this.prefixIcon,
    this.suffixChild,
    this.validator,
    this.readOnly = false,
    this.divider = true,
    this.maxLines,
    this.minLines,
    this.allowSearch = true,
    this.autovalidateMode,
    this.showHighlightFocus = false,
    this.optionEquals,
    this.prefixValueIcon,
    this.prefixValueIconColor,
    this.helperText,
  }) : _isSelectable = isSelectable ?? ((_) => true),
       useFilledInputDecoration = false,
       filledInputDecorationColor = null;

  YustSelect.filled({
    super.key,
    this.label,
    required this.value,
    this.unknownOptionLabel,
    required this.optionValues,
    required this.optionLabels,
    this.prefixWidgets,
    bool Function(T)? isSelectable,
    this.onSelected,
    this.onDelete,
    this.style = YustInputStyle.normal,
    this.prefixIcon,
    this.suffixChild,
    this.validator,
    this.readOnly = false,
    this.divider = true,
    this.maxLines,
    this.minLines,
    this.allowSearch = true,
    this.autovalidateMode,
    this.showHighlightFocus = false,
    this.optionEquals,
    this.prefixValueIcon,
    this.prefixValueIconColor,
    this.filledInputDecorationColor,
    this.helperText,
  }) : _isSelectable = isSelectable ?? ((_) => true),
       useFilledInputDecoration = true;

  @override
  Widget build(BuildContext context) {
    return useFilledInputDecoration
        ? YustInputTile.filled(
            label: label ?? '',
            text: _valueCaption(value),
            prefixIcon: prefixIcon,
            suffixChild: suffixChild,
            validator: validator,
            autovalidateMode: autovalidateMode,
            style: style,
            showHighlightFocus: showHighlightFocus,
            divider: divider,
            maxLines: maxLines,
            minLines: minLines,
            prefixLabelIcon: prefixValueIcon,
            prefixLabelIconColor: prefixValueIconColor,
            filledInputDecorationColor: filledInputDecorationColor,
            onTap: (onSelected == null || readOnly)
                ? null
                : () => _selectValue(context),
            onDelete: readOnly ? null : onDelete,
            helperText: helperText,
          )
        : YustInputTile(
            label: label ?? '',
            text: _valueCaption(value),
            prefixIcon: prefixIcon,
            suffixChild: suffixChild,
            validator: validator,
            autovalidateMode: autovalidateMode,
            style: style,
            showHighlightFocus: showHighlightFocus,
            divider: divider,
            maxLines: maxLines,
            minLines: minLines,
            prefixLabelIcon: prefixValueIcon,
            prefixLabelIconColor: prefixValueIconColor,
            onTap: (onSelected == null || readOnly)
                ? null
                : () => _selectValue(context),
            onDelete: readOnly ? null : onDelete,
            helperText: helperText,
          );
  }

  String _valueCaption(T value) {
    int index;
    if (optionEquals != null) {
      index = optionValues.indexWhere((o) => optionEquals!(o, value));
    } else {
      index = optionValues.indexOf(value);
    }

    if (index == -1) {
      return unknownOptionLabel ?? '';
    }
    return optionLabels[index];
  }

  void _selectValue(BuildContext context) async {
    if (onSelected == null) return;
    final enabledOptionValues = optionValues.where(_isSelectable).toList();
    final enabledOptionLabels = optionLabels
        .whereIndexed((index, value) => _isSelectable(optionValues[index]))
        .toList();
    final enabledPrefixWidgets = prefixWidgets
        ?.whereIndexed((index, value) => _isSelectable(optionValues[index]))
        .toList();
    final selectedValue = await YustUi.alertService.showSelectDialog(
      optionValues: enabledOptionValues,
      optionLabels: enabledOptionLabels,
      prefixWidgets: enabledPrefixWidgets ?? [],
      label: label ?? '',
    );
    if (selectedValue != null) {
      onSelected!(selectedValue);
    }
  }
}
