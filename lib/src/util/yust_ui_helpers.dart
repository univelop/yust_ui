import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:keyboard_name/keyboard_name.dart';
import 'package:yust/yust.dart';

class YustUiHelpers {
  final GlobalKey<NavigatorState> navStateKey;
  YustUiHelpers(this.navStateKey);

  /// Does unfocus the current focus node.
  void unfocusCurrent() {
    final context = navStateKey.currentContext;
    if (context == null) return;
    final currentFocus = Focus.of(context);
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

  /// Does this device use the Samsung keyboard?
  Future<bool> usesSamsungKeyboard() async =>
      Platform.isAndroid &&
      (await KeyboardName.getVendorName ?? '')
          .toLowerCase()
          .contains('samsung');

  /// Determine the current position of the device.
  ///
  /// When the location services are not enabled or permissions
  /// are denied the `Future` will return an error.
  static Future<Position> getPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      throw YustException('Location services are disabled');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        throw YustException('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      throw YustException('Location permissions are permanently denied');
    }

    // When we reach here, permissions are granted and we can
    // continue accessing the position of the device.
    return await Geolocator.getCurrentPosition();
  }
}
