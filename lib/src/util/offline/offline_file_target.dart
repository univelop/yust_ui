import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

/// Identifies where a set of offline files lives.
///
/// A target binds a Storage folder (where the bytes live) to the Firestore
/// document attribute that holds the file metadata. It replaces the loose
/// `storageFolderPath` / `linkedDocPath` / `linkedDocAttribute` triple that the
/// old `YustFileHandler` threaded through every method.
@immutable
class OfflineFileTarget {
  const OfflineFileTarget({
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

  /// True when the target is backed by a Firestore document, so files can be
  /// cached offline and their metadata written back.
  bool get isLinked => linkedDocPath != null && linkedDocAttribute != null;

  /// Whether [file] belongs to this target (same doc + attribute).
  bool owns(YustFile file) =>
      file.linkedDocPath == linkedDocPath &&
      file.linkedDocAttribute == linkedDocAttribute;

  /// Stamps [file] with this target's location.
  void apply(YustFile file) {
    file.storageFolderPath = storageFolderPath;
    file.linkedDocPath = linkedDocPath;
    file.linkedDocAttribute = linkedDocAttribute;
    file.linkedDocStoresFilesAsMap = storesFilesAsMap;
  }
}
