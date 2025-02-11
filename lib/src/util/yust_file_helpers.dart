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
import 'package:geolocator/geolocator.dart';
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

/// Position of the watermark on the image.
enum WatermarkPosition {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

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

  /// Processes an image.
  ///
  /// - If [resize] is true, the image will be resized to the fit the given [yustQuality].
  /// - If [convertToJPEG] is true, the image will be converted to JPEG.
  /// - If [setGPSToLocation] is true, the GPS tags will be set to the current location.
  /// - If [addTimestampWatermark] is true, a timestamp watermark will be added.
  /// - If [addGpsWatermark] is true, a GPS watermark will be added.
  Future<YustImage> processImage({
    required String path,
    required bool resize,
    required bool convertToJPEG,
    required String yustQuality,
    Uint8List? bytes,
    File? file,
    required bool setGPSToLocation,
    String? storageFolderPath,
    String? linkedDocPath,
    String? linkedDocAttribute,
    bool addTimestampWatermark = false,
    bool addGpsWatermark = false,
    WatermarkPosition watermarkPosition = WatermarkPosition.bottomLeft,
  }) async {
    final sanitizedPath = _sanitizeFilePath(path);
    final mustTransform =
        convertToJPEG && (resize || addTimestampWatermark || addGpsWatermark);

    if (mustTransform) {
      final size = yustImageQuality[yustQuality]!['size']!;
      final quality = yustImageQuality[yustQuality]!['quality']!;

      Future<Uint8List?> helper(RootIsolateToken? token) async {
        // This is needed for the geolocator plugin to work
        if (token != null) {
          BackgroundIsolateBinaryMessenger.ensureInitialized(token);
        }

        return await _transformImage(
            name: sanitizedPath,
            bytes: bytes,
            maxWidth: size,
            quality: quality,
            file: file,
            resize: resize,
            setGPSToLocation: setGPSToLocation,
            addTimestampWatermark: addTimestampWatermark,
            addGpsWatermark: addGpsWatermark);
      }

      RootIsolateToken? token;
      if (!kIsWeb) {
        token = RootIsolateToken.instance;
      }
      bytes = await compute(helper, token);
    }

    final newImageExtension = convertToJPEG ? 'jpeg' : path.split('.').last;
    final newImageName =
        '${Yust.helpers.randomString(length: 16)}.$newImageExtension';

    return YustImage(
      name: newImageName,
      file: file,
      bytes: bytes,
      storageFolderPath: storageFolderPath,
      linkedDocPath: linkedDocPath,
      linkedDocAttribute: linkedDocAttribute,
    );
  }
}

Future<Uint8List> _transformImage({
  required String name,
  Uint8List? bytes,
  File? file,
  int maxWidth = 1024,
  int quality = 80,
  bool resize = false,
  bool setGPSToLocation = false,
  bool addTimestampWatermark = false,
  bool addGpsWatermark = false,
  WatermarkPosition watermarkPosition = WatermarkPosition.bottomLeft,
}) async {
  // If we are on web, we rely purely on bytes. Watermarking will also not be possible.
  if (kIsWeb) {
    assert(bytes != null, 'bytes must not be null on web');

    if (!resize) {
      return bytes!;
    }

    return await _resizeWeb(
        name: name, bytes: bytes!, maxWidth: maxWidth, quality: quality);
  }

  // On mobile, either file or bytes must be provided.
  assert((file != null || bytes != null),
      'file or bytes must not be null on mobile');
  Image? newImage;

  // Decode the image
  var originalImage = file != null
      ? await decodeImageFile(file.path)
      : decodeNamedImage(name, bytes!);
  if (originalImage == null) throw YustException('Could not load image.');
  newImage = originalImage;

  // Check if we need to load the gps position for either
  // watermarking or setting the GPS tags.
  Position? position;
  if (setGPSToLocation || addGpsWatermark) {
    try {
      position = await YustUi.locationService.getCurrentPosition();
    } catch (e) {
      // ignore: avoid_print
      print('Error getting position: $e');
    }
  }

  // Resize the image if needed
  if (resize) {
    if (originalImage.width >= originalImage.height &&
        originalImage.width >= maxWidth) {
      newImage = copyResize(originalImage, width: maxWidth);
    } else if (originalImage.height > originalImage.width &&
        originalImage.height > maxWidth) {
      newImage = copyResize(originalImage, height: maxWidth);
    }
  }

  // Set exif data
  await _setImageExifData(originalImage, newImage, setGPSToLocation, position);

  // Add watermark to image
  if (addTimestampWatermark || addGpsWatermark) {
    _addWatermarks(
      newImage,
      addTimestampWatermark,
      addGpsWatermark,
      position,
      watermarkPosition,
    );
  }

  // Encode as JPEG
  return encodeJpg(newImage, quality: quality);
}

void _addWatermarks(
  Image image,
  bool addTimestamp,
  bool addGps,
  Position? position,
  WatermarkPosition watermarkPosition,
) {
  final textBuffer = <String>[];
  if (addTimestamp) {
    textBuffer.add(_formattedTimestamp());
  }
  if (addGps && position != null) {
    textBuffer.add('Lat: ${position.latitude.toStringAsFixed(6)}, '
        'Lon: ${position.longitude.toStringAsFixed(6)}');
  }

  if (textBuffer.isEmpty) {
    return;
  }

  // Join them with a line break if both are present.
  final watermarkText = textBuffer.join('\n');
  _drawTextInCorner(
      image: image,
      text: watermarkText,
      watermarkPosition: watermarkPosition,
      font: arial14);
}

/// Simple helper to get the current local time in a readable format.
String _formattedTimestamp() {
  final now = DateTime.now();
  return '${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)} '
      '${_twoDigits(now.hour)}:${_twoDigits(now.minute)}:${_twoDigits(now.second)}';
}

String _twoDigits(int n) => n.toString().padLeft(2, '0');

/// Draws [text] into [image] at [corner].
/// If [withBackground] is true, draws a semi-transparent rectangle behind it.
void _drawTextInCorner({
  required Image image,
  required String text,
  required BitmapFont font,
  required WatermarkPosition watermarkPosition,
  bool withBackground = true,
  int margin = 10,
}) {
  // Measure total width and height of all lines in [text].
  final (width: textWidth, height: textHeight) = _measureMultiline(font, text);

  // Determine the top-left placement (x,y) based on the chosen corner.
  late int x;
  late int y;
  switch (watermarkPosition) {
    case WatermarkPosition.topLeft:
      x = margin;
      y = margin;
      break;
    case WatermarkPosition.topRight:
      x = image.width - textWidth - margin;
      y = margin;
      break;
    case WatermarkPosition.bottomLeft:
      x = margin;
      y = image.height - textHeight - margin;
      break;
    case WatermarkPosition.bottomRight:
      x = image.width - textWidth - margin;
      y = image.height - textHeight - margin;
      break;
  }

  // Optionally draw a semi-transparent background rectangle behind the text.
  if (withBackground) {
    fillRect(
      image,
      x1: x,
      y1: y,
      x2: x + textWidth,
      y2: y + textHeight,
      color: ColorRgba8(0, 0, 0, 128), // black with alpha
    );
  }

  // Draw each line, moving downward as needed.
  final lines = text.split(RegExp(r'[\n\r]'));
  var currentY = y;
  for (final line in lines) {
    drawString(
      image,
      line,
      font: font,
      x: x,
      y: currentY,
      color: ColorRgba8(255, 255, 255, 255), // white text
    );
    final (width: _, height: lineHeight) = _measureSingleLine(font, line);
    currentY += lineHeight;
  }
}

/// Measures multi-line [text] by summing the heights of each line
/// and tracking the maximum width among them.
({int width, int height}) _measureMultiline(BitmapFont font, String text) {
  var maxWidth = 0;
  var totalHeight = 0;

  for (final line in text.split(RegExp(r'[\n\r]'))) {
    final (width: w, height: h) = _measureSingleLine(font, line);
    if (w > maxWidth) {
      maxWidth = w;
    }
    totalHeight += h;
  }
  return (width: maxWidth, height: totalHeight);
}

/// Measures a single [line] by replicating the internal drawString logic.
/// Returns a record with (width, height).
({int width, int height}) _measureSingleLine(BitmapFont font, String line) {
  var stringWidth = 0;
  var stringHeight = 0;

  for (final c in line.codeUnits) {
    if (!font.characters.containsKey(c)) {
      // Fallback width for missing glyphs
      stringWidth += font.base ~/ 2;
      continue;
    }
    final ch = font.characters[c]!;
    stringWidth += ch.xAdvance;
    final candidateHeight = ch.height + ch.yOffset;
    if (candidateHeight > stringHeight) {
      stringHeight = candidateHeight;
    }
  }

  // If the line is empty, default to at least font.base in height.
  if (line.isEmpty) {
    stringHeight = font.base;
  }

  return (width: stringWidth, height: stringHeight);
}

Future<void> _setImageExifData(Image originalImage, Image newImage,
    bool setGPSToLocation, Position? position) async {
  final exif = originalImage.exif;

  // Orientation is baked into the image, so we can set it to no rotation
  exif.imageIfd.orientation = 1;
  // Size is changed, so we need to update the resolution
  exif.imageIfd.xResolution = newImage.exif.imageIfd.xResolution;
  exif.imageIfd.yResolution = newImage.exif.imageIfd.yResolution;
  exif.imageIfd.resolutionUnit = newImage.exif.imageIfd.resolutionUnit;
  exif.imageIfd.imageHeight = newImage.exif.imageIfd.imageHeight;
  exif.imageIfd.imageWidth = newImage.exif.imageIfd.imageWidth;

  // TODO: Set createdAt timestamp here

  // Set GPS tags if needed
  if (setGPSToLocation && position != null) {
    // Check if GPS tags are set by the camera
    if (exif.gpsIfd['GPSLatitude'] == null) {
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
        exif.gpsIfd['GPSDestBearingRef'] = exif.gpsIfd['GPSImgDirectionRef'];
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
  }

  newImage.exif = exif;
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

String _sanitizeFilePath(String path) {
  return path.replaceAll(RegExp(r'[,#]'), '_');
}
