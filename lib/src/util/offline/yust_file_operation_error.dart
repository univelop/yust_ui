// FirebaseException, re-exported by cloud_firestore, covers Storage errors too.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:yust/yust.dart';

import '../../extensions/string_translate_extension.dart';
import '../../generated/locale_keys.g.dart';
import 'yust_file_operation.dart';

/// The bytes an operation needs are not in Storage at all.
///
/// Raised where the file service reports a failed transfer as empty bytes
/// rather than throwing, so the queue can tell "the object is gone" — which no
/// retry fixes — apart from "the server was unreachable", which every retry
/// might.
class YustMissingStorageObjectException extends YustException {
  YustMissingStorageObjectException(super.message);
}

/// Why an operation failed in a way no retry can fix, in the terms the user is
/// told about. Not a taxonomy of Firebase codes — four outcomes, because that is
/// how many distinct things there are to say.
enum YustFileOperationFailureReason {
  /// The account may not touch this file (any more).
  noPermission,

  /// Storage holds no such object — deleted elsewhere, or never arrived.
  fileMissing,

  /// The server rejected the file itself.
  fileInvalid,

  /// Something about the operation is broken in a way no retry gets past.
  unknown,
}

/// Classifies a file operation's failure: why it can never succeed, or null
/// when retrying might still get it through.
abstract final class YustFileOperationError {
  /// Firebase codes no retry gets past, by what they mean to the user.
  /// Everything absent here (`unavailable`, `retry-limit-exceeded`, …) is a
  /// connection problem wearing a code.
  static const _codesByReason = {
    YustFileOperationFailureReason.noPermission: {
      'permission-denied',
      'unauthenticated',
      'unauthorized',
      'storage/unauthorized',
    },
    YustFileOperationFailureReason.fileMissing: {
      'not-found',
      'object-not-found',
      'storage/object-not-found',
    },
    YustFileOperationFailureReason.fileInvalid: {
      'invalid-argument',
      'storage/invalid-argument',
    },
  };

  /// Why [error] means the operation can never succeed, or null when it is
  /// transient and the backoff should keep retrying. Only the cases below are
  /// permanent; an unrecognised error retries.
  static YustFileOperationFailureReason? reasonFor(Object error) {
    if (error is YustMissingStorageObjectException) {
      return YustFileOperationFailureReason.fileMissing;
    }
    if (error is ArgumentError || error is StateError) {
      return YustFileOperationFailureReason.unknown;
    }
    if (error is! FirebaseException) return null;
    for (final MapEntry(key: reason, value: codes) in _codesByReason.entries) {
      if (codes.contains(error.code)) return reason;
    }
    return null;
  }

  /// The error a failed transfer of [name] under [path] should be reported as:
  /// permanent when Storage holds no such object, transient otherwise.
  static Future<Exception> missingOrUnreachable(
    String path,
    String name,
  ) async {
    if (await Yust.fileService.fileExist(path: path, name: name)) {
      return YustException(LocaleKeys.exceptionFileNotFound.tr());
    }
    return YustMissingStorageObjectException(
      LocaleKeys.exceptionFileNotFound.tr(),
    );
  }
}

/// The alert's body for a failed upload: what could not be done, then why, then
/// what happens to it. The headline is the same for every failure
/// ([LocaleKeys.fileProcessingFailed]), so the operation is named here.
///
/// Resolved at display time, so it follows the app's current language rather
/// than the one the operation failed in. Only an upload is ever kept for the
/// user to see — every other kind is dropped as it fails.
extension YustFileOperationFailureText on YustFileOperation<YustFile> {
  String get failureMessage =>
      '${LocaleKeys.alertFileUploadFailed.tr()} ${switch (failure) {
        YustFileOperationFailureReason.noPermission =>
          LocaleKeys.alertFileSyncFailedNoPermission.tr(),
        YustFileOperationFailureReason.fileMissing =>
          LocaleKeys.alertFileSyncFailedFileMissing.tr(),
        YustFileOperationFailureReason.fileInvalid =>
          LocaleKeys.alertFileSyncFailedFileInvalid.tr(),
        YustFileOperationFailureReason.unknown ||
        null => LocaleKeys.alertFileSyncFailedUnknown.tr(),
      }}';
}
