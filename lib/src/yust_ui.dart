import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yust_ui/src/services/yust_location_service.dart';
import 'package:yust_ui/src/util/yust_image_helpers.dart';
import 'package:yust_ui/src/util/yust_ui_helpers.dart';
import 'package:yust_ui/src/util/yust_web_helpers/yust_web_helpers.dart';

import 'services/yust_alert_service.dart';
import 'util/yust_file_helpers.dart';
import 'util/yust_file_handler_manager.dart';

enum YustInputStyle {
  normal,
  outlineBorder,
}

typedef TapCallback = void Function();
typedef StringCallback = void Function(String?);
typedef DeleteCallback = FutureOr<void> Function();

class YustUi {
  static late YustAlertService alertService;
  static late YustLocationService locationService;
  static YustFileHandlerManager fileHandlerManager = YustFileHandlerManager();
  static late YustUiHelpers helpers;
  static YustFileHelpers fileHelpers = YustFileHelpers();
  static YustWebHelpers webHelpers = YustWebHelpers();
  static YustImageHelpers imageHelpers = YustImageHelpers();
  static String? storageUrl;
  static String? imagePlaceholderPath;
  static Function(
    String key, {
    String? localeOverride,
    List<String>? args,
    Map<String, String>? namedArgs,
    String? gender,
  }) trCallback = (key, {localeOverride, args, namedArgs, gender}) => key;
  static String? appRootFocusKey;

  static void initialize({
    String? storageUrl,
    String? imagePlaceholderPath,
    Function(
      String key, {
      String? localeOverride,
      List<String>? args,
      Map<String, String>? namedArgs,
      String? gender,
    })? trCallback,
    String? appRootFocusKey,
  }) {
    YustUi.storageUrl = storageUrl;
    YustUi.imagePlaceholderPath = imagePlaceholderPath;
    YustUi.trCallback = trCallback ?? YustUi.trCallback;
    YustUi.appRootFocusKey = appRootFocusKey;
  }

  static void setNavStateKey(GlobalKey<NavigatorState> navStateKey) {
    YustUi.alertService = YustAlertService(navStateKey);
    YustUi.helpers = YustUiHelpers(navStateKey);
    YustUi.locationService = YustLocationService(navStateKey);
  }
}
