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

class YustSelectForm<T> extends StatefulWidget {
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

  @override
  State<YustSelectForm<T>> createState() => _YustSelectFormState<T>();
}

class _YustSelectFormState<T> extends State<YustSelectForm<T>>
    with AutomaticKeepAliveClientMixin {
  final int _maxOptionCountBeforeSearch = 10;
  String searchValue = '';
  late final ScrollController controller = ScrollController();

  bool get showSearchBar =>
      widget.allowSearch &&
      widget.optionValues.length > _maxOptionCountBeforeSearch;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.optionListConstraints.maxHeight == double.infinity) {
      throw Exception(LocaleKeys.exceptionOptionListConstraints.tr());
    }

    if (widget.optionValues.isEmpty) {
      return YustListTile(
        label: widget.noOptionsText,
        center: true,
      );
    }

    final foundValues = _searchOptions(searchValue);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null)
          YustListTile(
            label: widget.label,
            divider: false,
          ),
        if (showSearchBar)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
            child: TextFormField(
              initialValue: searchValue,
              autofocus: widget.autofocus,
              decoration: InputDecoration(
                icon: const Icon(Icons.search),
                iconColor: Colors.grey,
                hintText: widget.label == null
                    ? LocaleKeys.searching.tr()
                    : LocaleKeys.searchingWithLabel
                        .tr(namedArgs: {'label': widget.label ?? ''}),
                border: InputBorder.none,
              ),
              onChanged: (value) {
                setState(() {
                  searchValue = value;
                });
              },
            ),
          ),
        Container(
          constraints: widget.optionListConstraints,
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
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
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
                      if (widget.allowSearch && foundValues.isEmpty)
                        ListTile(
                          title: Center(
                              child: Text(LocaleKeys.noOptionsFound.tr())),
                          titleAlignment: ListTileTitleAlignment.center,
                        ),
                      ...foundValues.asMap().entries.map((entry) {
                        final index = entry.key;
                        switch (widget.formType) {
                          case YustSelectFormType.single:
                            return _listItemSingle(foundValues, index);
                          case YustSelectFormType.multiple:
                            return _listItemMultiple(foundValues, index);
                          case YustSelectFormType.singleWithoutIndicator:
                            return _listItemSingleNoIndicator(
                                foundValues, index);
                          default:
                            throw Exception('Unknown form type');
                        }
                      }),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.divider)
          const Divider(height: 1.0, thickness: 1.0, color: Colors.grey),
      ],
    );
  }

  List<T> _searchOptions(String searchValue) => Yust.helpers
      .searchString(strings: widget.optionLabels, searchString: searchValue)
      .map((index) => widget.optionValues[index])
      .toList();

  Widget _listItemMultiple(List<T> foundValues, int index) {
    return CheckboxListTile(
      enabled: !widget.disabled,
      title: Text(_getOptionLabel(foundValues[index])),
      value: widget.selectedValues.contains(foundValues[index]),
      controlAffinity: ListTileControlAffinity.platform,
      onChanged: (value) {
        setState(() {
          (value ?? false)
              ? _addOption(foundValues[index])
              : widget.selectedValues.remove(foundValues[index]);
          widget.onChanged?.call();
        });
      },
    );
  }

  Widget _listItemSingle(List<T> foundValues, int index) {
    return RadioListTile(
      title: Text(_getOptionLabel(foundValues[index])),
      value: foundValues[index],
      groupValue: widget.selectedValues.firstOrNull,
      controlAffinity: ListTileControlAffinity.platform,
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          widget.selectedValues.clear();
          widget.selectedValues.add(value);
          widget.onChanged?.call();
        });
      },
    );
  }

  Widget _listItemSingleNoIndicator(List<T> foundValues, int index) {
    return ListTile(
      title: Text(_getOptionLabel(foundValues[index])),
      onTap: () {
        setState(() {
          final value = foundValues[index];
          widget.selectedValues.clear();
          widget.selectedValues.add(value);
          widget.onChanged?.call();
        });
      },
    );
  }

  String _getOptionLabel(T option) {
    final index = widget.optionValues.indexOf(option);
    if (index == -1) {
      return '';
    }
    return widget.optionLabels[index];
  }

  void _addOption(T option) {
    Map<T, int> optionIndices = {};
    for (int i = 0; i < widget.optionValues.length; i++) {
      optionIndices[widget.optionValues[i]] = i;
    }
    widget.selectedValues.add(option);
    widget.selectedValues
        .sort((a, b) => optionIndices[a]!.compareTo(optionIndices[b]!));
  }

  @override
  bool get wantKeepAlive => true;
}
