import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

import '../yust_file_helpers.dart';
import 'yust_file_operation.dart';
import 'yust_file_operation_error.dart';
import 'yust_offline_storage.dart';
import 'yust_sync_queue.dart';

/// Persists a single file's metadata to its linked document.
///
/// The offline manager is generic and never writes documents directly — a raw
/// Firestore write would bypass the host app's own write pipeline. The app
/// layer implements this so every file write funnels through one sanctioned
/// path.
abstract interface class YustOfflineFileDocumentWriter {
  /// Writes [file]'s metadata to its linked document, scoped to its own key.
  Future<void> writeFile(YustFile file);

  /// Removes [file]'s metadata from its linked document.
  Future<void> removeFile(YustFile file);
}

/// Drives every file change through the one [YustSyncQueue] and carries out
/// each operation: the outbound work (upload, rename, delete, metadata update)
/// that pushes to Storage and writes metadata back through a
/// [YustOfflineFileDocumentWriter], and the inbound work (download) that
/// fetches bytes into [YustOfflineStorage].
///
/// [processPendingOperations] applies the queue oldest-first and removes an
/// operation only on success. The flat queue is read as one FIFO per file:
/// only a file's oldest queued operation is eligible per sweep, so its own
/// operations stay in order while other files pass freely. A sweep that applied
/// nothing ends the pass; any failure schedules a retry with capped exponential
/// backoff (1s, 2s, 4s … 30s).
///
/// Operations are always attempted, never gated on a connectivity check.
/// Connectivity is a hint to retry sooner: a regained event resets the backoff
/// and requests another pass, coalescing if one is already running.
///
/// Failures are classified. Connection failures retry forever, untracked. A
/// failure retrying cannot fix ([YustFileOperationError.reasonFor]) ends the
/// operation on the spot: an upload keeps its reason and waits for the user to
/// acknowledge it via [discardOperationsForFile], since its bytes are on this
/// device and nowhere else; every other kind is dropped, because the change
/// simply did not happen. An unrecognised error counts as transient.
///
/// The document writer is resolved per operation via the `documentWriterFor`
/// callback from the file's own `linkedDocPath` / `linkedDocAttribute`. It may
/// return null: a picker bound to a host's settings has a storage folder but no
/// document.
///
/// No document write is awaited unbounded. A Firestore write resolves only on
/// server acknowledgement, which never comes offline, and the drain is serial.
/// Firestore's cache is itself a durable queue.
///
/// [enqueue] waits only for the operation to be durably queued, never for the
/// transfer.
///
/// Notifies whenever the queue changes, so a [YustFileListController] can
/// rebuild its pending-operation overlay without polling.
class YustFileOperationManager extends ChangeNotifier {
  YustFileOperationManager({
    required this.queue,
    required YustOfflineFileDocumentWriter? Function(
      YustFileOperation<YustFile>,
    )
    documentWriterFor,
    YustOfflineStorage? storage,
    Duration? documentWriteTimeout,
    // Emits true when the device regains connectivity; a new pass drains the
    // queue on reconnect. Defaults to [_defaultConnectivityStream].
    Stream<bool>? connectivityStream,
    Future<void> Function(Duration)? delay,
  }) : _documentWriterFor = documentWriterFor,
       _storage = storage ?? YustOfflineStorage.forDevice(),
       _documentWriteTimeout =
           documentWriteTimeout ?? defaultDocumentWriteTimeout,
       _delay = delay ?? ((duration) => Future<void>.delayed(duration)) {
    _connectivitySub = (connectivityStream ?? _defaultConnectivityStream)
        .listen(_onConnectivity);
  }

  /// How long a document write may take before the operation counts as done.
  /// Bounds only the document write; byte transfers keep Firebase's own window.
  static const defaultDocumentWriteTimeout = Duration(seconds: 30);

  /// The queue every operation — inbound and outbound — flows through.
  final YustSyncQueue queue;
  final Future<void> Function(Duration) _delay;

  /// Emits each operation right after it is applied and dropped from the queue.
  ///
  /// A listener receives this manager's own instance, so an applied upload
  /// already carries its `path` and `url`. Synchronous, so a listener has
  /// updated its state before the [notifyListeners] that follows.
  Stream<YustFileOperation<YustFile>> get applied => _applied.stream;

  final StreamController<YustFileOperation<YustFile>> _applied =
      StreamController<YustFileOperation<YustFile>>.broadcast(sync: true);

  static const _base = Duration(seconds: 1);
  static const _cap = Duration(seconds: 30);

  late final StreamSubscription<bool> _connectivitySub;
  int _attempt = 0;
  bool _isDraining = false;
  bool _retryScheduled = false;
  bool _disposed = false;

  /// The drain in flight, so overlapping callers can await it instead of
  /// starting a second one.
  Future<void>? _activeDrain;

  /// Set when a drain is requested while one is already running, so it loops
  /// once more instead of the request being dropped.
  bool _drainAgain = false;

  /// Appends [operation] and starts a drain, returning as soon as it is durably
  /// queued. The transfer itself is not awaited.
  ///
  /// Low-level. An upload/rename/updateMetadata operation must already have its
  /// bytes written to `YustOfflineStorage` and its hash set — for document-file
  /// mutations use `YustFileListController`, which does that bookkeeping first. A
  /// `YustFileOperationType.download` may be enqueued directly to fetch bytes (e.g.
  /// a sync reconcile).
  ///
  /// Throws [ArgumentError] for a file this manager could not address.
  Future<void> enqueue(YustFileOperation<YustFile> operation) async {
    _assertAddressable(operation);
    await queue.enqueueOperation(operation);
    await _notifyQueueChanged();
    unawaited(processPendingOperations());
  }

  /// Appends every addressable operation in [operations], then starts one drain.
  ///
  /// An unaddressable one is skipped rather than thrown on: a batch is a whole
  /// record's files, and one bad file must not stop the rest. Use [enqueue] to
  /// hear about it.
  Future<void> enqueueAll(
    Iterable<YustFileOperation<YustFile>> operations,
  ) async {
    final batch = operations.where(_isAddressable).toList();
    for (final operation in batch) {
      await queue.enqueueOperation(operation);
    }
    if (batch.isEmpty) return;
    await _notifyQueueChanged();
    unawaited(processPendingOperations());
  }

  /// Rejects an operation whose file this manager could not act on.
  ///
  /// [ArgumentError] because [YustFileOperationError.reasonFor] counts it as
  /// permanent; a `TypeError` from a null `!` counts as transient and retries
  /// forever.
  void _assertAddressable(YustFileOperation<YustFile> operation) {
    final file = operation.file;
    if (!file.hasName) {
      throw ArgumentError('Cannot queue a file without a name.');
    }
    if (file.hash.isEmpty) {
      throw ArgumentError(
        'Cannot queue "${file.name}" without a hash. Call '
        'YustFileOfflineKey.ensureHash first.',
      );
    }
    if (!_isAddressable(operation)) {
      throw ArgumentError(
        'Cannot queue ${operation.type.name} of "${file.name}" without a '
        'storage location.',
      );
    }
  }

  /// Whether this manager could act on [operation]'s file: it needs a name, a
  /// hash and a location. Writes need the Storage folder; a download can read
  /// from `path`.
  bool _isAddressable(YustFileOperation<YustFile> operation) {
    final file = operation.file;
    if (!file.hasName || file.hash.isEmpty) return false;
    return operation.type == YustFileOperationType.download
        ? file.hasStorageLocation
        : file.storageFolderPath?.isNotEmpty == true;
  }

  /// Drops a still-pending [operation] without applying it, e.g. a file deleted
  /// before its upload ran. [discardOperationsForFile] is the whole-file
  /// sibling of this.
  Future<void> cancel(YustFileOperation<YustFile> operation) async {
    await queue.removeOperation(operation);
    await _notifyQueueChanged();
  }

  /// Drops every operation still queued for [fileKey] — the one that failed and
  /// anything queued behind it.
  ///
  /// The whole chain goes: a file's operations are applied in order, so a rename
  /// queued behind a discarded upload would run against an object that never
  /// arrived.
  Future<void> discardOperationsForFile(String fileKey) async {
    for (final operation in await queue.getPendingOperations()) {
      if (operation.fileKey == fileKey) await queue.removeOperation(operation);
    }
    await _notifyQueueChanged();
  }

  /// This manager's pending operations, oldest-first.
  Future<List<YustFileOperation<YustFile>>> pending() =>
      queue.getPendingOperations();

  /// Whether [file]'s bytes are still on their way to Storage. Synchronous, so
  /// a widget can ask while it builds; listen to this manager to rebuild when it
  /// changes.
  ///
  /// An upload that failed for good is not in flight — the pickers report those.
  bool isUploading(YustFile file) =>
      _uploadingFileKeys.contains(file.offlineKey);

  /// Backs [isUploading]. Refreshed with every change to the queue, since the
  /// queue itself can only be read asynchronously.
  Set<String> _uploadingFileKeys = {};

  /// Re-reads the queue, then notifies. The one way this manager announces a
  /// change, so [isUploading] can never disagree with the listeners it wakes.
  Future<void> _notifyQueueChanged() async {
    _uploadingFileKeys = (await queue.getPendingOperations())
        .where(
          (operation) =>
              operation.type == YustFileOperationType.upload &&
              !operation.hasFailed,
        )
        .map((operation) => operation.fileKey)
        .toSet();
    if (!_disposed) notifyListeners();
  }

  /// Drains the queue, and completes when the drain in flight does.
  ///
  /// Only one drain runs at a time so two passes never race on the same operation. A
  /// caller arriving while one is running joins it rather than being dropped:
  /// it gets the running pass to await, and asks for one more pass afterwards
  /// so work that arrived mid-pass — a reconnect, a freshly enqueued operation — is
  /// never missed.
  Future<void> processPendingOperations() {
    if (_disposed) return Future<void>.value();
    if (_isDraining) {
      _drainAgain = true;
      return _activeDrain ?? Future<void>.value();
    }
    _isDraining = true;
    final drain = _drainUntilSettled().whenComplete(() {
      _isDraining = false;
      _activeDrain = null;
    });
    _activeDrain = drain;
    return drain;
  }

  /// Runs passes until no further one was requested while the last was running.
  Future<void> _drainUntilSettled() async {
    do {
      _drainAgain = false;
      await _drain();
    } while (_drainAgain && !_disposed);
  }

  /// One pass: applies what it can, oldest-first, skipping what fails.
  ///
  /// The queue is re-read after each sweep so an operation enqueued mid-pass is picked
  /// up without waiting for the next trigger. A sweep that applied nothing ends
  /// the pass — re-reading would hand back the same failing operations and spin.
  Future<void> _drain() async {
    var failed = false;
    final failedOperationIdsThisPass = <String>{};
    for (
      var pending = await queue.getPendingOperations();
      pending.isNotEmpty;
      pending = await queue.getPendingOperations()
    ) {
      var applied = 0;
      for (final operation in _nextOperationPerFile(pending)) {
        if (_disposed) return;
        // One attempt per operation per pass; the backoff owns the next one.
        if (failedOperationIdsThisPass.contains(operation.id)) continue;
        try {
          await _executeOperation(operation);
          await queue.removeOperation(operation);
          _applied.add(operation);
          await _notifyQueueChanged();
          applied++;
        } catch (error) {
          failed = true;
          failedOperationIdsThisPass.add(operation.id);
          await _recordFailure(operation, error);
        }
      }
      if (applied == 0) break;
    }
    if (failed) {
      _scheduleRetry();
    } else {
      _attempt = 0; // fully drained → reset backoff
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_connectivitySub.cancel());
    unawaited(_applied.close());
    super.dispose();
  }

  /// The oldest queued operation of each file, in the order the files first appear —
  /// the flat queue read as one FIFO per file. A file whose oldest operation has
  /// failed yields nothing, holding its whole chain until the user discards it.
  Iterable<YustFileOperation<YustFile>> _nextOperationPerFile(
    List<YustFileOperation<YustFile>> pending,
  ) {
    final firstOperationForFile = <String, YustFileOperation<YustFile>>{};
    for (final operation in pending) {
      firstOperationForFile.putIfAbsent(operation.fileKey, () => operation);
    }
    return firstOperationForFile.values.where(
      (operation) => !operation.hasFailed,
    );
  }

  /// Ends [operation] on a failure no retry can fix. A connection failure
  /// records nothing and is left to the backoff.
  ///
  /// Only an upload is kept for the user: its bytes are on this device and
  /// nowhere else, so dropping it would lose them. Every other operation is a
  /// change the server can simply not have — the file keeps its old name, stays
  /// undeleted, keeps its old metadata — and the display is the document
  /// snapshot overlaid with this queue, so removing the operation is what puts
  /// the user back on the server's state. A download is not even that: its bytes
  /// are still in Storage, and the offline sync re-enqueues whatever is missing.
  Future<void> _recordFailure(
    YustFileOperation<YustFile> operation,
    Object error,
  ) async {
    final reason = YustFileOperationError.reasonFor(error);
    if (reason == null) return;
    if (operation.type == YustFileOperationType.upload) {
      operation.failure = reason;
      await queue.saveToDisk();
    } else {
      await queue.removeOperation(operation);
    }
    await _notifyQueueChanged();
  }

  void _onConnectivity(bool online) {
    if (online && !_disposed) {
      _attempt = 0;
      unawaited(processPendingOperations());
    }
  }

  void _scheduleRetry() {
    if (_retryScheduled || _disposed) return;
    _retryScheduled = true;
    final delay = _nextDelay();
    if (delay < _cap) _attempt++;
    unawaited(
      _delay(delay).then((_) {
        _retryScheduled = false;
        if (!_disposed) unawaited(processPendingOperations());
      }),
    );
  }

  Duration _nextDelay() {
    // 1 << _attempt = 2^_attempt: doubles the base delay each retry
    // (1s, 2s, 4s…), capped at _cap.
    final raw = _base.inMilliseconds * (1 << _attempt);
    return Duration(
      milliseconds: raw < _cap.inMilliseconds ? raw : _cap.inMilliseconds,
    );
  }

  final YustOfflineFileDocumentWriter? Function(YustFileOperation<YustFile>)
  _documentWriterFor;
  final Duration _documentWriteTimeout;
  final YustOfflineStorage? _storage;

  /// Carries out [operation]: its byte work and document write.
  Future<void> _executeOperation(YustFileOperation<YustFile> operation) =>
      switch (operation.type) {
        YustFileOperationType.upload => _upload(operation),
        YustFileOperationType.rename => _rename(operation),
        YustFileOperationType.delete => _delete(operation),
        YustFileOperationType.updateMetadata => _updateMetadata(operation),
        YustFileOperationType.download => _download(operation),
      };

  /// Pushes the bytes to Storage, writes the entry, then drops the entry these
  /// bytes supersede ([YustFileOperation.supersededHash]).
  ///
  /// Both document writes happen here, in this order, so the document never
  /// holds two entries for the one file and never holds none.
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
    await _removeSupersededEntry(operation, documentWriter);
  }

  /// Drops the entry [operation]'s bytes superseded, leaving every byte in
  /// place — [_delete] without the Storage delete.
  ///
  /// The Storage object under this name now holds the replacing bytes, and the
  /// device copy is keyed by content and shared with every other entry holding
  /// it. Nothing to do when the upload superseded no entry or landed on the
  /// same key, which would drop the entry just written. Removing an absent
  /// entry is a no-op, so a retry is safe.
  Future<void> _removeSupersededEntry(
    YustFileOperation<YustFile> operation,
    YustOfflineFileDocumentWriter? documentWriter,
  ) async {
    final supersededHash = operation.supersededHash;
    final file = operation.file;
    if (supersededHash == null || supersededHash == file.hash) return;
    await _awaitDocumentWrite(
      documentWriter?.removeFile(file.copyWithUrl(null)..hash = supersededHash),
    );
  }

  /// Removes the file's document entry, then deletes its Storage object.
  ///
  /// The document write is awaited: until it lands the document points at bytes
  /// this operation is about to delete, and a failed write retries the whole
  /// operation rather than being lost. Removing an absent entry is a no-op.
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
  /// One write: the entry is keyed by content hash, which a rename leaves
  /// alone, so it replaces itself.
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
    // The same bytes under the new name (bytes unchanged → same hash): from the
    // device copy when there is one, else copied within Storage.
    final url = localPath != null
        ? await Yust.fileService.uploadFile(
            path: file.storageFolderPath!,
            name: newName,
            file: File(localPath),
            linkedDocPath: file.linkedDocPath,
            linkedDocAttribute: file.linkedDocAttribute,
            createThumbnail: file.createThumbnail,
          )
        : await Yust.fileService.copyFile(
            path: file.storageFolderPath!,
            name: oldName,
            newName: newName,
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
    final bytes = await Yust.fileService.downloadFileOrThrow(
      path: storageFolder,
      name: file.name!,
    );
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

  Stream<bool> get _defaultConnectivityStream => YustFileHelpers
      .connectivityStream
      .map((results) => results.any((r) => r != ConnectivityResult.none));
}
