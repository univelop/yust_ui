import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

import 'file_operation.dart';
import 'file_operation_handler.dart';
import 'offline_file_doc_writer.dart';
import 'offline_storage.dart';

/// Pushes an outbound op — upload / rename / delete / metadata update — up to
/// Storage and writes its metadata back through an [OfflineFileDocWriter]. The
/// outbound executor.
///
/// This is where that logic lives — moved out of the pickers and
/// `YustFileHandler`. Queueing, retries and connectivity are the
/// [FileOperationHandler]'s job; this class only declares which kinds it owns
/// and how to carry out one. Byte transfer goes straight to `Yust.fileService`.
///
/// One shared manager drains ops for every record/brick, so the doc writer is
/// resolved per op via [docWriterFor] — the app builds the writer scoped to the
/// op's own file (from its `linkedDocPath` / `linkedDocAttribute`) rather than
/// one writer being bound at construction.
class UploadManager implements FileOperationExecutor {
  UploadManager({
    required OfflineFileDocWriter Function(FileOperation<YustFile>)
    docWriterFor,
    OfflineStorage? storage,
  }) : _docWriterFor = docWriterFor,
       _storage = storage ?? OfflineStorage();

  final OfflineFileDocWriter Function(FileOperation<YustFile>) _docWriterFor;
  final OfflineStorage _storage;

  @override
  Set<FileOperationType> get handledTypes => {
    FileOperationType.upload,
    FileOperationType.rename,
    FileOperationType.delete,
    FileOperationType.updateMetadata,
  };

  @override
  Future<void> execute(FileOperation<YustFile> op) => switch (op.type) {
    FileOperationType.upload => _upload(op),
    FileOperationType.rename => _rename(op),
    FileOperationType.delete => _delete(op),
    FileOperationType.updateMetadata => _updateMetadata(op),
    FileOperationType.download => throw StateError(
      'download is not an upload op',
    ),
  };

  Future<void> _upload(FileOperation<YustFile> op) async {
    final file = op.file;
    final docWriter = _docWriterFor(op);
    final localPath = await _storage.resolvePath(op.fileKey);
    final url = await Yust.fileService.uploadFile(
      path: file.storageFolderPath!,
      name: file.name!,
      file: localPath != null ? File(localPath) : file.file,
      bytes: file.bytes,
      linkedDocPath: file.linkedDocPath,
      linkedDocAttribute: file.linkedDocAttribute,
      createThumbnail: file.createThumbnail,
    );
    file.path = file.storageFolderPath;
    // ignore: deprecated_member_use
    file.url = url;
    await docWriter.writeFile(file);
  }

  /// Detaches the file's record entry first, then deletes its bytes.
  ///
  /// The order matters offline. A document write reaches Firestore's local
  /// cache immediately — every listener sees the file gone at once — while its
  /// Future only completes once the server acknowledges, which offline is
  /// never. So the write is handed off rather than awaited: Firestore is itself
  /// a durable write queue and syncs it on reconnect. This queue owns the
  /// bytes, which is the part Firestore cannot do.
  ///
  /// Deleting the bytes first instead would fail offline before the entry was
  /// ever detached, leaving the file on screen with nothing visibly happening.
  /// The byte delete still gates the op: if it fails the op stays queued and
  /// runs again, and re-detaching an already-detached entry is a no-op.
  Future<void> _delete(FileOperation<YustFile> op) async {
    final file = op.file;
    unawaited(
      _docWriterFor(op)
          .removeFile(file)
          .catchError(
            (Object error) => debugPrint(
              '[offline-sync] detaching "${file.name}" failed: $error',
            ),
          ),
    );
    await Yust.fileService.deleteFile(
      path: file.storageFolderPath!,
      name: file.name,
    );
    await _storage.remove(op.fileKey);
  }

  /// Re-writes the file's document entry with no byte transfer. Queued behind
  /// any upload of the same file, so it always lands on an entry that exists.
  Future<void> _updateMetadata(FileOperation<YustFile> op) =>
      _docWriterFor(op).writeFile(op.file);

  Future<void> _rename(FileOperation<YustFile> op) async {
    final file = op.file;
    final docWriter = _docWriterFor(op);
    final oldName = file.name!;
    final newName = op.newName!;
    final localPath = await _storage.resolvePath(op.fileKey);
    // Reupload the same bytes under the new name (bytes unchanged → same hash).
    final bytes = localPath == null
        ? await Yust.fileService.downloadFile(
            path: file.storageFolderPath!,
            name: oldName,
          )
        : null;
    final url = await Yust.fileService.uploadFile(
      path: file.storageFolderPath!,
      name: newName,
      file: localPath != null ? File(localPath) : null,
      bytes: bytes,
      linkedDocPath: file.linkedDocPath,
      linkedDocAttribute: file.linkedDocAttribute,
    );
    // Remove the old entry before writing the new one — for the map layout both
    // share the hash key, so writing first then removing would drop the new one.
    await docWriter.removeFile(file);
    file.name = newName;
    file.path = file.storageFolderPath;
    // ignore: deprecated_member_use
    file.url = url;
    await docWriter.writeFile(file);
    await Yust.fileService.deleteFile(
      path: file.storageFolderPath!,
      name: oldName,
    );
  }
}
