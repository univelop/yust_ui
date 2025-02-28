import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html;
import 'package:yust/yust.dart';
// ignore: implementation_imports
import 'package:image/src/util/rational.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../yust_ui.dart';

final Map<String, Map<String, int>> yustImageQuality = {
  'original': {'quality': 100, 'size': 5000},
  'high': {'quality': 90, 'size': 2000},
  'medium': {'quality': 80, 'size': 1200},
  'low': {'quality': 70, 'size': 800},
};

final yustAllowedImageExtensions = [
  'jpg',
  'jpeg',
  'png',
  'gif',
  'tiff',
  if (!kIsWeb) 'heic',
];

/// exifTagPrecision to encode exif information, e.g. latitude.
/// This number is the denominator of the fraction => increasing the number
/// increases the exifTagPrecision.
const exifTagPrecision = 10000;

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
    final size = MediaQuery.sizeOf(context);
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
    final size = MediaQuery.sizeOf(context);
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

  /// Resizes an image to a maximum width and quality.
  /// If [file] is not null, it will be used to load the image.
  /// If [bytes] is not null, it will be used to load the image.
  /// If [setGPSToLocation] is true, the GPS tags will be set to the current
  /// location, if they are not set.
  Future<Uint8List> resizeImage(
      {required String name,
      Uint8List? bytes,
      File? file,
      int maxWidth = 1024,
      int quality = 80,
      bool setGPSToLocation = false}) async {
    if (kIsWeb) {
      assert(bytes != null, 'bytes must not be null on web');
      return await _resizeWeb(
          name: name, bytes: bytes!, maxWidth: maxWidth, quality: quality);
    } else {
      assert((file != null || bytes != null),
          'file or bytes must not be null on mobile');
      Image? newImage;

      var originalImage = file != null
          ? await decodeImageFile(file.path)
          : decodeNamedImage(name, bytes!);
      if (originalImage == null) throw YustException('Could not load image.');

      newImage = originalImage;
      if (originalImage.width >= originalImage.height &&
          originalImage.width >= maxWidth) {
        newImage = copyResize(originalImage, width: maxWidth);
      } else if (originalImage.height > originalImage.width &&
          originalImage.height > maxWidth) {
        newImage = copyResize(originalImage, height: maxWidth);
      }

      final exif = originalImage.exif;

      // Orientation is baked into the image, so we can set it to no rotation
      exif.imageIfd.orientation = 1;
      // Size is changed, so we need to update the resolution
      exif.imageIfd.xResolution = newImage.exif.imageIfd.xResolution;
      exif.imageIfd.yResolution = newImage.exif.imageIfd.yResolution;
      exif.imageIfd.resolutionUnit = newImage.exif.imageIfd.resolutionUnit;
      exif.imageIfd.imageHeight = newImage.exif.imageIfd.imageHeight;
      exif.imageIfd.imageWidth = newImage.exif.imageIfd.imageWidth;
      if (setGPSToLocation) {
        try {
          // Check if GPS tags are set by the camera
          if (exif.gpsIfd['GPSLatitude'] == null) {
            final position = await YustUi.locationService.getCurrentPosition();

            exif.gpsIfd['GPSLatitudeRef'] =
                IfdValueAscii(position.latitude > 0 ? 'N' : 'S');
            exif.gpsIfd['GPSLatitude'] = _dDtoDMS(position.latitude);
            exif.gpsIfd['GPSLongitudeRef'] =
                IfdValueAscii(position.longitude > 0 ? 'E' : 'W');
            exif.gpsIfd['GPSLongitude'] = _dDtoDMS(position.longitude);
            exif.gpsIfd['GPSAltitudeRef'] =
                IfdByteValue(position.altitude > 0 ? 0 : 1);
            exif.gpsIfd['GPSAltitude'] = IfdValueRational(
                (position.altitude * exifTagPrecision).toInt().abs(),
                exifTagPrecision);
            final date = DateTime.now().toUtc();
            exif.gpsIfd['GPSTimeStamp'] = IfdValueRational.list([
              Rational(date.hour, 1),
              Rational(date.minute, 1),
              Rational(date.second, 1)
            ]);
            if (position.speed != 0) {
              exif.gpsIfd['GPSSpeedRef'] = IfdValueAscii('K');
              exif.gpsIfd['GPSSpeed'] = IfdValueRational(
                  // Conversion m/s to km/h
                  (((position.speed * 60 * 60) / 1000) * exifTagPrecision)
                      .toInt()
                      .abs(),
                  exifTagPrecision);
            }
            if (position.heading != 0 && position.heading != -1) {
              exif.gpsIfd['GPSImgDirectionRef'] = IfdValueAscii('T');
              exif.gpsIfd['GPSImgDirection'] = IfdValueRational(
                  (position.heading * exifTagPrecision).toInt().abs(),
                  exifTagPrecision);
              exif.gpsIfd['GPSDestBearingRef'] =
                  exif.gpsIfd['GPSImgDirectionRef'];
              exif.gpsIfd['GPSDestBearing'] = exif.gpsIfd['GPSImgDirection'];
            }
            exif.gpsIfd['GPSDate'] = IfdValueAscii(
                '${date.year}:${date.month.toString().padLeft(2, '0')}:${date.day.toString().padLeft(2, '0')}');
            if (position.accuracy != 0) {
              exif.gpsIfd[0x001f] = IfdValueRational(
                  (position.accuracy * exifTagPrecision).toInt().abs(),
                  exifTagPrecision);
            }
          }
        } catch (e) {
          // ignore: avoid_print
          print('Error getting position: $e');
        }
      }

      newImage.exif = exif;

      return encodeJpg(newImage, quality: quality);
    }
  }

  Future<Uint8List> _resizeWeb(
      {required String name,
      required Uint8List bytes,
      required int maxWidth,
      required int quality}) async {
    var base64 = base64Encode(bytes);
    var newImg = html.ImageElement();
    var mimeType =
        'image/${name.split('.').last.toLowerCase()}'.replaceAll('jpg', 'jpeg');
    newImg.src = 'data:$mimeType;base64,$base64';

    await newImg.onLoad.first;

    int width = newImg.width!;
    int height = newImg.height!;

    if (newImg.width! >= newImg.height! && newImg.width! >= maxWidth) {
      width = maxWidth;
      height = (width * newImg.height! / newImg.width!).round();
    } else if (newImg.height! > newImg.width! && newImg.height! > maxWidth) {
      height = maxWidth;
      width = (height * newImg.width! / newImg.height!).round();
    }

    var canvas = html.CanvasElement(width: width, height: height);
    var ctx = canvas.context2D;

    ctx.drawImageScaled(newImg, 0, 0, width, height);

    return await _getBlobData(await canvas.toBlob('image/jpeg', quality / 100));
  }

  Future<Uint8List> _getBlobData(html.Blob blob) {
    final completer = Completer<Uint8List>();
    final reader = html.FileReader();
    reader.readAsArrayBuffer(blob);
    reader.onLoad.listen((_) => completer.complete(reader.result as Uint8List));
    return completer.future;
  }

  /// Converts a double (Decimal Degree Format) to a [IfdValueRational]
  /// in DMS (Degree Minute Second) Format.
  IfdValueRational _dDtoDMS(double dd) {
    final double degrees = dd.abs();
    final int degreesInt = degrees.toInt();
    final double minutes = (dd.abs() - degreesInt) * 60;
    final int minutesInt = minutes.toInt();
    final double seconds = (minutes - minutesInt) * 60;
    final int secondsInt = (seconds * exifTagPrecision).toInt();
    return IfdValueRational.list([
      Rational(degreesInt, 1),
      Rational(minutesInt, 1),
      Rational(secondsInt, exifTagPrecision)
    ]);
  }

  Future<YustFile> resizeImageWithCompute(
      {required String path,
      required bool resize,
      required bool convertToJPEG,
      required String yustQuality,
      Uint8List? bytes,
      File? file,
      required bool setGPSToLocation,
      String? storageFolderPath,
      String? linkedDocPath,
      String? linkedDocAttribute}) async {
    final sanitizedPath = _sanitizeFilePath(path);
    if (resize && convertToJPEG) {
      final size = yustImageQuality[yustQuality]!['size']!;
      final quality = yustImageQuality[yustQuality]!['quality']!;
      // Save file helpers instance, so compute doesn't cause problems
      final fileHelpers = YustUi.fileHelpers;
      final locationService = YustUi.locationService;

      Future<Uint8List?> helper(RootIsolateToken? token) async {
        // This is needed for the geolocator plugin to work
        if (token != null) {
          BackgroundIsolateBinaryMessenger.ensureInitialized(token);
        }
        // Make sure the YustUI statics are initialized for this thread too
        YustUi.fileHelpers = fileHelpers;
        YustUi.locationService = locationService;

        return await YustUi.fileHelpers.resizeImage(
            name: sanitizedPath,
            bytes: bytes,
            maxWidth: size,
            quality: quality,
            file: file,
            setGPSToLocation: setGPSToLocation);
      }

      RootIsolateToken? token;
      if (!kIsWeb) {
        token = RootIsolateToken.instance;
      }
      bytes = await compute(helper, token);
    }

    convertToJPEG = convertToJPEG;
    final newImageName = convertToJPEG
        ? '${Yust.helpers.randomString(length: 16)}.jpeg'
        : '${Yust.helpers.randomString(length: 16)}.${path.split('.').last}';

    return YustFile(
      name: newImageName,
      file: file,
      bytes: bytes,
      storageFolderPath: storageFolderPath,
      linkedDocPath: linkedDocPath,
      linkedDocAttribute: linkedDocAttribute,
    );
  }

  /// Returns a string with the size in KiB, MiB or GiB.
  ///
  /// - [sizeInKB] The size in KiB.
  String formatFileSize(num sizeInKiB) {
    if (sizeInKiB >= 1024 * 1024) {
      return '${(sizeInKiB / (1024 * 1024)).toStringAsFixed(2)} GiB';
    } else if (sizeInKiB >= 1024) {
      return '${(sizeInKiB / 1024).toStringAsFixed(2)} MiB';
    } else {
      return '$sizeInKiB KiB';
    }
  }
}

_sanitizeFilePath(String path) {
  return path.replaceAll(RegExp(r'[,#]'), '_');
}
