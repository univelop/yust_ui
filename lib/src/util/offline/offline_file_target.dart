import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

/// Identifies where a set of offline files lives.
///
/// Binds a Storage folder (where the bytes live) to the Firestore document
/// attribute holding the file metadata, so the two travel together.
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

  /// A value, so a target can key a provider family: two targets built from the
  /// same brick address the same files and must compare equal.
  @override
  bool operator ==(Object other) =>
      other is OfflineFileTarget &&
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

  /// Stamps [file] with this target's location.
  void apply(YustFile file) {
    file.storageFolderPath = storageFolderPath;
    file.linkedDocPath = linkedDocPath;
    file.linkedDocAttribute = linkedDocAttribute;
    file.linkedDocStoresFilesAsMap = storesFilesAsMap;
  }
}
