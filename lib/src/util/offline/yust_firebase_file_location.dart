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
    this.storesFilesAsMap = false,
  });

  /// Storage folder the file bytes live under.
  final String storageFolderPath;

  /// Firestore document holding the file metadata (e.g. `documents/abc`).
  final String? linkedDocPath;

  /// Attribute on [linkedDocPath] holding the files (e.g. `attributes.xyz`).
  final String? linkedDocAttribute;

  /// When true the attribute is a `{hash: file}` map, so a single file can be
  /// written with a field mask (`attribute.hash`) — conflict-free, no array
  /// read-modify-write. When false the legacy array layout is used.
  final bool storesFilesAsMap;

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
      other.linkedDocAttribute == linkedDocAttribute &&
      other.storesFilesAsMap == storesFilesAsMap;

  @override
  int get hashCode => Object.hash(
    storageFolderPath,
    linkedDocPath,
    linkedDocAttribute,
    storesFilesAsMap,
  );

  /// Stamps [file] with this location.
  void apply(YustFile file) {
    file.storageFolderPath = storageFolderPath;
    file.linkedDocPath = linkedDocPath;
    file.linkedDocAttribute = linkedDocAttribute;
    file.linkedDocStoresFilesAsMap = storesFilesAsMap;
  }
}
