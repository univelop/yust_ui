import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

/// The keys every offline component addresses a file by: [offlineKey] for the
/// entry, [byteKey] for its bytes.
extension YustFileOfflineKey on YustFile {
  /// This file's identity as one entry of a list: overlay entry, queue matching,
  /// download dedupe. A digest of the Storage location, which is what an entry
  /// is — never the bare name, which is not unique across records, and never the
  /// content hash, which two entries holding the same bytes share.
  ///
  /// Not `FileHandlingHelper.fileMapKey` (uni_core): that keys the Firestore
  /// entry and must keep matching existing documents.
  String get offlineKey =>
      md5.convert(utf8.encode('${storageFolderPath ?? path}/$name')).toString();

  /// The key this file's bytes are cached under: the content hash, falling back
  /// to [offlineKey] for a file that has none.
  ///
  /// Content-addressed on purpose. An entry keeps its location when its content
  /// is replaced — a re-drawn signature is `signature.png` either way — so a
  /// location-keyed copy would go on being served after the bytes changed
  /// somewhere else.
  String get byteKey => hash.isNotEmpty ? hash : offlineKey;

  /// Cache key of a hashless file on an install predating [byteKey]. Read only:
  /// nothing writes it.
  String get legacyOfflineKey => name ?? '';

  /// Computes the md5 [YustFile.hash] from the file's content when it has none,
  /// so its record key is stable before the upload runs.
  ///
  /// Call before enqueueing: a file that stays hashless is keyed in the record
  /// by name, which cannot be addressed as a single Firestore field once it
  /// contains a dot.
  Future<void> ensureHash() async {
    if (hash.isNotEmpty) return;
    final stopwatch = Stopwatch()..start();
    if (bytes != null) {
      hash = md5.convert(bytes!).toString();
    } else if (file != null) {
      hash = (await file!.openRead().transform(md5).first).toString();
    }
    // Runs on the UI isolate and scales with the file, so its cost is worth
    // seeing: on web there is no isolate to move it to.
    debugPrint(
      '[offline-sync] hashed "$name" '
      '(${bytes?.lengthInBytes ?? 0} bytes) in ${stopwatch.elapsedMilliseconds}ms',
    );
  }
}

/// What a [FileOperation] does. The first four are outbound (local change →
/// server, handled by the UploadManager); [download] is inbound (server → local
/// cache, handled by the DownloadManager). All flow through the one queue.
///
/// [updateMetadata] touches no bytes: it re-writes the file's own entry in the
/// linked document (e.g. after its favorite flag changed). It exists so that a
/// metadata-only change is queued and field-masked like every other change,
/// instead of the picker saving its whole file list back over the record.
enum FileOperationType { upload, rename, delete, updateMetadata, download }

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
    this.failedAttempts = 0,
    String? id,
    String? fileKey,
    DateTime? createdAt,
  }) : fileKey = fileKey ?? file.offlineKey,
       createdAt = createdAt ?? DateTime.now(),
       id = id ?? '${DateTime.now().microsecondsSinceEpoch}_${file.offlineKey}';

  /// Stable identity for the entry, independent of the mutable [file]. A manager
  /// removes an operation by this after applying it (the file may have been mutated,
  /// e.g. renamed, by then).
  final String id;

  /// What this operation does.
  final FileOperationType type;

  /// The file the operation acts on, in its current state.
  final T file;

  /// The new name for a [FileOperationType.rename]; null otherwise.
  final String? newName;

  /// The [YustFileOfflineKey.offlineKey] of [file], frozen at enqueue time so a
  /// rename cannot move the operation's bytes out from under it.
  final String fileKey;

  /// When the operation was enqueued (FIFO ordering).
  final DateTime createdAt;

  /// How often this operation failed for a reason retrying cannot fix. Connection
  /// failures never count; at the handler's limit the operation is timed out.
  final int failedAttempts;

  /// A copy with one more permanent failure recorded.
  FileOperation<T> withFailedAttempt() =>
      _copyWith(failedAttempts: failedAttempts + 1);

  /// A copy with its failures forgotten, for a user-triggered retry.
  FileOperation<T> withResetFailedAttempts() => _copyWith(failedAttempts: 0);

  FileOperation<T> _copyWith({required int failedAttempts}) => FileOperation<T>(
    type: type,
    file: file,
    newName: newName,
    id: id,
    fileKey: fileKey,
    createdAt: createdAt,
    failedAttempts: failedAttempts,
  );

  /// Serialises the operation, the file via [YustFile.toLocalJson].
  ///
  /// `type` appears at both levels — the operation's here, the file's subtype
  /// nested. Flattening the map would collide them.
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'newName': newName,
    'fileKey': fileKey,
    'failedAttempts': failedAttempts,
    'createdAt': createdAt.toIso8601String(),
    'file': file.toLocalJson(),
  };

  /// Rebuilds an operation, taking the file's subtype from its own `type`.
  static FileOperation<T> fromJson<T extends YustFile>(
    Map<String, dynamic> json,
  ) {
    final fileJson = Map<String, dynamic>.from(json['file'] as Map);
    final file = fileJson['type'] == YustImage.type
        ? YustImage.fromLocalJson(fileJson)
        : YustFile.fromLocalJson(fileJson);
    return FileOperation<T>(
      id: json['id'] as String?,
      type: FileOperationType.values.byName(json['type'] as String),
      file: file as T,
      newName: json['newName'] as String?,
      fileKey: json['fileKey'] as String?,
      failedAttempts: json['failedAttempts'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
