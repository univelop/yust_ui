import 'package:flutter/material.dart';
import 'package:yust_ui/src/widgets/yust_select_form.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
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
  final ButtonStyle buttonStyle;

  const YustSelectMultiple({
    super.key,
    this.label,
    required this.values,
    required this.optionValues,
    required this.optionLabels,
    this.onSelected,
    this.onDelete,
    this.style = YustInputStyle.normal,
    this.buttonStyle = const ButtonStyle(),
    this.prefixIcon,
    this.suffixChild,
    this.readOnly = false,
  });

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
        .join(', ');
  }

  void _selectValue(BuildContext context) async {
    YustUi.helpers.unfocusCurrent();
    if (onSelected == null) return;
    final selectedValues = values.toSet().toList(); //remove duplicates
    await showDialog<List<T>>(
      context: context,
      builder: (BuildContext context) {
        return _buildDialog(selectedValues, context);
      },
    );

    onSelected!(selectedValues);
  }

  Widget _buildDialog(List<dynamic> selectedValues, BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.only(top: 16, bottom: 24),
      title: (label == null)
          ? null
          : Text(LocaleKeys.selectValue.tr(namedArgs: {'label': label ?? ''})),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          YustSelectForm(
            optionValues: optionValues,
            optionLabels: optionLabels,
            selectedValues: selectedValues,
            optionListConstraints: const BoxConstraints(
              maxHeight: 400.0,
              maxWidth: 400.0,
            ),
            divider: false,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Align(
              alignment: Alignment.center,
              child: ElevatedButton(
                style: buttonStyle,
                child: Text(LocaleKeys.ok.tr()),
                onPressed: () {
                  // Close the Dialog & return selectedItems
                  Navigator.pop(context);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
