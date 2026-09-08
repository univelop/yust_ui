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
import 'package:yust/yust.dart';

import '../../yust_ui.dart';
import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';

class YustFileHelpers {
  YustFileHelpers({YustOfflineStorage? offlineStorage})
    : _offlineStorage = offlineStorage ?? YustOfflineStorage.forDevice();

  final YustOfflineStorage? _offlineStorage;

  /// Under Firefox only one BroadcastStream can be used for the
  /// connectivity result. Therefore, use this stream instance
  static final connectivityStream = Connectivity().onConnectivityChanged
      .asBroadcastStream();

  /// Where [file]'s bytes should be read from: the on-device copy when cached,
  /// else the signed network URL, else null.
  Future<Uri?> getSourceUri(YustFile file) async {
    final path = await _offlineStorage?.pathForFile(file.byteKey);
    if (path != null) return Uri.file(path);
    final url = file.getOriginalUrl();
    return url == null ? null : Uri.parse(url);
  }

  /// [file]'s on-device copy, when it is still there. A [YustFile.devicePath]
  /// can outlive the bytes it points at: the byte store is cleaned of files no
  /// record marked available offline holds, while a file object already handed
  /// out keeps the path.
  File? _deviceFileIfStillPresent(YustFile file) {
    final devicePath = file.devicePath;
    if (devicePath == null) return null;
    final deviceFile = File(devicePath);
    return deviceFile.existsSync() ? deviceFile : null;
  }

  /// A synchronous [ImageProvider] for [file]: its on-device copy when cached
  /// (requires [YustFile.devicePath] to already be populated), else the network
  /// URL. For async cache resolution to a [Uri], use [getSourceUri].
  ImageProvider imageProviderFor(YustFile file) {
    final deviceFile = _deviceFileIfStillPresent(file);
    return deviceFile != null
        ? MemoryImage(deviceFile.readAsBytesSync())
        : NetworkImage(file.getOriginalUrl() ?? '');
  }

  /// The URL to fetch [file] from: the configured download-url hook if any,
  /// else its signed original URL. Null when the file is not addressable.
  Future<String?> resolveDownloadUrl(YustFile file) async {
    final generateDownloadUrl = Yust.fileAccessService.generateDownloadUrl;
    return (generateDownloadUrl != null
            ? await generateDownloadUrl(file)
            : null) ??
        file.getOriginalUrl();
  }

  /// A local [File] for [file]: the on-device copy when cached, otherwise the
  /// file downloaded to a namespaced temp path. Native only — web has no local
  /// file. Throws [YustException] when the file is neither cached nor
  /// addressable.
  Future<File> resolveToLocalFile(YustFile file) async {
    file.storageFolderPath ??= file.path;
    // The durable copy short-circuits the byte-store lookup; an uploaded file
    // is found through its content key.
    final cachedPath =
        _deviceFileIfStillPresent(file)?.path ??
        await _offlineStorage?.pathForFile(file.byteKey);
    if (cachedPath != null) return File(cachedPath);

    final url = await resolveDownloadUrl(file);
    if (url == null) throw YustException(LocaleKeys.exceptionFileNotFound.tr());

    // iOS mishandles special characters in file names, so sanitize them.
    final fileName = Platform.isIOS ? sanitizeFileName(file.name!) : file.name!;
    final tempDir = await getTemporaryDirectory();
    final folder = '${tempDir.path}/${file.storageFolderPath}';
    await Directory(folder).create(recursive: true);
    final downloadPath = '$folder/$fileName';
    await Dio().download(url, downloadPath);
    return File(downloadPath);
  }

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
        // iOS has problems handling files with special characters in the name,
        // therefore we share the file as data.
        if (Platform.isIOS) {
          data ??= await file.readAsBytes();
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile.fromData(data)],
              fileNameOverrides: [sanitizeFileName(name)],
              sharePositionOrigin: sharePositionOrigin,
              title: name,
            ),
          );
          return;
        }
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            subject: name,
          ),
        );
      }
    }
  }

  /// Sanitizes the given [rawFileName] by removing or replacing invalid characters.
  static String sanitizeFileName(String rawFileName) {
    // Replace invalid characters
    final fileName = rawFileName
        .replaceAll(
          RegExp(r"[^A-Za-z\s0-9!#$%&'()+.,´\-—_;:=@\[\]^{}]", unicode: true),
          '_',
        )
        // Replace any whitespace characters (tabs, etc.) with a single space
        .replaceAll(RegExp(r'\s+'), ' ');
    return fileName.trim();
  }

  /// Shares or downloads a file.
  /// On iOS and Android shows Share-Popup afterwards.
  /// For the browser starts the file download.
  /// Use either [file] or [data].
  ///
  /// Generic launcher for arbitrary bytes or files (generated exports, scripts,
  /// logs). For a `YustFile`, use `YustFilePresenter` instead — it resolves the
  /// on-device cache and signed URL, which this does not.
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
  ///
  /// Generic launcher for an arbitrary URL. For a `YustFile`, use
  /// `YustFilePresenter` instead — it resolves the on-device cache and signed URL,
  /// which this does not.
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
      await _showFileError(e);
    }
  }

  /// Whether [file] cannot be opened from anywhere.
  static bool isFileBroken(YustFile file) {
    final name = file.name;
    if (name == null || name.isEmpty) return true;
    if (file.isValid()) return false;
    return file.bytes == null &&
        file.file == null &&
        (kIsWeb || file.devicePath == null);
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

  Future<void> _showFileError(Object error) => YustUi.alertService.showAlert(
    LocaleKeys.oops.tr(),
    LocaleKeys.alertCannotOpenFileWithError.tr(
      namedArgs: {'error': error.toString()},
    ),
  );

  void _validateFileResponse(http.Response response) {
    if (response.statusCode >= 300) {
      throw YustException(
        LocaleKeys.errorOnFileDownload.tr(
          namedArgs: {'statusCode': response.statusCode.toString()},
        ),
      );
    }
  }
}
