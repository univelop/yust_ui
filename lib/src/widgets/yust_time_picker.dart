import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../yust_ui.dart';
import 'yust_date_picker.dart';

class YustTimePicker extends StatefulWidget {
  final String? label;
  final DateTime? value;
  final DateTimeCallback? onChanged;
  final void Function()? onEditingComplete;
  final bool hideClearButton;
  final YustInputStyle style;
  final Widget? prefixIcon;
  final FocusNode? focusNode;
  final bool autofocus;
  final String popUpTitle;
  final bool readOnly;

  YustTimePicker({
    super.key,
    this.label,
    this.value,
    this.onChanged,
    this.onEditingComplete,
    this.hideClearButton = false,
    this.style = YustInputStyle.normal,
    this.prefixIcon,
    this.focusNode,
    this.autofocus = false,
    String? popUpTitle,
    this.readOnly = false,
  }) : popUpTitle = popUpTitle ?? LocaleKeys.selectTime.tr();

  @override
  State<YustTimePicker> createState() => _YustTimePickerState();
}

class _YustTimePickerState extends State<YustTimePicker> {
  TextEditingController? _controller;
  MaskTextInputFormatter? _maskFormatter;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: Yust.helpers.formatTime(widget.value));
    _maskFormatter = MaskTextInputFormatter(
      mask: 'H#:M#',
      filter: {
        '#': RegExp(r'[0-9]'),
        'H': RegExp(r'[0-2]'),
        'M': RegExp(r'[0-5]')
      },
      initialText: Yust.helpers.formatTime(widget.value),
    );
  }

  @override
  void dispose() {
    _controller!.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.value == null) {
      _controller!.text = '';
    }
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            decoration: InputDecoration(
              labelText: widget.label,
              contentPadding: const EdgeInsets.all(20.0),
              border: widget.style == YustInputStyle.outlineBorder
                  ? const OutlineInputBorder()
                  : null,
              prefixIcon: widget.prefixIcon,
              suffixIcon: _buildTrailing(context),
              hintText: 'HH:MM',
            ),
            controller: _controller,
            inputFormatters: [_maskFormatter!],
            textInputAction: TextInputAction.next,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onChanged: widget.onChanged == null
                ? null
                : (value) => _setTimeString(value),
            onEditingComplete: widget.onEditingComplete,
            readOnly: widget.readOnly,
            keyboardType: kIsWeb
                ? null
                : const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
          ),
        ),
        if (_controller!.text != '' &&
            !widget.hideClearButton &&
            !widget.readOnly)
          IconButton(
              onPressed: widget.onChanged == null ? null : () => _setTime(null),
              icon: Icon(
                Icons.delete,
                color: Theme.of(context).primaryColor,
              )),
      ],
    );
  }

  /// build the clock- / x-icon
  Widget _buildTrailing(BuildContext context) {
    return (_controller!.text == '')
        ? IconButton(
            icon: const Icon(Icons.access_time),
            onPressed: widget.onChanged == null
                ? null
                : () => _pickTime(context, widget.popUpTitle),
          )
        : const SizedBox();
  }

  void _pickTime(BuildContext context, String title) async {
    YustUi.helpers.unfocusCurrent();
    final value = widget.value ?? DateTime.utc(1970);

    final localValue = Yust.helpers.utcToLocal(value);
    final dateTimeUtc = Yust.helpers.localNow(
        year: localValue.year,
        month: localValue.month,
        day: localValue.day,
        second: 0,
        microsecond: 0,
        millisecond: 0);
    final dateTime = Yust.helpers.utcToLocal(dateTimeUtc);
    final initialTime = TimeOfDay.fromDateTime(dateTime);
    final selectedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      cancelText: LocaleKeys.cancel.tr(),
      confirmText: LocaleKeys.ok.tr(),
      helpText: title,
    );
    if (selectedTime != null) {
      final changeDateTime = DateTime(dateTime.year, dateTime.month,
          dateTime.day, selectedTime.hour, selectedTime.minute, 0, 0, 0);
      _setTime(Yust.helpers.tryLocalToUtc(changeDateTime));
    }
  }

  void _setTimeString(String txt) {
    if (txt.length == 5) {
      var time = int.tryParse(_maskFormatter!.getUnmaskedText())!;
      if (time == 2400) {
        time == 0;
      }
      var hour = time ~/ 100 >= 24 ? 0 : time ~/ 100;
      var minute = time % 100 >= 60 ? 0 : time % 100;
      final value = widget.value ?? DateTime(1970);
      var dateTime =
          DateTime(value.year, value.month, value.day, hour, minute, 0, 0, 0);
      widget.onChanged!(Yust.helpers.localToUtc(dateTime));
    }
  }

  // Make sure the [dateTime] is in utc
  void _setTime(DateTime? dateTime) {
    setState(() {
      _maskFormatter!.clear();
      _controller!.text = Yust.helpers.formatTime(dateTime);
    });
    widget.onChanged!(dateTime);
  }
}
