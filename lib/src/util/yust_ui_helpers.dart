import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class YustUiHelpers {
  final BuildContext context;
  YustUiHelpers(this.context);

  /// Under Firefox only one BroadcastStream can be used for the
  /// connectivity result. Therefore, use this stream instance
  final connectivityStream =
      Connectivity().onConnectivityChanged.asBroadcastStream();

  /// Does unfocus the current focus node.
  void unfocusCurrent() {
    final currentFocus = FocusScope.of(context);
    if (!currentFocus.hasPrimaryFocus) {
      currentFocus.unfocus();
    }
  }

  /// Does not return null.
  String formatDate(DateTime? dateTime, {String? format}) {
    if (dateTime == null) return '';

    var formatter = DateFormat(format ?? 'dd.MM.yyyy');
    return formatter.format(dateTime.toLocal());
  }

  /// Does not return null.
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
