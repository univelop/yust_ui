import 'dart:async';
import 'dart:io';

import 'package:yust/yust.dart';

import 'yust_download_manager.dart';
import 'yust_file_operation.dart';
import 'yust_file_operation_handler.dart';
import 'yust_offline_storage.dart';

/// Persists a single file's metadata to its linked document.
///
/// The offline managers are generic and never write records directly — a raw
/// Firestore write would bypass the app's permission, workspace-lock and
/// trigger pipeline. The app layer implements this so every file write funnels
/// through one sanctioned path.
abstract interface class YustOfflineFileDocumentWriter {
  /// Writes [file]'s metadata to its linked document, scoped to its own key.
  Future<void> writeFile(YustFile file);

  /// Removes [file]'s metadata from its linked document.
  Future<void> removeFile(YustFile file);
}

/// The outbound executor: pushes an upload, rename, delete or metadata update
/// to Storage and writes its metadata back through an
/// [YustOfflineFileDocumentWriter]. Queueing, retries and connectivity are the
/// [YustFileOperationHandler]'s job.
///
/// One shared manager drains operations for every record and brick, so the
/// document writer is resolved per operation via [documentWriterFor] from the
/// file's own `linkedDocPath` / `linkedDocAttribute`. It may return null: a
/// picker bound to a brick's settings has a storage folder but no record.
///
/// No document write is awaited unbounded. A Firestore write resolves only on
/// server acknowledgement, which never comes offline, and the drain is serial.
/// Firestore's cache is itself a durable queue.
class YustUploadManager implements YustFileOperationExecutor {
  YustUploadManager({
    required YustOfflineFileDocumentWriter? Function(YustFileOperation<YustFile>)
    documentWriterFor,
    YustOfflineStorage? storage,
    Duration? documentWriteTimeout,
  }) : _documentWriterFor = documentWriterFor,
       _storage = storage ?? YustOfflineStorage.forDevice(),
       _documentWriteTimeout =
           documentWriteTimeout ?? defaultDocumentWriteTimeout;

  /// How long a document write may take before the operation counts as done.
  /// Bounds only the record write; byte transfers keep Firebase's own window.
  static const defaultDocumentWriteTimeout = Duration(seconds: 30);

  final YustOfflineFileDocumentWriter? Function(YustFileOperation<YustFile>)
  _documentWriterFor;
  final Duration _documentWriteTimeout;
  final YustOfflineStorage? _storage;

  @override
  Set<YustFileOperationType> get handledTypes => {
    YustFileOperationType.upload,
    YustFileOperationType.rename,
    YustFileOperationType.delete,
    YustFileOperationType.updateMetadata,
  };

  @override
  Future<void> execute(YustFileOperation<YustFile> operation) =>
      switch (operation.type) {
        YustFileOperationType.upload => _upload(operation),
        YustFileOperationType.rename => _rename(operation),
        YustFileOperationType.delete => _delete(operation),
        YustFileOperationType.updateMetadata => _updateMetadata(operation),
        YustFileOperationType.download => throw StateError(
          'download is not an upload operation',
        ),
      };

  Future<void> _upload(YustFileOperation<YustFile> operation) async {
    final file = operation.file;
    final documentWriter = _documentWriterFor(operation);
    final localPath = await _storage?.pathForFile(file.byteKey);
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
    await _awaitDocumentWrite(documentWriter?.writeFile(file));
  }

  /// Detaches the file's record entry, then deletes its bytes.
  ///
  /// The detach is awaited, not handed off: an array-layout attribute is
  /// rewritten from a read of the record, so the next operation's write would
  /// read the entry back in and resurrect it — pointing at bytes this operation
  /// has already deleted. Awaiting also means a failed detach retries the whole
  /// operation instead of being logged and lost; re-detaching a detached entry
  /// is a no-op.
  Future<void> _delete(YustFileOperation<YustFile> operation) async {
    final file = operation.file;
    await _awaitDocumentWrite(_documentWriterFor(operation)?.removeFile(file));
    await Yust.fileService.deleteFile(
      path: file.storageFolderPath!,
      name: file.name,
    );
    await _storage?.removeFile(file.byteKey);
  }

  /// Re-writes the file's document entry with no byte transfer, e.g. after its
  /// favorite flag changed. Queued behind any upload of the same file, so it
  /// lands on an entry that exists, and awaited like every other record write
  /// so the operation after it reads the result rather than the state before.
  Future<void> _updateMetadata(YustFileOperation<YustFile> operation) =>
      _awaitDocumentWrite(
        _documentWriterFor(operation)?.writeFile(operation.file),
      );

  Future<void> _rename(YustFileOperation<YustFile> operation) async {
    final file = operation.file;
    final documentWriter = _documentWriterFor(operation);
    final oldName = file.name!;
    final newName = operation.newName!;
    final localPath = await _storage?.pathForFile(file.byteKey);
    // Reupload the same bytes under the new name (bytes unchanged → same hash).
    final bytes = localPath == null
        ? await Yust.fileService.downloadFile(
            path: file.storageFolderPath!,
            name: oldName,
          )
        : null;
    // A failed download comes back as empty bytes, not an error. Uploading them
    // would write a 0-byte object and detach the old entry — losing the file.
    if (localPath == null && (bytes == null || bytes.isEmpty)) {
      throw await missingOrUnreachable(file.storageFolderPath!, oldName);
    }
    final url = await Yust.fileService.uploadFile(
      path: file.storageFolderPath!,
      name: newName,
      file: localPath != null ? File(localPath) : null,
      bytes: bytes,
      linkedDocPath: file.linkedDocPath,
      linkedDocAttribute: file.linkedDocAttribute,
    );
    // The map layout keys both on the same hash, so the old entry goes first.
    await _awaitDocumentWrite(documentWriter?.removeFile(file));
    file.name = newName;
    file.path = file.storageFolderPath;
    // ignore: deprecated_member_use
    file.url = url;
    await _awaitDocumentWrite(documentWriter?.writeFile(file));
    await Yust.fileService.deleteFile(
      path: file.storageFolderPath!,
      name: oldName,
    );
  }

  /// Awaits a document write, but never longer than [_documentWriteTimeout].
  /// Failures propagate; a missing acknowledgement is absorbed and left to
  /// Firestore to sync.
  Future<void> _awaitDocumentWrite(Future<void>? write) async {
    if (write == null) return;
    try {
      await write.timeout(_documentWriteTimeout);
    } on TimeoutException {
      // Offline, a write never acks; Firestore's cache carries it.
    }
  }
}
