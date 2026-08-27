// FirebaseException, re-exported by cloud_firestore, covers Storage errors too.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:yust/yust.dart';

import '../../extensions/string_translate_extension.dart';
import '../../generated/locale_keys.g.dart';

/// The bytes an operation needs are not in Storage at all.
///
/// Raised where the file service reports a failed transfer as empty bytes
/// rather than throwing, so the queue can tell "the object is gone" — which no
/// retry fixes — apart from "the server was unreachable", which every retry
/// might.
class YustMissingStorageObjectException extends YustException {
  YustMissingStorageObjectException(super.message);
}

/// Classifies a file operation's failure as permanent or transient.
abstract final class YustFileOperationError {
  /// Firebase codes no retry gets past: not allowed, or the target is gone.
  /// Everything else (`unavailable`, `retry-limit-exceeded`, …) is a connection
  /// problem wearing a code.
  static const _permanentFirebaseCodes = {
    'permission-denied',
    'unauthenticated',
    'unauthorized',
    'not-found',
    'object-not-found',
    'invalid-argument',
    'storage/unauthorized',
    'storage/object-not-found',
    'storage/invalid-argument',
  };

  /// Whether [error] means the operation can never succeed, so it counts against
  /// the operation's attempt budget instead of retrying forever. Only these are
  /// permanent; every other error counts as transient and retries.
  static bool isPermanent(Object error) =>
      error is ArgumentError ||
      error is StateError ||
      error is YustMissingStorageObjectException ||
      (error is FirebaseException &&
          _permanentFirebaseCodes.contains(error.code));

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
