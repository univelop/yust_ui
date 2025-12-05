import 'dart:async';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../yust_ui.dart';
import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';

class YustFileHelpers {
  YustFileHelpers();

  /// Under Firefox only one BroadcastStream can be used for the
  /// connectivity result. Therefore, use this stream instance
  static final connectivityStream = Connectivity().onConnectivityChanged
      .asBroadcastStream();

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
      YustUi.webHelpers.downloadData(name, data);
    } else {
      if (file == null && data != null) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/$name';
        file = await File(path).create();
        file.writeAsBytesSync(data);
      }
      if (file != null) {
        final buttonLocation = box!.localToGlobal(Offset.zero) & box.size;
        // Clamp buttonLocation to the screen size
        final clampedButtonLocation = Rect.fromLTWH(
          buttonLocation.left.clamp(0, size.width),
          buttonLocation.top.clamp(0, size.height),
          buttonLocation.width.clamp(0, size.width - buttonLocation.left),
          buttonLocation.height.clamp(0, size.height - buttonLocation.top),
        );

        // Alternatively create a Location in the center of the Screen
        // c-spell: disable-next-line
        final centerLocation = Rect.fromLTWH(0, 0, size.width, size.height / 2);

        // If we don't have a useful button location, use the center position
        final sharePositionOrigin =
            (clampedButtonLocation.bottom > size.height ||
                clampedButtonLocation.right > size.width)
            ? centerLocation
            : clampedButtonLocation;
        // ignore: todo
        // TODO: use shareXFiles
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            subject: name,
            sharePositionOrigin: sharePositionOrigin,
          ),
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
      size: size,
      box: box,
      name: name,
      file: file,
      data: data,
    );
  }

  /// Downloads a file. On iOS and Android shows Share-Popup afterwards.
  /// For the browser starts the file download.
  Future<void> downloadAndLaunchFile({
    required BuildContext context,
    required String url,
    required String name,
  }) async {
    final size = MediaQuery.sizeOf(context);
    // Get the Location of the widget (e.g. button), that called the method.
    final box = context.findRenderObject() as RenderBox?;
    await EasyLoading.show(status: LocaleKeys.loadingFile.tr());
    try {
      if (kIsWeb) {
        final r = await http.get(
          Uri.parse(url),
        );
        _validateFileResponse(r);

        final data = r.bodyBytes;
        await launchFileWithoutContext(
          size: size,
          box: box,
          name: name,
          data: data,
        );
      } else {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/$name';
        await Dio().download(url, path);
        final file = File(path);
        await launchFileWithoutContext(
          size: size,
          box: box,
          name: name,
          file: file,
        );
      }
      await EasyLoading.dismiss();
    } catch (e) {
      await EasyLoading.dismiss();
      await YustUi.alertService.showAlert(
        LocaleKeys.oops.tr(),
        LocaleKeys.alertCannotOpenFileWithError.tr(
          namedArgs: {'error': e.toString()},
        ),
      );
    }
  }

  void _validateFileResponse(http.Response response) {
    if (response.statusCode >= 300) {
      throw Exception(
        LocaleKeys.errorOnFileDownload.tr(
          namedArgs: {'statusCode': response.statusCode.toString()},
        ),
      );
    }
  }

  bool isValidFileName(String filename) {
    final invalidChars = ['\\', '/', ':', '*', '?', '<', '>', '|'];

    return invalidChars.none((element) => filename.contains(element));
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
