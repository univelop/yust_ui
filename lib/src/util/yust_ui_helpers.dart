import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class YustUiHelpers {
  final GlobalKey<NavigatorState> navStateKey;
  YustUiHelpers(this.navStateKey);

  /// Does unfocus the current focus node.
  void unfocusCurrent() {
    final context = navStateKey.currentContext;
    if (context == null) return;
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus) {
      currentFocus.unfocus();
    }
  }

  /// Does not return null.
  @Deprecated('Use YustHelper.formatDate instead')
  String formatDate(DateTime? dateTime, {String? format}) {
    if (dateTime == null) return '';

    var formatter = DateFormat(format ?? 'dd.MM.yyyy');
    return formatter.format(dateTime.toLocal());
  }

  /// Does not return null.
  @Deprecated('Use YustHelper.formatTime instead')
  String formatTime(DateTime? dateTime, {String? format}) {
    if (dateTime == null) return '';

    var formatter = DateFormat(format ?? 'HH:mm');
    return formatter.format(dateTime.toLocal());
  }

  /// Creates a string formatted just as the [YustDoc.createdAt] property is.
  String toStandardDateTimeString(DateTime dateTime) =>
      dateTime.toIso8601String();

  /// Returns null if the string cannot be parsed.
  DateTime? fromStandardDateTimeString(String dateTimeString) =>
      DateTime.tryParse(dateTimeString);
}
