import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

/// Where a set of files lives in Firebase, and the identity of that set.
///
/// Binds the Storage folder (where the bytes live) to the Firestore document
/// attribute holding the file metadata, so the two travel together. This is the
/// remote location only — the on-device copy is addressed separately, via
/// `YustFileOfflineKey` and `YustOfflineStorage`.
///
/// These three fields used to live directly on the per-host file handler. Once
/// the handler became a single app-scoped [YustFileOperationHandler] whose queue
/// carries every host's files, the address had to become its own value: each
/// [YustFileListController] holds one to stamp its files ([apply]) and to pick its
/// own operations back out of the shared queue ([owns]).
@immutable
class YustFirebaseFileLocation {
  const YustFirebaseFileLocation({
    required this.storageFolderPath,
    this.linkedDocPath,
    this.linkedDocAttribute,
  });

  /// Storage folder the file bytes live under.
  final String storageFolderPath;

  /// Firestore document holding the file metadata (e.g. `documents/abc`).
  final String? linkedDocPath;

  /// Attribute on [linkedDocPath] holding the files (e.g. `attributes.xyz`).
  final String? linkedDocAttribute;

  /// True when the location is backed by a Firestore document, so files can be
  /// cached offline and their metadata written back.
  bool get isLinked => linkedDocPath != null && linkedDocAttribute != null;

  /// Whether [file] belongs to this location. The Storage folder is part of the
  /// identity because two unlinked locations share a null document address.
  bool owns(YustFile file) =>
      file.storageFolderPath == storageFolderPath &&
      file.linkedDocPath == linkedDocPath &&
      file.linkedDocAttribute == linkedDocAttribute;

  /// A value, so a location can key a provider family: two locations built from
  /// the same host address the same files and must compare equal.
  @override
  bool operator ==(Object other) =>
      other is YustFirebaseFileLocation &&
      other.storageFolderPath == storageFolderPath &&
      other.linkedDocPath == linkedDocPath &&
      other.linkedDocAttribute == linkedDocAttribute;

  @override
  int get hashCode =>
      Object.hash(storageFolderPath, linkedDocPath, linkedDocAttribute);

  /// Re-attaches this location's addressing to [file]. The document does not
  /// persist these fields, so a file read back from it needs them stamped on.
  void apply(YustFile file) {
    file.storageFolderPath = storageFolderPath;
    file.linkedDocPath = linkedDocPath;
    file.linkedDocAttribute = linkedDocAttribute;
  }
}
