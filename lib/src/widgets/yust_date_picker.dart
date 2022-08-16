import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import '../yust_ui.dart';
import 'yust_input_tile.dart';

typedef DateTimeCallback = void Function(DateTime?);

class YustDatePicker extends StatelessWidget {
  final String? label;
  final DateTime? value;

  final DateTimeCallback? onChanged;
  final bool hideClearButton;
  final YustInputStyle style;
  final Widget? prefixIcon;
  final bool readOnly;

  YustDatePicker({
    Key? key,
    this.label,
    this.value,
    this.onChanged,
    this.hideClearButton = false,
    this.style = YustInputStyle.normal,
    this.prefixIcon,
    this.readOnly = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return YustInputTile(
      label: label ?? '',
      text: Yust.helpers.formatDate(value),
      style: style,
      prefixIcon: prefixIcon,
      onTap: (onChanged == null || readOnly) ? null : () => pickDate(context),
      onDelete: (onChanged == null || hideClearButton || readOnly)
          ? null
          : () async {
              onChanged!(null);
            },
    );
  }

  void pickDate(BuildContext context) async {
    YustUi.helpers.unfocusCurrent(context);
    var dateTime = value;
    if (dateTime == null) {
      final now = DateTime.now();
      dateTime = DateTime(now.year, now.month, now.day, 0, 0, 0, 0, 0);
    }
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: dateTime,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      locale: Locale('de', 'DE'),
    );
    if (selectedDate != null) {
      dateTime = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          dateTime.hour,
          dateTime.minute,
          dateTime.second,
          dateTime.millisecond,
          dateTime.microsecond);
      onChanged!(dateTime);
    }
  }
}
