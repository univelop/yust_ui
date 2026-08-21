import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yust/yust.dart';
import 'package:yust_open_file_x/yust_open_file_x.dart';

import '../../extensions/string_translate_extension.dart';
import '../../generated/locale_keys.g.dart';
import '../../yust_ui.dart';

/// Presents a [YustFile] to the user — the single entry point for opening,
/// opening in the default app, and sharing.
///
/// The only file component that touches a [BuildContext], so the offline
/// managers stay UI-free and testable. Every verb resolves the file through
/// [YustFileHelpers.resolveToLocalFile] (native) or
/// [YustFileHelpers.resolveDownloadUrl] (web), so one cache-and-URL policy sits
/// behind all of them.
class FilePresenter {
  /// Opens [file] in the built-in preview — the on-device copy if cached,
  /// otherwise downloaded — falling back to the browser. Opens the browser
  /// directly on web.
  static Future<void> open(BuildContext context, YustFile file) {
    if (kIsWeb) return _launchBrowser(file);
    return _openLocal(file, useDefaultApp: false);
  }

  /// Opens [file] in the user's default app (iOS 26+), else the built-in
  /// preview. On web, shares (downloads) the file.
  static Future<void> openInDefaultApp(BuildContext context, YustFile file) {
    if (kIsWeb) return share(context, file);
    return _openLocal(file, useDefaultApp: true);
  }

  /// Opens the share sheet (mobile) or triggers a download (web), using the
  /// on-device copy when cached. [fileName] overrides the shared name, else the
  /// file's own name is used.
  static Future<void> share(
    BuildContext context,
    YustFile file, {
    String? fileName,
  }) async {
    final name = fileName ?? file.name!;
    if (kIsWeb) {
      final url = await YustUi.fileHelpers.resolveDownloadUrl(file);
      if (url == null) {
        await _showError(LocaleKeys.alertCannotOpenFile.tr());
        return;
      }
      if (!context.mounted) return;
      await YustUi.fileHelpers.downloadAndLaunchFile(
        context: context,
        url: url,
        name: name,
      );
      return;
    }
    await _withLocalFile(file, (localFile) async {
      if (!context.mounted) return;
      await YustUi.fileHelpers.launchFile(
        context: context,
        name: name,
        file: localFile,
      );
    });
  }

  static Future<void> _openLocal(
    YustFile file, {
    required bool useDefaultApp,
  }) => _withLocalFile(file, (localFile) async {
    final result = await OpenFilex.open(
      localFile.path,
      useIosDefaultApp: useDefaultApp,
    );
    if (result.type != ResultType.done) await _launchBrowser(file);
  });

  /// Resolves [file] to an on-device file behind a loading indicator, runs
  /// [action] on it, and surfaces any failure as an alert.
  static Future<void> _withLocalFile(
    YustFile file,
    Future<void> Function(File localFile) action,
  ) async {
    await EasyLoading.show(status: LocaleKeys.loadingFile.tr());
    try {
      final localFile = await YustUi.fileHelpers.resolveToLocalFile(file);
      await EasyLoading.dismiss();
      await action(localFile);
    } catch (error) {
      await EasyLoading.dismiss();
      await _showError(
        LocaleKeys.alertCannotOpenFileWithError.tr(
          namedArgs: {'error': error.toString()},
        ),
      );
    }
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

  static Future<void> _showError(String message) =>
      YustUi.alertService.showAlert(LocaleKeys.oops.tr(), message);
}
