import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

/// Where a set of files lives in Firebase, and the identity of that set.
///
/// Binds the Storage folder (where the bytes live) to the Firestore document
/// attribute holding the file metadata, so the two travel together. This is the
/// remote location only — the on-device copy is addressed separately, via
/// `YustFileOfflineKey` and `OfflineStorage`.
///
/// These three fields used to live directly on the per-brick file handler. Once
/// the handler became a single app-scoped [FileOperationHandler] whose queue
/// carries every brick's files, the address had to become its own value: each
/// [FileListController] holds one to stamp its files ([apply]) and to pick its
/// own operations back out of the shared queue ([owns]).
@immutable
class FirebaseFileLocation {
  const FirebaseFileLocation({
    required this.storageFolderPath,
    this.linkedDocPath,
    this.linkedDocAttribute,
    this.storesFilesAsMap = false,
  });

  /// Storage folder the file bytes live under.
  final String storageFolderPath;

  /// Firestore document holding the file metadata (e.g. `records/abc`).
  final String? linkedDocPath;

  /// Attribute on [linkedDocPath] holding the files (e.g. `brickValues.xyz`).
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
  /// the same brick address the same files and must compare equal.
  @override
  bool operator ==(Object other) =>
      other is FirebaseFileLocation &&
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
