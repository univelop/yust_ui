import 'package:flutter/material.dart';

import '../yust_ui.dart';
import 'yust_input_tile.dart';

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

    var selectedValue = await showDialog<T>(
        context: context,
        builder: (BuildContext context) {
          return SimpleDialog(
            title: (label == null) ? null : Text('$label'),
            children: optionValues.map((optionValue) {
              return SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(context, optionValue);
                },
                child: Text(_valueCaption(optionValue)),
              );
            }).toList(),
          );
        });
    if (selectedValue != null) {
      onSelected!(selectedValue);
    }
  }
}
