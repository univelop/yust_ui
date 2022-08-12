import 'package:flutter/material.dart';

import '../util/yust_ui_helpers.dart';
import 'package:collection/collection.dart';
import '../yust_ui.dart';
import 'yust_input_tile.dart';

class YustSelectMultiple<T> extends StatelessWidget {
  final String? label;
  final List<T> values;
  final List<T> optionValues;
  final List<String> optionLabels;
  final void Function(List<T>)? onSelected;
  final DeleteCallback? onDelete;
  final YustInputStyle style;
  final Widget? prefixIcon;
  final Widget? suffixChild;
  final bool readOnly;

  const YustSelectMultiple({
    Key? key,
    this.label,
    required this.values,
    required this.optionValues,
    required this.optionLabels,
    this.onSelected,
    this.onDelete,
    this.style = YustInputStyle.normal,
    this.prefixIcon,
    this.suffixChild,
    this.readOnly = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return YustInputTile(
      label: label ?? '',
      text: _valueCaption(values),
      prefixIcon: prefixIcon,
      suffixChild: suffixChild,
      style: style,
      onTap:
          (onSelected == null || readOnly) ? null : () => _selectValue(context),
      onDelete: readOnly ? null : onDelete,
    );
  }

  String _valueCaption(List<T> values) {
    final validEntryIndexes = values
        .where((value) => optionValues.contains(value))
        .map((value) => optionValues.indexOf(value));

    return validEntryIndexes
        .map((optionIndex) => optionLabels[optionIndex])
        .toList()
        .join(", ");
  }

  void _selectValue(BuildContext context) async {
    YustUi.helpers.unfocusCurrent(context);
    if (onSelected == null) return;

    final selectedValues = values.toSet();

    await showDialog<List<T>>(
        context: context,
        builder: (BuildContext context) {
          return SimpleDialog(
            title: (label == null) ? null : Text('$label wählen'),
            children: [
              ...optionValues
                  .mapIndexed((int index, T optionValue) => StatefulBuilder(
                        builder: (_, StateSetter setState) => CheckboxListTile(
                            title: Text(
                                optionLabels[index]), // Displays the option
                            value: selectedValues.contains(
                                optionValue), // Displays checked or unchecked value
                            controlAffinity: ListTileControlAffinity.platform,
                            onChanged: (value) => setState(() =>
                                (value ?? false)
                                    ? selectedValues.add(optionValue)
                                    : selectedValues.remove(optionValue))),
                      ))
                  .toList(),
              Align(
                  alignment: Alignment.center,
                  child: ElevatedButton(
                      style: const ButtonStyle(
                          visualDensity: VisualDensity.comfortable),
                      child: const Text('OK'),
                      onPressed: () {
                        // Close the Dialog & return selectedItems
                        Navigator.pop(context);
                      }))
            ],
          );
        });

    onSelected!(selectedValues.toList());
  }
}
