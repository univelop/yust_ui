import 'package:firebase_storage/firebase_storage.dart';
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
  static YustAlertService alertService = YustAlertService();
  static YustFileService fileService = YustFileService();
  static YustFileHandlerManager fileHandlerManager = YustFileHandlerManager();
  static YustUiHelpers helpers = YustUiHelpers();
  static String? storageUrl;
  static String? imagePlaceholderPath;

  static Future<void> initializeMocked() async {
    YustUi.fileService = YustFileService.mocked();
  }

  static Future<void> initialize({
    String? storageUrl,
    String? imagePlaceholderPath,
  }) async {
    YustUi.storageUrl = storageUrl;
    YustUi.imagePlaceholderPath = imagePlaceholderPath;
    FirebaseStorage.instance.setMaxUploadRetryTime(Duration(seconds: 20));
  }
}
