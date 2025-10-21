import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/yust_web_helpers/yust_web_helpers_interface.dart';

class YustWebHelpers implements YustWebHelpersInterface {
  @override
  void replaceUrl(String path) => throw UnimplementedError();

  @override
  void downloadData(String name, Uint8List? data) => throw UnimplementedError();

  @override
  Future<Uint8List> resizeImage({
    required String name,
    required Uint8List bytes,
    required int maxWidth,
    required int quality,
  }) => throw UnimplementedError();

  @override
  void setFavicon(YustImage? image) => throw UnimplementedError();
}
