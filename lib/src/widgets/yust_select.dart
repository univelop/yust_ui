import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:yust_ui/src/extensions/string_translate_extension.dart';
import 'package:yust_ui/yust_ui.dart';

import '../generated/locale_keys.g.dart';

class YustSelect<T> extends StatelessWidget {
  final String? label;
  final T value;
  final List<T> optionValues;
  final List<String> optionLabels;
  final void Function(T)? onSelected;
  final DeleteCallback? onDelete;
  final YustInputStyle style;
  final Widget? prefixIcon;
  final Widget? suffixChild;
  final FormFieldValidator<String>? validator;
  final bool readOnly;
  final bool showUnknownValue;
  final bool divider;
  final int? maxLines;
  final int? minLines;
  final bool allowSearch;
  final AutovalidateMode? autovalidateMode;
  final bool showHighlightFocus;
  final bool Function(T) _isSelectable;

  static const maxVisibleOptions = 10;

  YustSelect({
    super.key,
    this.label,
    required this.value,
    required this.optionValues,
    required this.optionLabels,
    bool Function(T)? isSelectable,
    this.onSelected,
    this.onDelete,
    this.style = YustInputStyle.normal,
    this.prefixIcon,
    this.suffixChild,
    this.validator,
    this.readOnly = false,
    this.showUnknownValue = false,
    this.divider = true,
    this.maxLines,
    this.minLines,
    this.allowSearch = true,
    this.autovalidateMode,
    this.showHighlightFocus = false,
  }) : _isSelectable = isSelectable ?? ((_) => true);

  @override
  Widget build(BuildContext context) {
    return YustInputTile(
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
      onTap:
          (onSelected == null || readOnly) ? null : () => _selectValue(context),
      onDelete: readOnly ? null : onDelete,
    );
  }

  String _valueCaption(T value) {
    final index = optionValues.indexOf(value);
    if (index == -1) {
      return showUnknownValue ? value.toString() : '';
    }
    return optionLabels[index];
  }

  void _selectValue(BuildContext context) async {
    if (onSelected == null) return;

    final selectedValues = <T>[];

    await showDialog<T>(
      context: context,
      builder: (BuildContext context) {
        return _buildDialog(context, selectedValues);
      },
    );
    final selectedValue = selectedValues.firstOrNull;
    if (selectedValue != null) {
      onSelected!(selectedValue);
    }
  }

  Widget _buildDialog(BuildContext context, List<T> selectedValues) {
    final enabledOptionValues = optionValues.where(_isSelectable).toList();
    final enabledOptionLabels = optionLabels
        .whereIndexed((index, value) => _isSelectable(optionValues[index]))
        .toList();
    return AlertDialog(
      contentPadding: const EdgeInsets.only(top: 16, bottom: 24),
      title: label == null
          ? null
          : Text(LocaleKeys.selectValue.tr(namedArgs: {'label': label ?? ''})),
      content: YustSelectForm(
        optionValues: enabledOptionValues,
        optionLabels: enabledOptionLabels,
        selectedValues: selectedValues,
        formType: YustSelectFormType.singleWithoutIndicator,
        onChanged: () {
          Navigator.pop(context);
        },
        optionListConstraints: const BoxConstraints(
          maxHeight: 400.0,
          maxWidth: 400.0,
        ),
        divider: false,
        autofocus: true,
      ),
    );
  }
}
