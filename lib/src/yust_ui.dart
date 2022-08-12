import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:yust_ui/src/util/yust_ui_helpers.dart';

import 'services/yust_alert_service.dart';
import 'services/yust_file_service.dart';
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
  // static YustAlertService alertService(context) => YustAlertService(context);
  static YustFileService fileService = YustFileService();
  static YustFileHandlerManager fileHandlerManager = YustFileHandlerManager();
  static late YustUiHelpers helpers;
  static String? storageUrl;
  static String? imagePlaceholderPath;

  static void initializeMocked() {
    YustUi.fileService = YustFileService.mocked();
  }

  static void initialize({
    String? storageUrl,
    String? imagePlaceholderPath,
  }) {
    YustUi.storageUrl = storageUrl;
    YustUi.imagePlaceholderPath = imagePlaceholderPath;
    FirebaseStorage.instance.setMaxUploadRetryTime(Duration(seconds: 20));
  }

  static void initContext(BuildContext context) {
    YustUi.alertService = YustAlertService(context);
    YustUi.helpers = YustUiHelpers(context);
  }
}
