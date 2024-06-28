import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as image_lib;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../yust_ui.dart';

class YustFileHelpers {
  YustFileHelpers();

  /// Under Firefox only one BroadcastStream can be used for the
  /// connectivity result. Therefore, use this stream instance
  static final connectivityStream =
      Connectivity().onConnectivityChanged.asBroadcastStream();

  /// Shares or downloads a file.
  /// On iOS and Android shows Share-Popup afterwards.
  /// For the browser starts the file download.
  /// Use either [file] or [data].
  Future<void> launchFileWithoutContext({
    required Size size,
    required RenderBox? box,
    required String name,
    File? file,
    Uint8List? data,
  }) async {
    if (kIsWeb) {
      if (data != null) {
        final base64data = base64Encode(data);
        final a = html.AnchorElement(
            href: 'data:application/octet-stream;base64,$base64data');
        a.download = name;
        a.click();
        a.remove();
      }
    } else {
      if (file == null && data != null) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/$name';
        file = await File(path).create();
        file.writeAsBytesSync(data);
      }
      if (file != null) {
        final buttonLocation = box!.localToGlobal(Offset.zero) & box.size;
        // Alternatively create a Location in the center of the Screen
        final centerLocation = Rect.fromLTWH(0, 0, size.width, size.height / 2);

        // If we don't have a useful button location, use the center position
        final sharePositionOrigin = buttonLocation.height >= size.height
            ? centerLocation
            : buttonLocation;
        // ignore: todo
        // TODO: use shareXFiles
        // ignore: deprecated_member_use
        await Share.shareFiles(
          [file.path],
          subject: name,
          sharePositionOrigin: sharePositionOrigin,
        );
      }
    }
  }

  /// Shares or downloads a file.
  /// On iOS and Android shows Share-Popup afterwards.
  /// For the browser starts the file download.
  /// Use either [file] or [data].
  Future<void> launchFile({
    required BuildContext context,
    required String name,
    File? file,
    Uint8List? data,
  }) async {
    final size = MediaQuery.of(context).size;
    // Get the Location of the widget (e.g. button), that called the method.
    final box = context.findRenderObject() as RenderBox?;
    await launchFileWithoutContext(
        size: size, box: box, name: name, file: file, data: data);
  }

  /// Downloads a file. On iOS and Android shows Share-Popup afterwards.
  /// For the browser starts the file download.
  Future<void> downloadAndLaunchFile(
      {required BuildContext context,
      required String url,
      required String name}) async {
    final size = MediaQuery.of(context).size;
    // Get the Location of the widget (e.g. button), that called the method.
    final box = context.findRenderObject() as RenderBox?;
    await EasyLoading.show(status: LocaleKeys.loadingFile.tr());
    try {
      if (kIsWeb) {
        final r = await http.get(
          Uri.parse(url),
        );
        final data = r.bodyBytes;
        await launchFileWithoutContext(
            size: size, box: box, name: name, data: data);
      } else {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/$name';
        await Dio().download(url, path);
        final file = File(path);
        await launchFileWithoutContext(
            size: size, box: box, name: name, file: file);
      }
      await EasyLoading.dismiss();
    } catch (e) {
      await EasyLoading.dismiss();
      await YustUi.alertService.showAlert(
          LocaleKeys.oops.tr(),
          LocaleKeys.alertCannotOpenFileWithError
              .tr(namedArgs: {'error': e.toString()}));
    }
  }

  bool isValidFileName(String filename) {
    final invalidChars = ['\\', '/', ':', '*', '?', '<', '>', '|'];

    return invalidChars.none((element) => filename.contains(element));
  }

  Future<Uint8List?> resizeImage(
      {required String name,
      required Uint8List bytes,
      int maxWidth = 1024}) async {
    var originalImage = image_lib.decodeNamedImage(name, bytes)!;
    image_lib.Image newImage = originalImage;
    if (originalImage.width > originalImage.height &&
        originalImage.width > maxWidth) {
      newImage = image_lib.copyResize(originalImage, width: maxWidth);
    } else if (originalImage.height > originalImage.width &&
        originalImage.height > maxWidth) {
      newImage = image_lib.copyResize(originalImage, height: maxWidth);
    }

    if (originalImage.hasAlpha) {
      originalImage = _replaceTransparentBackground(originalImage);
    }

    name = name.replaceAll(RegExp(r'\.[^.]+$'), '.jpeg');

    final exif = originalImage.exif;

    // Orientation is baked into the image, so we can set it to no rotation
    exif.imageIfd.orientation = 1;
    // Size is changed, so we need to update the resolution
    exif.imageIfd.xResolution = newImage.exif.imageIfd.xResolution;
    exif.imageIfd.yResolution = newImage.exif.imageIfd.yResolution;
    exif.imageIfd.resolutionUnit = newImage.exif.imageIfd.resolutionUnit;
    exif.imageIfd.imageHeight = newImage.exif.imageIfd.imageHeight;
    exif.imageIfd.imageWidth = newImage.exif.imageIfd.imageWidth;

    newImage.exif = exif;

    return image_lib.encodeNamedImage(name, newImage);
  }

  image_lib.Image _replaceTransparentBackground(image_lib.Image image) {
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        image.setPixel(
            x,
            y,
            image_lib.ColorRgba8(
                min(255, (pixel.r + 255 - pixel.a).toInt()),
                min(255, (pixel.g + 255 - pixel.a).toInt()),
                min(255, (pixel.b + 255 - pixel.a).toInt()),
                255));
      }
    }
    return image;
  }
}
