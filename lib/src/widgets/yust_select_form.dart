import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/widgets/yust_list_tile.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';

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
  final BoxConstraints optionListConstraints;
  final bool autofocus;

  YustSelectForm({
    super.key,
    this.label,
    required this.optionValues,
    required this.optionLabels,
    List<T>? selectedValues,
    String? noOptionsText,
    this.disabled = false,
    this.formType = YustSelectFormType.multiple,
    this.onChanged,
    this.divider = true,
    this.allowSearch = true,
    this.optionListConstraints = const BoxConstraints(maxHeight: 300.0),
    this.autofocus = false,
  })  : noOptionsText = noOptionsText ?? LocaleKeys.noOptions.tr(),
        selectedValues = selectedValues ?? [];

  final _maxOptionCountBeforeSearch = 10;

  get showSearchBar =>
      allowSearch && optionValues.length > _maxOptionCountBeforeSearch;

  @override
  Widget build(BuildContext context) {
    if (optionListConstraints.maxHeight == double.infinity) {
      throw Exception(LocaleKeys.exceptionOptionListConstraints.tr());
    }

    if (optionValues.isEmpty) {
      return YustListTile(
        label: noOptionsText,
        center: true,
      );
    }

    String searchValue = '';
    final controller = ScrollController();

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
            if (showSearchBar)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                child: TextFormField(
                  initialValue: searchValue,
                  autofocus: autofocus,
                  decoration: InputDecoration(
                    icon: const Icon(Icons.search),
                    iconColor: Colors.grey,
                    hintText: label == null
                        ? LocaleKeys.searching.tr()
                        : LocaleKeys.searchingWithLabel
                            .tr(namedArgs: {'label': label ?? ''}),
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
            Container(
              constraints: optionListConstraints,
              child: Scrollbar(
                controller: controller,
                thumbVisibility: true,
                child: SingleChildScrollView(
                    controller: controller,
                    child: FocusTraversalGroup(
                      policy: WidgetOrderTraversalPolicy(),
                      child: Focus(
                        skipTraversal: true,
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent) {
                            if (event.logicalKey ==
                                LogicalKeyboardKey.arrowDown) {
                              if (node.context != null) {
                                FocusScope.of(node.context!).nextFocus();
                              }
                              return KeyEventResult.handled;
                            } else if (event.logicalKey ==
                                LogicalKeyboardKey.arrowUp) {
                              if (node.context != null) {
                                FocusScope.of(node.context!).previousFocus();
                              }
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Column(
                          children: [
                            if (allowSearch && foundValues.isEmpty)
                              ListTile(
                                title: Center(
                                    child:
                                        Text(LocaleKeys.noOptionsFound.tr())),
                                titleAlignment: ListTileTitleAlignment.center,
                              ),
                            ...foundValues.map((value) {
                              switch (formType) {
                                case YustSelectFormType.single:
                                  return _listItemSingle(foundValues,
                                      foundValues.indexOf(value), setState);
                                case YustSelectFormType.multiple:
                                  return _listItemMultiple(foundValues,
                                      foundValues.indexOf(value), setState);
                                case YustSelectFormType.singleWithoutIndicator:
                                  return _listItemSingleNoIndicator(foundValues,
                                      foundValues.indexOf(value), setState);
                                default:
                                  throw Exception('Unknown form type');
                              }
                            }),
                          ],
                        ),
                      ),
                    )),
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
      autofocus: index == 0 && !showSearchBar,
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
      autofocus: index == 0 && !showSearchBar,
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
    return ListTile(
      autofocus: index == 0 && !showSearchBar,
      title: Text(_getOptionLabel(foundValues[index])),
      onTap: () => setState(() {
        final value = foundValues[index];
        selectedValues.clear();
        selectedValues.add(value);
        onChanged?.call();
      }),
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
