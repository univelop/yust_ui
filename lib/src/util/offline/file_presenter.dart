import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yust/yust.dart';

import '../../extensions/string_translate_extension.dart';
import '../../generated/locale_keys.g.dart';
import '../../yust_ui.dart';
import '../yust_file_helpers.dart';

/// Presents offline files to the user (open / open-in-default-app / share).
///
/// The only offline-file component that touches a [BuildContext], so the
/// managers stay UI-free and testable.
class FilePresenter {
  /// Opens [file] in the built-in preview — the on-device copy if cached,
  /// otherwise downloaded from its URL — falling back to the browser.
  static Future<void> open(BuildContext context, YustFile file) =>
      _open(context, file, useDefaultApp: false);

  /// Opens [file] in the user's default app (iOS 26+), else the built-in
  /// preview. On web, downloads the file.
  static Future<void> openInDefaultApp(BuildContext context, YustFile file) {
    if (kIsWeb) return share(context, file);
    return _open(context, file, useDefaultApp: true);
  }

  /// Opens the share sheet (mobile) or triggers a download (web).
  static Future<void> share(BuildContext context, YustFile file) => YustUi
      .fileHelpers
      .downloadAndLaunchYustFile(context: context, file: file);

  static Future<void> _open(
    BuildContext context,
    YustFile file, {
    required bool useDefaultApp,
  }) async {
    if (kIsWeb) {
      await _launchBrowser(file);
      return;
    }
    await EasyLoading.show(status: LocaleKeys.loadingFile.tr());
    try {
      final filePath = await _resolveLocalPath(file);
      await EasyLoading.dismiss();
      final result = await OpenFilex.open(
        filePath,
        useIosDefaultApp: useDefaultApp,
      );
      if (result.type != ResultType.done) await _launchBrowser(file);
    } catch (error) {
      await EasyLoading.dismiss();
      await YustUi.alertService.showAlert(
        LocaleKeys.oops.tr(),
        LocaleKeys.alertCannotOpenFileWithError.tr(
          namedArgs: {'error': error.toString()},
        ),
      );
    }
  }

  /// Returns a local file path for [file], using the on-device copy when present
  /// and downloading to a temp file otherwise.
  static Future<String> _resolveLocalPath(YustFile file) async {
    file.storageFolderPath ??= file.path;
    // The durable app-support copy, not the temp staging dir.
    final offlinePath = file.cached
        ? file.devicePath
        : await YustUi.fileHelpers.getPathForFile(file);
    if (offlinePath != null) {
      file.devicePath = offlinePath;
      return offlinePath;
    }

    final url = file.getOriginalUrl();
    if (url == null) throw YustException(LocaleKeys.exceptionFileNotFound.tr());

    // iOS mishandles special characters in file names, so sanitize them.
    final fileName = Platform.isIOS
        ? YustFileHelpers.sanitizeFileName(file.name!)
        : file.name!;
    final tempDir = await getTemporaryDirectory();
    final downloadPath = '${tempDir.path}/${file.storageFolderPath}/$fileName';
    await Directory(
      '${tempDir.path}/${file.storageFolderPath}',
    ).create(recursive: true);
    await Dio().download(url, downloadPath);
    return downloadPath;
  }

  static Future<void> _launchBrowser(YustFile file) async {
    final url = file.getOriginalUrl();
    final uri = Uri.parse(url ?? '');
    if (url != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw YustException(LocaleKeys.alertCannotOpenFile.tr());
    }
  }
}
