import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import '../yust_ui.dart';
import 'yust_input_tile.dart';

typedef DateTimeCallback = void Function(DateTime?);

class YustDatePicker extends StatelessWidget {
  final String? label;
  final DateTime? value;
  final DateTime? firstDate;
  final DateTime? lastDate;

  final DateTimeCallback? onChanged;
  final bool hideClearButton;
  final YustInputStyle style;
  final Widget? prefixIcon;
  final bool readOnly;

  const YustDatePicker({
    super.key,
    this.label,
    this.value,
    this.firstDate,
    this.lastDate,
    this.onChanged,
    this.hideClearButton = false,
    this.style = YustInputStyle.normal,
    this.prefixIcon,
    this.readOnly = false,
  });

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
    YustUi.helpers.unfocusCurrent();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: Yust.helpers.utcToLocal(_determineInitialDate()),
      firstDate: (firstDate != null)
          ? Yust.helpers.utcToLocal(firstDate!)
          : DateTime.utc(1900),
      lastDate: (lastDate != null)
          ? Yust.helpers.utcToLocal(lastDate!)
          : DateTime.utc(2100),
      locale: const Locale('de', 'DE'),
      currentDate: Yust.helpers.localNow(),
    );
    if (selectedDate != null) {
      final newDateTime = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      );
      onChanged!(Yust.helpers.localToUtc(newDateTime));
    }
  }

  DateTime _determineInitialDate() {
    if (value != null) {
      if (firstDate != null && value!.isBefore(firstDate!)) {
        return firstDate!;
      }
      if (lastDate != null && value!.isAfter(lastDate!)) {
        return lastDate!;
      }
      return value!;
    } else {
      final today = Yust.helpers.utcNow(
          hour: 0, minute: 0, second: 0, microsecond: 0, millisecond: 0);
      if (firstDate != null && firstDate!.isAfter(today)) {
        return firstDate!;
      }
      if (lastDate != null && lastDate!.isBefore(today)) {
        return lastDate!;
      }
      return today;
    }
  }
}
