import 'dart:async';
import 'dart:io';

import 'package:yust/yust.dart';

import 'yust_file_operation.dart';
import 'yust_file_operation_error.dart';
import 'yust_offline_storage.dart';

/// Persists a single file's metadata to its linked document.
///
/// The offline managers are generic and never write documents directly — a raw
/// Firestore write would bypass the host app's own write pipeline. The app
/// layer implements this so every file write funnels through one sanctioned
/// path.
abstract interface class YustOfflineFileDocumentWriter {
  /// Writes [file]'s metadata to its linked document, scoped to its own key.
  Future<void> writeFile(YustFile file);

  /// Removes [file]'s metadata from its linked document.
  Future<void> removeFile(YustFile file);
}

/// Carries out every kind of file operation: the outbound work (upload, rename,
/// delete, metadata update) that pushes to Storage and writes metadata back
/// through a [YustOfflineFileDocumentWriter], and the inbound work (download)
/// that fetches bytes into [YustOfflineStorage]. Queueing, retries and
/// connectivity are the [YustFileOperationHandler]'s job.
///
/// The document writer is resolved per operation via [documentWriterFor] from
/// the file's own `linkedDocPath` / `linkedDocAttribute`. It may return null: a
/// picker bound to a host's settings has a storage folder but no document.
///
/// No document write is awaited unbounded. A Firestore write resolves only on
/// server acknowledgement, which never comes offline, and the drain is serial.
/// Firestore's cache is itself a durable queue.
class YustFileOperationManager {
  YustFileOperationManager({
    required YustOfflineFileDocumentWriter? Function(
      YustFileOperation<YustFile>,
    )
    documentWriterFor,
    YustOfflineStorage? storage,
    Duration? documentWriteTimeout,
  }) : _documentWriterFor = documentWriterFor,
       _storage = storage ?? YustOfflineStorage.forDevice(),
       _documentWriteTimeout =
           documentWriteTimeout ?? defaultDocumentWriteTimeout;

  /// How long a document write may take before the operation counts as done.
  /// Bounds only the document write; byte transfers keep Firebase's own window.
  static const defaultDocumentWriteTimeout = Duration(seconds: 30);

  /// Carries out [operation]: its byte work and document write.
  Future<void> execute(YustFileOperation<YustFile> operation) =>
      switch (operation.type) {
        YustFileOperationType.upload => _upload(operation),
        YustFileOperationType.rename => _rename(operation),
        YustFileOperationType.delete => _delete(operation),
        YustFileOperationType.updateMetadata => _updateMetadata(operation),
        YustFileOperationType.download => _download(operation),
      };

  final YustOfflineFileDocumentWriter? Function(YustFileOperation<YustFile>)
  _documentWriterFor;
  final Duration _documentWriteTimeout;
  final YustOfflineStorage? _storage;

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

  /// Detaches the file's document entry, then deletes its Storage object.
  ///
  /// The detach is awaited: until it lands the document points at bytes this
  /// operation is about to delete, and a failed detach retries the whole
  /// operation rather than being lost. Re-detaching is a no-op.
  ///
  /// The on-device bytes stay: they are keyed by content hash, so freeing them
  /// here would take the offline copy from every other record holding the same
  /// file. Whoever owns the offline selection reclaims them instead.
  Future<void> _delete(YustFileOperation<YustFile> operation) async {
    final file = operation.file;
    await _awaitDocumentWrite(_documentWriterFor(operation)?.removeFile(file));
    await Yust.fileService.deleteFile(
      path: file.storageFolderPath!,
      name: file.name,
    );
  }

  /// Re-writes the file's document entry with no byte transfer, e.g. after its
  /// favorite flag changed. Queued behind any upload of the same file, so it
  /// lands on an entry that exists, and awaited like every other document write
  /// so the operation after it reads the result rather than the state before.
  Future<void> _updateMetadata(YustFileOperation<YustFile> operation) =>
      _awaitDocumentWrite(
        _documentWriterFor(operation)?.writeFile(operation.file),
      );

  /// Re-uploads the bytes under [YustFileOperation.newName], points the
  /// document entry at it, and deletes the old Storage object.
  ///
  /// One write, no detach: the entry is keyed by content hash, which a rename
  /// leaves alone, so it replaces itself.
  ///
  /// Works on [renamed], never on `operation.file`: the queue hands out live
  /// entries, so a mutated name would survive into the retry, which would then
  /// delete the object it just wrote.
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
      throw await YustFileOperationError.missingOrUnreachable(
        file.storageFolderPath!,
        oldName,
      );
    }
    final url = await Yust.fileService.uploadFile(
      path: file.storageFolderPath!,
      name: newName,
      file: localPath != null ? File(localPath) : null,
      bytes: bytes,
      linkedDocPath: file.linkedDocPath,
      linkedDocAttribute: file.linkedDocAttribute,
      createThumbnail: file.createThumbnail,
    );
    final renamed = file.copyWithUrl(url)
      ..name = newName
      ..path = file.storageFolderPath;
    await _awaitDocumentWrite(documentWriter?.writeFile(renamed));
    await Yust.fileService.deleteFile(
      path: file.storageFolderPath!,
      name: oldName,
    );
  }

  /// Downloads [operation]'s file and keeps its bytes on the device, setting the
  /// [YustFile.devicePath]. Skips the fetch when a copy already exists; a no-op
  /// when the file has no location.
  Future<void> _download(YustFileOperation<YustFile> operation) async {
    final file = operation.file;
    final storageFolder = file.storageFolderPath ?? file.path;
    // Nothing to fetch: storageFolderPath and path are both empty.
    if (file.name == null || storageFolder == null || storageFolder.isEmpty) {
      return;
    }
    final storage = _storage;
    // Nowhere to keep the bytes, so fetching them would only discard them.
    if (storage == null) return;
    if (await storage.hasFile(file.byteKey)) {
      file.devicePath = await storage.pathForFile(file.byteKey);
      return;
    }
    final bytes = await Yust.fileService.downloadFile(
      path: storageFolder,
      name: file.name!,
    );
    // downloadFile returns empty on any failure (never null), so an empty result
    // is a failed fetch, not a 0-byte file — throw to keep the operation queued
    // rather than cache a broken "available offline" file.
    if (bytes == null || bytes.isEmpty) {
      throw await YustFileOperationError.missingOrUnreachable(
        storageFolder,
        file.name!,
      );
    }
    file.devicePath = await storage.writeBytes(
      byteKey: file.byteKey,
      name: file.name!,
      bytes: bytes,
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
