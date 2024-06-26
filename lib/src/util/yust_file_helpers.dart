import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:http/http.dart' as http;
import 'package:exif/exif.dart';
import 'package:image/image.dart' as image_lib;
import 'package:image/src/util/rational.dart';
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
    final invalidChars = ['\\', '/', ':', '*', '?', '"', '<', '>', '|'];

    return invalidChars.none((element) => filename.contains(element));
  }


Future<Uint8List?> resizeImage(
    {required String name, required Uint8List bytes, int maxWidth = 1024}) async {
  var image = image_lib.decodeNamedImage(name, bytes)!;
  if (image.width > image.height && image.width > maxWidth) {
    image = image_lib.copyResize(image, width: maxWidth);
  } else if (image.height > image.width && image.height > maxWidth) {
    image = image_lib.copyResize(image, height: maxWidth);
  }

  name = name.replaceAll(RegExp(r'\.[^.]+$'), '.jpeg');

  //Read EXIF-data
  final data = await readExifFromBytes(bytes);
  final exifData = image_lib.ExifData();

  for (final entry in data.entries) {
    dynamic newValue;
    switch (entry.value.tagType) {
      case 'ASCII':
        newValue = image_lib.IfdValueAscii(entry.value.toString());
        break;
      case 'Byte':
        newValue = image_lib.IfdByteValue.list(
            Uint8List.fromList(entry.value.values.toList() as List<int>));
        break;
      case 'Long':
        newValue = image_lib.IfdValueLong(entry.value.values.firstAsInt());
        break;
      case 'Ratio':
        newValue = image_lib.IfdValueRational.list(
            (entry.value.values as IfdRatios)
                .ratios
                .map((e) => Rational(e.numerator, e.denominator))
                .toList());
        break;
    }
    if (entry.key.contains('GPS')) {
      exifData.gpsIfd[entry.value.tag] = newValue;
    } else {
      exifData.imageIfd[entry.value.tag] = newValue;
    }
  }

  image.exif = exifData;

  return image_lib.encodeNamedImage(name, image);
}
}