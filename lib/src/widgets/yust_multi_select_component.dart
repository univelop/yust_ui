import 'package:flutter/material.dart';

import 'package:collection/collection.dart';

class YustMultiSelectComponent<T> extends StatelessWidget {
  final List<T> optionValues;
  final List<String> optionLabels;
  final List<T>? selectedValues;
  const YustMultiSelectComponent({
    Key? key,
    required this.optionValues,
    required this.optionLabels,
    List<T>? selectedValues,
  })  : selectedValues = selectedValues ?? const [],
        super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ...optionValues
            .mapIndexed((int index, T optionValue) => StatefulBuilder(
                  builder: (_, StateSetter setState) => CheckboxListTile(
                      title: Text(optionLabels[index]), // Displays the option
                      value: selectedValues!.contains(
                          optionValue), // Displays checked or unchecked value
                      controlAffinity: ListTileControlAffinity.platform,
                      onChanged: (value) => setState(() => (value ?? false)
                          ? selectedValues!.add(optionValue)
                          : selectedValues!.remove(optionValue))),
                ))
            .toList(),
      ],
    );
  }
}
