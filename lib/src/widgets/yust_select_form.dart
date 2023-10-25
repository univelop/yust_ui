import 'dart:math';

import 'package:flutter/material.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/widgets/yust_list_tile.dart';

enum YustSelectFormType {
  single, // single select with indicator
  multiple, // select multiple
  singleWithoutIndicator, // single select without indicator (can be used when the form disappears right after selection ex. in YustSelect)
}

class YustSelectForm<T> extends StatelessWidget {
  final String? label;
  final List<T> optionValues;
  final List<String> optionLabels;
  final List<T> selectedValues;
  final bool disabled;
  final YustSelectFormType formType;
  final String noOptionsText;
  final Function? onChanged;
  final bool divider;
  final bool allowSearch;

  static const maxVisibleOptions = 10;

  YustSelectForm({
    Key? key,
    this.label,
    required this.optionValues,
    required this.optionLabels,
    List<T>? selectedValues,
    this.noOptionsText = 'Keine Optionen vorhanden',
    this.disabled = false,
    this.formType = YustSelectFormType.multiple,
    this.onChanged,
    this.divider = true,
    this.allowSearch = true,
  })  : selectedValues = selectedValues ?? [],
        super(key: key);

  double get optionHeight {
    switch (formType) {
      case YustSelectFormType.single:
        return 48.0;
      case YustSelectFormType.multiple:
        return 48.0;
      case YustSelectFormType.singleWithoutIndicator:
        return 36.0;
      default:
        throw Exception('Unknown form type');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (optionValues.isEmpty) {
      return YustListTile(
        label: noOptionsText,
        center: true,
      );
    }

    String searchValue = '';

    return StatefulBuilder(
      builder: (_, setState) {
        final foundValues = _searchOptions(searchValue);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (label != null)
              YustListTile(
                label: label,
                divider: false,
              ),
            if (allowSearch && optionValues.length > maxVisibleOptions)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                child: TextFormField(
                  initialValue: searchValue,
                  decoration: InputDecoration(
                    hintText:
                        label == null ? 'Suche...' : 'Durchsuche $label...',
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    setState(
                      () {
                        searchValue = value;
                      },
                    );
                  },
                ),
              ),
            SizedBox(
              height:
                  min(maxVisibleOptions, optionValues.length) * optionHeight,
              width: 300.0,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: foundValues.length,
                itemBuilder: (context, index) {
                  switch (formType) {
                    case YustSelectFormType.single:
                      return _listItemSingle(foundValues, index, setState);
                    case YustSelectFormType.multiple:
                      return _listItemMultiple(foundValues, index, setState);
                    case YustSelectFormType.singleWithoutIndicator:
                      return _listItemSingleNoIndicator(
                          foundValues, index, setState);
                    default:
                      throw Exception('Unknown form type');
                  }
                },
              ),
            ),
            if (divider)
              const Divider(height: 1.0, thickness: 1.0, color: Colors.grey),
          ],
        );
      },
    );
  }

  List<T> _searchOptions(String searchValue) => Yust.helpers
      .searchString(strings: optionLabels, searchString: searchValue)
      .map((index) => optionValues[index])
      .toList();

  Widget _listItemMultiple(
      List<T> foundValues, int index, StateSetter setState) {
    return CheckboxListTile(
      enabled: !disabled,
      title: Text(_getOptionLabel(foundValues[index])),
      value: selectedValues.contains(foundValues[index]),
      controlAffinity: ListTileControlAffinity.platform,
      onChanged: (value) => setState(() {
        (value ?? false)
            ? _addOption(foundValues[index])
            : selectedValues.remove(foundValues[index]);
        onChanged?.call();
      }),
    );
  }

  Widget _listItemSingle(List<T> foundValues, int index, StateSetter setState) {
    return RadioListTile(
      title: Text(_getOptionLabel(foundValues[index])),
      value: foundValues[index],
      groupValue: selectedValues.firstOrNull,
      controlAffinity: ListTileControlAffinity.platform,
      onChanged: (value) => setState(() {
        if (value == null) return;
        selectedValues.clear();
        selectedValues.add(value);
        onChanged?.call();
      }),
    );
  }

  Widget _listItemSingleNoIndicator(
      List<T> foundValues, int index, StateSetter setState) {
    return SimpleDialogOption(
      onPressed: () {
        final value = foundValues[index];
        selectedValues.clear();
        selectedValues.add(value);
        onChanged?.call();
      },
      child: Text(_getOptionLabel(foundValues[index])),
    );
  }

  String _getOptionLabel(T option) {
    final index = optionValues.indexOf(option);
    if (index == -1) {
      return '';
    }
    return optionLabels[index];
  }

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
