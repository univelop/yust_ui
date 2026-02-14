import 'dart:async';

import 'package:yust/yust.dart';

import '../../yust_ui.dart';
import '../generated/locale_keys.g.dart';
import 'string_translate_extension.dart';

/// UI convenience extension for [YustFileValidationOptions].
///
/// Wraps [YustFileValidationOptions.validateFile] with translated alerts
/// via [YustUi.alertService].
extension YustFileValidationOptionsUi on YustFileValidationOptions {
  /// Validates a new file and shows a translated alert on failure.
  ///
  /// Returns `true` if valid, `false` if validation failed (alert already shown).
  /// For [YustFileAlreadyExistsException] and [YustFileOverwriteRequiredException],
  /// shows a confirmation dialog — returns `true` if the user confirms.
  Future<bool> verifyFile({
    required YustFile newFile,
    required List<YustFile> existingFiles,
    int? newFileSizeInKiB,
  }) async {
    try {
      validateFile(
        newFile: newFile,
        existingFiles: existingFiles,
        newFileSizeInKiB: newFileSizeInKiB,
      );
      return true;
    } on YustFileOverwriteRequiredException {
      final confirmed = await YustUi.alertService.showConfirmation(
        LocaleKeys.alertConfirmOverwriteFile.tr(),
        LocaleKeys.continue_.tr(),
      );
      return confirmed ?? false;
    } on YustFileAlreadyExistsException catch (e) {
      final confirmed = await YustUi.alertService.showConfirmation(
        LocaleKeys.alertFileAlreadyExists
            .tr(namedArgs: {'fileName': e.fileName}),
        LocaleKeys.continue_.tr(),
      );
      return confirmed ?? false;
    } on YustFileSizeExceededException catch (e) {
      unawaited(
        YustUi.alertService.showAlert(
          LocaleKeys.fileUpload.tr(),
          LocaleKeys.alertFileTooBig.tr(
            namedArgs: {
              'fileName': newFile.name ?? '',
              'maxFileSize': YustUi.fileHelpers
                  .formatFileSize(e.maximumFileSizeInKiB),
            },
          ),
        ),
      );
      return false;
    } on YustFileExtensionNotAllowedException catch (e) {
      unawaited(
        YustUi.alertService.showAlert(
          LocaleKeys.fileUpload.tr(),
          e.allowedExtensions.isEmpty
              ? LocaleKeys.alertNoAllowedExtensions.tr()
              : LocaleKeys.alertAllowedExtensions.tr(
                  namedArgs: {
                    'allowedExtensions': e.allowedExtensions.join(', '),
                  },
                ),
        ),
      );
      return false;
    } on YustFileLimitExceededException catch (e) {
      unawaited(
        YustUi.alertService.showAlert(
          LocaleKeys.fileUpload.tr(),
          LocaleKeys.fileLimitWillExceed.tr(
            namedArgs: {'limit': e.limit.toString()},
          ),
        ),
      );
      return false;
    }
  }
}
