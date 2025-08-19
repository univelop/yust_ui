import 'package:flutter/foundation.dart';

abstract class YustWebHelpersInterface {
  /// Replaces the current URL with the given path.
  /// NOTE: This will not trigger a re-render and should NOT
  /// be used to navigate to a new page.
  void replaceUrl(String path);

  /// Downloads a file via creating and clicking an anchor element.
  /// [name] is the name of the file.
  /// [data] is the data to be downloaded.
  void downloadData(String name, Uint8List? data);

  /// Resizes an image.
  /// [name] is the name of the image.
  /// [bytes] is the bytes of the image.
  /// [maxWidth] is the maximum width of the image.
  /// [quality] is the quality of the image.
  Future<Uint8List> resizeImage({
    required String name,
    required Uint8List bytes,
    required int maxWidth,
    required int quality,
  });
}
