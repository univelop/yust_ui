import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

import 'file_operation.dart';
import 'file_operation_handler.dart';
import 'offline_file_document_writer.dart';
import 'offline_storage.dart';

/// Pushes an outbound operation — upload / rename / delete / metadata update — up to
/// Storage and writes its metadata back through an [OfflineFileDocumentWriter]. The
/// outbound executor.
///
/// This is where that logic lives — moved out of the pickers and
/// `YustFileHandler`. Queueing, retries and connectivity are the
/// [FileOperationHandler]'s job; this class only declares which kinds it owns
/// and how to carry out one. Byte transfer goes straight to `Yust.fileService`.
///
/// One shared manager drains operations for every record/brick, so the document writer is
/// resolved per operation via [documentWriterFor] — the app builds the writer scoped to the
/// operation's own file (from its `linkedDocPath` / `linkedDocAttribute`) rather than
/// one writer being bound at construction.
///
/// [documentWriterFor] may return null: a picker bound to a brick's settings has a
/// storage folder but no record, so its bytes upload with nothing to write back.
///
/// No document write is awaited unbounded. A Firestore write reaches the local
/// cache at once but resolves only on server acknowledgement — offline it
/// neither completes nor fails, and the drain is serial, so one such write would
/// stop every other operation. Firestore's cache is a durable queue, so handing the
/// write off loses nothing.
class UploadManager implements FileOperationExecutor {
  UploadManager({
    required OfflineFileDocumentWriter? Function(FileOperation<YustFile>)
    documentWriterFor,
    OfflineStorage? storage,
    Duration? documentWriteTimeout,
  }) : _documentWriterFor = documentWriterFor,
       _storage = storage ?? OfflineStorage(),
       _documentWriteTimeout =
           documentWriteTimeout ?? defaultDocumentWriteTimeout;

  /// How long a document write may take before the operation counts as done anyway.
  /// Bounds only the record write; byte transfers keep Firebase's own window.
  static const defaultDocumentWriteTimeout = Duration(seconds: 30);

  final OfflineFileDocumentWriter? Function(FileOperation<YustFile>)
  _documentWriterFor;
  final Duration _documentWriteTimeout;
  final OfflineStorage _storage;

  @override
  Set<FileOperationType> get handledTypes => {
    FileOperationType.upload,
    FileOperationType.rename,
    FileOperationType.delete,
    FileOperationType.updateMetadata,
  };

  @override
  Future<void> execute(FileOperation<YustFile> operation) =>
      switch (operation.type) {
        FileOperationType.upload => _upload(operation),
        FileOperationType.rename => _rename(operation),
        FileOperationType.delete => _delete(operation),
        FileOperationType.updateMetadata => _updateMetadata(operation),
        FileOperationType.download => throw StateError(
          'download is not an upload operation',
        ),
      };

  Future<void> _upload(FileOperation<YustFile> operation) async {
    final file = operation.file;
    final documentWriter = _documentWriterFor(operation);
    final localPath = await _storage.resolvePath(operation.fileKey);
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
    await _awaitDocumentWrite(
      documentWriter?.writeFile(file),
      'entry for "${file.name}"',
    );
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
  /// The byte delete still gates the operation: if it fails the operation stays queued and
  /// runs again, and re-detaching an already-detached entry is a no-op.
  Future<void> _delete(FileOperation<YustFile> operation) async {
    final file = operation.file;
    _startDocumentWrite(
      _documentWriterFor(operation)?.removeFile(file),
      'detaching "${file.name}"',
    );
    await Yust.fileService.deleteFile(
      path: file.storageFolderPath!,
      name: file.name,
    );
    await _storage.remove(operation.fileKey);
  }

  /// Re-writes the file's document entry with no byte transfer (e.g. after its
  /// favorite flag changed). Queued behind any upload of the same file, so it
  /// always lands on an entry that exists. The write is the whole operation, so it is
  /// handed off — see [_startDocumentWrite].
  Future<void> _updateMetadata(FileOperation<YustFile> operation) async =>
      _startDocumentWrite(
        _documentWriterFor(operation)?.writeFile(operation.file),
        'metadata for "${operation.file.name}"',
      );

  Future<void> _rename(FileOperation<YustFile> operation) async {
    final file = operation.file;
    final documentWriter = _documentWriterFor(operation);
    final oldName = file.name!;
    final newName = operation.newName!;
    final localPath = await _storage.resolvePath(operation.fileKey);
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
    await _awaitDocumentWrite(
      documentWriter?.removeFile(file),
      'old entry for "$oldName"',
    );
    file.name = newName;
    file.path = file.storageFolderPath;
    // ignore: deprecated_member_use
    file.url = url;
    await _awaitDocumentWrite(
      documentWriter?.writeFile(file),
      'entry for "$newName"',
    );
    await Yust.fileService.deleteFile(
      path: file.storageFolderPath!,
      name: oldName,
    );
  }

  /// Awaits a document write, but never longer than [_documentWriteTimeout]. Real
  /// failures propagate so the handler can classify them; only a missing
  /// acknowledgement is absorbed, since Firestore syncs it on reconnect.
  Future<void> _awaitDocumentWrite(
    Future<void>? write,
    String description,
  ) async {
    if (write == null) return;
    try {
      await write.timeout(_documentWriteTimeout);
    } on TimeoutException {
      debugPrint(
        '[offline-sync] $description not acknowledged within '
        '${_documentWriteTimeout.inSeconds}s — left to Firestore to sync',
      );
    }
  }

  /// Starts a document write without waiting for it, logging a failure. For operations
  /// whose work must not sit behind an acknowledgement offline never delivers.
  void _startDocumentWrite(Future<void>? write, String description) =>
      unawaited(
        write?.catchError(
          (Object error) =>
              debugPrint('[offline-sync] $description failed: $error'),
        ),
      );
}
