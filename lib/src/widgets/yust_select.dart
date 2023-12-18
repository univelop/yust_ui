import 'package:flutter/material.dart';
import 'package:yust_ui/yust_ui.dart';

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
  final bool showUnkownValue;
  final bool divider;
  final int? maxLines;
  final int? minLines;
  final bool allowSearch;

  static const maxVisibleOptions = 10;

  const YustSelect({
    Key? key,
    this.label,
    required this.value,
    required this.optionValues,
    required this.optionLabels,
    this.onSelected,
    this.onDelete,
    this.style = YustInputStyle.normal,
    this.prefixIcon,
    this.suffixChild,
    this.validator,
    this.readOnly = false,
    this.showUnkownValue = false,
    this.divider = true,
    this.maxLines,
    this.minLines,
    this.allowSearch = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return YustInputTile(
      label: label ?? '',
      text: _valueCaption(value),
      prefixIcon: prefixIcon,
      suffixChild: suffixChild,
      validator: validator,
      style: style,
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
      return showUnkownValue ? value.toString() : '';
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
    final selectedValue = selectedValues.first;
    if (selectedValue != null) {
      onSelected!(selectedValue);
    }
  }

  Widget _buildDialog(BuildContext context, List<T> selectedValues) {
    return AlertDialog(
      contentPadding: const EdgeInsets.only(top: 16, bottom: 24),
      title: label == null ? null : Text('$label wählen'),
      content: YustSelectForm(
        optionValues: optionValues,
        optionLabels: optionLabels,
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
      ),
    );
  }
}
