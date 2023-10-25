import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:yust_ui/src/widgets/yust_list_tile.dart';

class YustSelectForm<T> extends StatelessWidget {
  final String? label;
  final List<T> optionValues;
  final List<String> optionLabels;
  final List<T> selectedValues;
  final bool disabled;
  final bool singleSelect;
  final String noOptionsText;
  final Function? onChanged;
  final bool divider;

  YustSelectForm({
    Key? key,
    this.label,
    required this.optionValues,
    required this.optionLabels,
    List<T>? selectedValues,
    this.noOptionsText = 'Keine Optionen vorhanden',
    this.disabled = false,
    this.singleSelect = false,
    this.onChanged,
    this.divider = true,
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
          if (label != null)
            YustListTile(
              label: label,
              divider: false,
            ),
          ...optionValues
              .mapIndexed(
                (int index, T optionValue) => CheckboxListTile(
                  enabled: !isCheckBoxDisabled(optionValue),
                  title: Text(optionLabels[index]),
                  value: selectedValues.contains(optionValue),
                  controlAffinity: ListTileControlAffinity.platform,
                  onChanged: (value) => setState(() {
                    (value ?? false)
                        ? _addOption(optionValue)
                        : selectedValues.remove(optionValue);
                    onChanged?.call();
                  }),
                ),
              )
              .toList(),
          if (divider)
            const Divider(height: 1.0, thickness: 1.0, color: Colors.grey),
        ],
      ),
    );
  }

  bool isCheckBoxDisabled(T value) =>
      disabled ||
      (singleSelect &&
          (!selectedValues.contains(value) && selectedValues.isNotEmpty));

  void _addOption(T option) {
    Map<T, int> optionIndizes = {};
    for (int i = 0; i < optionValues.length; i++) {
      optionIndizes[optionValues[i]] = i;
    }
    selectedValues.add(option);
    selectedValues
        .sort((a, b) => optionIndizes[a]!.compareTo(optionIndizes[b]!));
  }
}
