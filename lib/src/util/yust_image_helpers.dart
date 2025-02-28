import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart';
import 'package:universal_html/html.dart' as html;
import 'package:yust/yust.dart';
// ignore: implementation_imports
import 'package:image/src/util/rational.dart';

import '../../yust_ui.dart';
import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';

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
enum YustWatermarkPosition {
  topLeft(LocaleKeys.topLeft),
  topRight(LocaleKeys.topRight),
  bottomLeft(LocaleKeys.bottomLeft),
  bottomRight(LocaleKeys.bottomRight);

  const YustWatermarkPosition(this._localeKey);
  final String _localeKey;

  /// Returns the translated label of this option
  String getLabel() => _localeKey.tr();

  /// Returns the translated labels of all options
  static List<String> get labels =>
      YustWatermarkPosition.values.map((r) => r.getLabel()).toList();

  static YustWatermarkPosition fromJson(String value) =>
      YustWatermarkPosition.values.firstWhere(
        (e) => e.name == value,
        orElse: () => YustWatermarkPosition.bottomLeft,
      );

  String toJson() => name;
}

enum YustLocationAppearance {
  decimalDegree(LocaleKeys.decimalDegreeWithAbbreviation, 'decimal_degree'),
  degreeMinutesSeconds(
      LocaleKeys.degreeMinuteSecondsWithAbbreviation, 'degree_minutes_seconds');

  const YustLocationAppearance(this._localeKey, this._jsonKey);
  final String _localeKey;
  final String _jsonKey;

  /// Returns the translated label of this option
  String getLabel() => _localeKey.tr();

  /// Returns the translated labels of all options
  static List<String> get labels =>
      YustLocationAppearance.values.map((r) => r.getLabel()).toList();

  static List<String> jsonValues() =>
      YustLocationAppearance.values.map((l) => l._jsonKey).toList();

  static YustLocationAppearance fromJson(String value) =>
      YustLocationAppearance.values.firstWhere(
        (e) => e._jsonKey == value,
        orElse: () => YustLocationAppearance.decimalDegree,
      );

  String toJson() => _jsonKey;
}

/// exifTagPrecision to encode exif information, e.g. latitude.
/// This number is the denominator of the fraction => increasing the number
/// increases the exifTagPrecision.
const exifTagPrecision = 10000;

class YustImageHelpers {
  YustImageHelpers();

  /// Processes an image.
  ///
  /// - If [resize] is true, the image will be resized to the fit the given [yustQuality].
  /// - If [convertToJPEG] is true, the image will be converted to JPEG.
  ///
  /// The following only works on mobile:
  /// - If [setGPSToLocation] is true, the GPS tags will be set to the current location.
  /// - If [addTimestampWatermark] is true, a timestamp watermark will be added.
  /// - If [addGpsWatermark] is true, a GPS watermark will be added.
  /// - Use [watermarkPosition] to specify the position of the watermark. Default is [YustWatermarkPosition.bottomLeft].
  /// - Use [locale] to specify the locale for the watermark timestamp.
  /// - If [displayCoordinatesInDegreeMinuteSecond] is true, the GPS watermark will be displayed in DMS format. Default is in decimal degrees.
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
    YustWatermarkPosition watermarkPosition = YustWatermarkPosition.bottomLeft,
    Locale locale = const Locale('de'),
    YustLocationAppearance watermarkLocationAppearance =
        YustLocationAppearance.decimalDegree,
  }) async {
    final sanitizedPath = _sanitizeFilePath(path);
    final mustTransform =
        convertToJPEG && (resize || addTimestampWatermark || addGpsWatermark);
    Uint8List? transformedBytes;
    final now = Yust.helpers.utcNow();
    Position? position;
    YustAddress? address;

    if (mustTransform) {
      final size = yustImageQuality[yustQuality]!['size']!;
      final quality = yustImageQuality[yustQuality]!['quality']!;

      // This is required because we cannot access the static YustUi.[...] from the isolated process
      final fileHelpers = YustUi.fileHelpers;
      final timestampText =
          '${Yust.helpers.formatDate(now, locale: locale.languageCode)} ${Yust.helpers.formatTime(now)}';

      // Check if we need to load the gps position for either
      // watermarking or setting the GPS tags.
      if (setGPSToLocation || addGpsWatermark) {
        try {
          position = await YustUi.locationService.getCurrentPosition();
          address = await YustUi.locationService.getAddressFromCoordinates(
            position.latitude,
            position.longitude,
          );
        } catch (e) {
          // ignore: avoid_print
          print('Error getting position: $e');
        }
      }

      Future<Uint8List> helper(RootIsolateToken? token) async {
        // This is needed for the geolocator plugin to work
        if (token != null) {
          BackgroundIsolateBinaryMessenger.ensureInitialized(token);
        }

        // Make sure the YustUI statics are initialized for this thread too
        YustUi.fileHelpers = fileHelpers;

        return await _transformImage(
          name: sanitizedPath,
          bytes: bytes,
          maxWidth: size,
          quality: quality,
          file: file,
          resize: resize,
          convertToJPEG: convertToJPEG,
          setGPSToLocation: setGPSToLocation,
          addTimestampWatermark: addTimestampWatermark,
          addGpsWatermark: addGpsWatermark,
          locale: locale,
          watermarkLocationAppearance: watermarkLocationAppearance,
          watermarkPosition: watermarkPosition,
          now: now,
          // This is required because we cannot access the static YustUi.[...] from the isolated process
          timestampText: timestampText,
          position: position,
        );
      }

      RootIsolateToken? token;
      if (!kIsWeb) {
        token = RootIsolateToken.instance;
      }
      transformedBytes = await compute(helper, token);
    }

    final newImageExtension = convertToJPEG ? 'jpeg' : path.split('.').last;
    final newImageName =
        '${Yust.helpers.randomString(length: 16)}.$newImageExtension';

    return YustImage(
      name: newImageName,
      file: file,
      bytes: transformedBytes,
      storageFolderPath: storageFolderPath,
      linkedDocPath: linkedDocPath,
      linkedDocAttribute: linkedDocAttribute,
      location: position != null
          ? YustGeoLocation(
              latitude: position.latitude,
              longitude: position.longitude,
              accuracy: position.accuracy,
              address: address,
            )
          : null,
      createdAt: now,
    );
  }
}

/// Transforms an image
Future<Uint8List> _transformImage({
  required String name,
  required Locale locale,
  required bool resize,
  required bool convertToJPEG,
  required bool setGPSToLocation,
  required bool addTimestampWatermark,
  required bool addGpsWatermark,
  required DateTime now,
  Uint8List? bytes,
  File? file,
  int maxWidth = 1024,
  int quality = 80,
  YustWatermarkPosition watermarkPosition = YustWatermarkPosition.bottomLeft,
  YustLocationAppearance watermarkLocationAppearance =
      YustLocationAppearance.decimalDegree,
  String? timestampText,
  Position? position,
}) async {
  // If we are on web, we rely purely on bytes. Watermarking will also not be possible.
  if (kIsWeb) {
    assert(bytes != null, 'bytes must not be null on web');

    if (!resize) {
      return bytes!;
    }

    final resized = await _resizeWeb(
        name: name, bytes: bytes!, maxWidth: maxWidth, quality: quality);

    return resized;
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
  await _setImageExifData(
    originalImage: originalImage,
    newImage: newImage,
    setGPSToLocation: setGPSToLocation,
    position: position,
    createdAt: now,
  );

  // Add watermark to image
  if (addTimestampWatermark || addGpsWatermark) {
    _addWatermarks(
      image: newImage,
      addTimestamp: addTimestampWatermark,
      addGps: addGpsWatermark,
      position: position,
      watermarkPosition: watermarkPosition,
      locale: locale,
      watermarkLocationAppearance: watermarkLocationAppearance,
      timestampText: timestampText,
    );
  }

  if (convertToJPEG) {
    // Encode as JPEG
    return encodeJpg(newImage, quality: quality);
  }

  return newImage.getBytes();
}

void _addWatermarks({
  required Image image,
  required bool addTimestamp,
  required bool addGps,
  required YustWatermarkPosition watermarkPosition,
  required Locale locale,
  Position? position,
  YustLocationAppearance watermarkLocationAppearance =
      YustLocationAppearance.decimalDegree,
  String? timestampText,
}) {
  final textBuffer = <String>[];
  if (addTimestamp && timestampText != null) {
    textBuffer.add(timestampText);
  }

  if (addGps && position != null) {
    final yustLocationHelper = YustLocationHelper();

    if (watermarkLocationAppearance ==
        YustLocationAppearance.degreeMinutesSeconds) {
      textBuffer.add(
          '${yustLocationHelper.formatLatitudeToDMS(position.latitude, degreeSymbol: '*')} ${yustLocationHelper.formatLongitudeToDMS(position.longitude, degreeSymbol: '*')}');
    } else {
      textBuffer.add(
          '${yustLocationHelper.formatDecimalCoordinate(position.latitude)} ${yustLocationHelper.formatDecimalCoordinate(position.longitude)}');
    }
  }

  if (textBuffer.isEmpty) {
    return;
  }

  _drawTextOnImage(
    image: image,
    text: textBuffer.join('\n'),
    watermarkPosition: watermarkPosition,
  );
}

/// Draws a string on an image.
///
/// Internally draws text on an offscreen image, then resize and places it at [watermarkPosition].
/// - [fractionOfWidth] is the maximum fraction of [image.width]. Default is 20%
/// - [minWidth] ensures a minimum pixel width for small images. Default is 150px
/// - [lineSpacing] extra vertical space between lines of text.
void _drawTextOnImage({
  required Image image,
  required String text,
  required YustWatermarkPosition watermarkPosition,
  double fractionOfWidth = 0.2,
  int minWidth = 150,
  bool withBackground = true,
  int margin = 10,
  int backgroundPadding = 5,
  int lineSpacing = 6,
}) {
  if (image.width < minWidth) {
    return;
  }

  final font = arial48;

  // Calculate text sizes
  final (width: unscaledWidth, height: unscaledHeight) =
      _measureMultiline(font, text, lineSpacing);
  if (unscaledWidth == 0 || unscaledHeight == 0) return;

  final textCanvas = Image(width: unscaledWidth, height: unscaledHeight);

  // Draw the text
  var currentY = 0;
  final lines = text.split(RegExp(r'[\n\r]'));
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    drawString(
      textCanvas,
      line,
      font: font,
      x: 0,
      y: currentY,
      color: ColorRgba8(255, 255, 255, 255),
    );
    final (width: _, height: lineHeight) = _measureSingleLine(font, line);
    currentY += lineHeight;

    if (i < lines.length - 1) {
      currentY += lineSpacing;
    }
  }

  // Compute the maximum scaled width based on [fractionOfWidth]
  final maxScaledWidth = (image.width * fractionOfWidth).round();
  final scaledWidth = max(maxScaledWidth, minWidth);
  if (scaledWidth < 1) return;

  final scaleFactor = scaledWidth / unscaledWidth;
  final scaledHeight = (unscaledHeight * scaleFactor).round();

  // Scale the text
  final scaledCanvas = copyResize(
    textCanvas,
    width: scaledWidth,
    height: scaledHeight,
    interpolation: Interpolation.cubic,
  );

  late int dstX;
  late int dstY;
  switch (watermarkPosition) {
    case YustWatermarkPosition.topLeft:
      dstX = margin;
      dstY = margin;
      break;
    case YustWatermarkPosition.topRight:
      dstX = image.width - scaledWidth - margin;
      dstY = margin;
      break;
    case YustWatermarkPosition.bottomLeft:
      dstX = margin;
      dstY = image.height - scaledHeight - margin;
      break;
    case YustWatermarkPosition.bottomRight:
      dstX = image.width - scaledWidth - margin;
      dstY = image.height - scaledHeight - margin;
      break;
  }

  if (withBackground) {
    final bgX1 = dstX - backgroundPadding;
    final bgY1 = dstY - backgroundPadding;
    final bgX2 = dstX + scaledWidth + backgroundPadding;
    final bgY2 = dstY + scaledHeight + backgroundPadding;

    fillRect(
      image,
      x1: bgX1,
      y1: bgY1,
      x2: bgX2,
      y2: bgY2,
      color: ColorRgba8(0, 0, 0, 255),
    );
  }

  compositeImage(
    image,
    scaledCanvas,
    dstX: dstX,
    dstY: dstY,
  );
}

/// Measures multi-line [text] separated by \n or \r, returns (width, height)
({int width, int height}) _measureMultiline(
    BitmapFont font, String text, int lineSpacing) {
  var maxWidth = 0;
  var totalHeight = 0;

  final lines = text.split(RegExp(r'[\n\r]'));
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final (width: w, height: h) = _measureSingleLine(font, line);
    if (w > maxWidth) {
      maxWidth = w;
    }
    totalHeight += h;

    // For all but the last line, add spacing
    if (i < lines.length - 1) {
      totalHeight += lineSpacing;
    }
  }

  return (width: maxWidth, height: totalHeight);
}

/// Measures the size of a single line of text
/// Returns (width, height).
({int width, int height}) _measureSingleLine(BitmapFont font, String line) {
  var stringWidth = 0;
  var stringHeight = 0;

  for (final c in line.codeUnits) {
    if (!font.characters.containsKey(c)) {
      // fallback for missing glyph
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

  if (line.isEmpty) {
    stringHeight = font.base;
  }

  return (width: stringWidth, height: stringHeight);
}

Future<void> _setImageExifData({
  required Image originalImage,
  required Image newImage,
  required bool setGPSToLocation,
  required DateTime createdAt,
  Position? position,
}) async {
  final exif = originalImage.exif;

  // Orientation is baked into the image, so we can set it to no rotation
  exif.imageIfd.orientation = 1;
  // Size is changed, so we need to update the resolution
  exif.imageIfd.xResolution = newImage.exif.imageIfd.xResolution;
  exif.imageIfd.yResolution = newImage.exif.imageIfd.yResolution;
  exif.imageIfd.resolutionUnit = newImage.exif.imageIfd.resolutionUnit;
  exif.imageIfd.imageHeight = newImage.exif.imageIfd.imageHeight;
  exif.imageIfd.imageWidth = newImage.exif.imageIfd.imageWidth;

  final formattedDate = _formatExifDateTime(createdAt);

  if (exif.imageIfd['DateTimeOriginal'] == null) {
    exif.imageIfd['DateTimeOriginal'] = IfdValueAscii(formattedDate);
  }

  if (exif.imageIfd['DateTimeDigitized'] == null) {
    exif.imageIfd['DateTimeDigitized'] = IfdValueAscii(formattedDate);
  }

  if (exif.imageIfd['DateTime'] == null) {
    exif.imageIfd['DateTime'] = IfdValueAscii(formattedDate);
  }

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

/// Formats a DateTime to a string in the format 'YYYY:MM:DD HH:MM:SS'
String _formatExifDateTime(DateTime dt) =>
    '${dt.year.toString().padLeft(4, '0')}:'
    '${dt.month.toString().padLeft(2, '0')}:'
    '${dt.day.toString().padLeft(2, '0')} '
    '${dt.hour.toString().padLeft(2, '0')}:'
    '${dt.minute.toString().padLeft(2, '0')}:'
    '${dt.second.toString().padLeft(2, '0')}';

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
