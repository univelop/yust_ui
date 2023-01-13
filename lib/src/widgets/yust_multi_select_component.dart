import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:yust_ui/src/widgets/yust_list_tile.dart';

class YustMultiSelectComponent<T> extends StatelessWidget {
  final List<T> optionValues;
  final List<String> optionLabels;
  final List<T> selectedValues;
  final bool disabled;
  final bool singleSelect;
  final String noOptionsText;
  YustMultiSelectComponent({
    Key? key,
    required this.optionValues,
    required this.optionLabels,
    List<T>? selectedValues,
    this.noOptionsText = 'Keine Optionen vorhanden',
    this.disabled = false,
    this.singleSelect = false,
  })  : selectedValues = selectedValues ?? [],
        super(key: key);

  @override
  Widget build(BuildContext context) {
    if (optionValues.isEmpty) {
      return YustListTile(
        label: noOptionsText,
        center: true,
      );
    }
    return StatefulBuilder(
      builder: (_, StateSetter setState) => Column(
        children: [
          ...optionValues
              .mapIndexed(
                (int index, T optionValue) => CheckboxListTile(
                  enabled: !isCheckBoxDisabled(optionValue),
                  title: Text(optionLabels[index]),
                  value: selectedValues.contains(optionValue),
                  controlAffinity: ListTileControlAffinity.platform,
                  onChanged: (value) => setState(() {
                    (value ?? false)
                        ? selectedValues.add(optionValue)
                        : selectedValues.remove(optionValue);
                  }),
                ),
              )
              .toList(),
        ],
      ),
    );
  }

  bool isCheckBoxDisabled(T value) =>
      disabled ||
      (singleSelect &&
          (!selectedValues.contains(value) && selectedValues.isNotEmpty));
}
