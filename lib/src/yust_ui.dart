import 'package:flutter/material.dart';
import 'package:yust_ui/src/util/yust_ui_helpers.dart';

import 'services/yust_alert_service.dart';
import 'util/yust_file_helpers.dart';
import 'util/yust_file_handler_manager.dart';

enum YustInputStyle {
  normal,
  outlineBorder,
}

typedef TapCallback = void Function();
typedef StringCallback = void Function(String?);
typedef DeleteCallback = Future<void> Function();

class YustUi {
  static late YustAlertService alertService;
  static YustFileHandlerManager fileHandlerManager = YustFileHandlerManager();
  static late YustUiHelpers helpers;
  static YustFileHelpers fileHelpers = YustFileHelpers();
  static String? storageUrl;
  static String? imagePlaceholderPath;

  static void initialize({
    String? storageUrl,
    String? imagePlaceholderPath,
  }) {
    YustUi.storageUrl = storageUrl;
    YustUi.imagePlaceholderPath = imagePlaceholderPath;
  }

  static void setNavStateKey(GlobalKey<NavigatorState> navStateKey) {
    YustUi.alertService = YustAlertService(navStateKey);
    YustUi.helpers = YustUiHelpers(navStateKey);
  }
}
