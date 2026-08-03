import 'package:yust/yust.dart';

/// What a [FileOperation] does. The first three are outbound (local change →
/// server, handled by the UploadManager); [download] is inbound (server → local
/// cache, handled by the DownloadManager). All flow through the one queue.
enum FileOperationType { upload, rename, delete, download }

/// A single file change queued for sync — the queue's entry type.
///
/// Generic over [T] so [YustFile] and [YustImage] share the queue; the image's
/// extra fields round-trip via the polymorphic [YustFile.toJson] and the factory
/// in [fromJson].
class FileOperation<T extends YustFile> {
  FileOperation({
    required this.type,
    required this.file,
    this.newName,
    String? id,
    String? databaseIdentifier,
    DateTime? createdAt,
  }) : databaseIdentifier = databaseIdentifier ?? file.hash,
       createdAt = createdAt ?? DateTime.now(),
       id = id ?? '${DateTime.now().microsecondsSinceEpoch}_${file.hash}';

  /// Stable identity for the entry, independent of the mutable [file]. A manager
  /// removes an op by this after applying it (the file may have been mutated,
  /// e.g. renamed, by then).
  final String id;

  /// What this operation does.
  final FileOperationType type;

  /// The file the operation acts on, in its current state.
  final T file;

  /// The new name for a [FileOperationType.rename]; null otherwise.
  final String? newName;

  /// Content-hash key locating the file's entry in the record document.
  final String databaseIdentifier;

  /// When the op was enqueued (FIFO ordering).
  final DateTime createdAt;

  /// The on-device key for this file's bytes: the identifier, or the name for
  /// hashless legacy (array-layout) files.
  String get fileKey =>
      databaseIdentifier.isNotEmpty ? databaseIdentifier : (file.name ?? '');

  /// Serialises the op, adding the file's addressing fields that
  /// [YustFile.toJson] drops so the op is replayable after a restart.
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'file': file.toJson(),
    'fileType': file is YustImage ? YustImage.type : YustFile.type,
    'devicePath': file.devicePath,
    'storageFolderPath': file.storageFolderPath,
    'linkedDocPath': file.linkedDocPath,
    'linkedDocAttribute': file.linkedDocAttribute,
    'storesFilesAsMap': file.linkedDocStoresFilesAsMap,
    'newName': newName,
    'databaseIdentifier': databaseIdentifier,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Rebuilds an op. [fileFromJson] picks the concrete file subtype
  /// (`YustFile.fromJson` or `YustImage.fromJson`); the queue supplies it.
  static FileOperation<T> fromJson<T extends YustFile>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fileFromJson,
  ) {
    final file = fileFromJson(json['file'] as Map<String, dynamic>);
    file.devicePath = json['devicePath'] as String?;
    file.storageFolderPath = json['storageFolderPath'] as String?;
    file.linkedDocPath = json['linkedDocPath'] as String?;
    file.linkedDocAttribute = json['linkedDocAttribute'] as String?;
    file.linkedDocStoresFilesAsMap = json['storesFilesAsMap'] as bool?;
    return FileOperation<T>(
      id: json['id'] as String?,
      type: FileOperationType.values.byName(json['type'] as String),
      file: file,
      newName: json['newName'] as String?,
      databaseIdentifier: json['databaseIdentifier'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
