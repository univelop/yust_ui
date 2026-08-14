import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

import 'file_operation.dart';
import 'file_operation_handler.dart';
import 'file_upload_decision.dart';
import 'offline_file_target.dart';
import 'offline_storage.dart';

/// Widget-facing model for a brick's file list.
///
/// Shows the record's persisted files overlaid with the pending operations still in the
/// shared [FileOperationHandler]'s queue: a pending add shows straight from its
/// on-device bytes, a pending delete is hidden, a pending rename shows the new
/// name. The list-model concern that used to be tangled inside `YustFileHandler`;
/// here every change is a stateless command (write local bytes → enqueue an operation),
/// and the display is derived — the queue is the single source of "not yet
/// synced", replacing the old in-memory tombstone.
class FileListController<T extends YustFile> extends ChangeNotifier {
  FileListController({
    required this.handler,
    required this.target,
    OfflineStorage? storage,
    this.newestFirst = false,
    this.onOnlineFilesChanged,
  }) : _storage = storage ?? OfflineStorage() {
    handler.addListener(_onQueueChanged);
    _appliedSub = handler.applied.listen(_onOperationApplied);
  }

  /// The one app-scoped handler every file change flows through.
  final FileOperationHandler handler;

  /// Where this brick's files live (stamps files, filters pending operations).
  final OfflineFileTarget target;

  final OfflineStorage _storage;

  /// Whether the newest file is shown first.
  bool newestFirst;

  /// Notified with the current online files when **this host is the one that has
  /// to persist them** — see [_emitOnlineFiles].
  final void Function(List<T>)? onOnlineFilesChanged;

  /// Persisted files from the record snapshot (last [setOnlineFiles]).
  final List<T> _online = [];

  /// This target's pending operations, oldest-first (mirrors the queue).
  List<FileOperation<YustFile>> _pending = [];

  /// Files this device has just uploaded, carried across one reconciliation.
  ///
  /// The doc write and the record stream race: a snapshot already in flight
  /// when the write landed still lacks the file, and reconciling against it
  /// would drop the file from the list until the next emission. (The old
  /// `YustFileHandler` kept a `_recentlyUploadedFiles` set for the same reason.)
  ///
  /// Held for a *single* [setOnlineFiles] only. Keeping entries until they show
  /// up would resurrect a file another device deleted in the meantime, which is
  /// worse than one frame of flicker.
  final Map<String, T> _justUploaded = {};

  late final StreamSubscription<FileOperation<YustFile>> _appliedSub;

  /// The chain of refreshes requested so far; see [settled].
  Future<void> _refresh = Future<void>.value();

  bool _disposed = false;

  /// The files to display: the record snapshot overlaid with pending operations,
  /// honouring [newestFirst].
  List<T> get files {
    final overlaid = _overlay();
    return newestFirst ? overlaid.reversed.toList(growable: false) : overlaid;
  }

  /// Files already persisted in the record.
  List<T> get onlineFiles => _overlay().where(_isOnline).toList();

  /// Files with an on-device copy (pending upload or downloaded for offline).
  List<T> get cachedFiles => _overlay().where((file) => file.cached).toList();

  /// Whether [file] is still queued for upload, i.e. it exists on this device
  /// but not yet in Storage. Drives the "not yet uploaded" marker.
  bool isPendingUpload(T file) => _pendingUploadFor(file) != null;

  /// Whether one of [file]'s queued operations is timed out — out of failedAttempts and waiting
  /// on the user. Drives the "could not be synced" marker.
  bool isTimedOut(T file) => _pending.any(
    (operation) =>
        operation.fileKey == file.offlineKey &&
        operation.failedAttempts >= FileOperationHandler.maxFailedAttempts,
  );

  /// Whether [file] is persisted in the record.
  ///
  /// A queued upload disqualifies it: both pickers stamp `path` at pick time,
  /// before any upload has run, so a storage location alone cannot tell a
  /// picked file from an uploaded one — only the queue can. Reporting a picked
  /// file as online is what wrote url-less entries into the record and let a
  /// stale list overwrite another device's files.
  bool _isOnline(T file) =>
      _pendingUploadFor(file) == null &&
      // ignore: deprecated_member_use
      (file.path != null || file.url != null);

  /// Overlays the pending operations onto the record snapshot, keyed by content hash
  /// (or name for hashless legacy files). A pending add/replace shows its local
  /// bytes; a pending delete is hidden. A rename or metadata update is already
  /// reflected on the online instance (mutated optimistically by [rename] /
  /// [updateMetadata]), so neither needs an entry.
  List<T> _overlay() {
    final byKey = <String, T>{
      for (final file in _online) file.offlineKey: file,
    };
    for (final operation in _pending) {
      switch (operation.type) {
        case FileOperationType.upload:
          byKey[operation.fileKey] = operation.file as T;
        case FileOperationType.delete:
          byKey.remove(operation.fileKey);
        case FileOperationType.rename:
        case FileOperationType.updateMetadata:
        case FileOperationType.download:
          break;
      }
    }
    return List<T>.unmodifiable(byKey.values);
  }

  /// Reconciles the list with the [incoming] online files from the record.
  /// Call on init and whenever the brick value changes.
  ///
  /// A file uploaded here since the last reconciliation is carried over when
  /// [incoming] does not have it yet — see [_justUploaded].
  Future<void> setOnlineFiles(List<T> incoming) async {
    final incomingKeys = incoming.map((file) => file.offlineKey).toSet();
    final carried = _justUploaded.values
        .where((file) => !incomingKeys.contains(file.offlineKey))
        .toList();
    _justUploaded.clear();
    _online
      ..clear()
      ..addAll(incoming)
      ..addAll(carried);
    for (final file in _online) {
      target.apply(file);
      final path = await _storage.pathForFile(file);
      if (path != null) file.devicePath = path;
    }
    await _refreshPending();
  }

  /// Adds [file]: writes its bytes to the device, then enqueues the upload
  /// (which persists via the shared handler's document writer). Shown immediately
  /// through the pending overlay.
  ///
  /// Returns only once the overlay reflects the new operation. The caller reads
  /// [onlineFiles] the moment this completes and writes it to the record, so a
  /// stale overlay there would report the queued file as persisted and store an
  /// entry for bytes that are not in Storage yet.
  Future<void> add(T file) async {
    target.apply(file);
    await file.ensureHash();
    await _writeBytes(file);
    await handler.enqueue(_uploadOperation(FileOperationType.upload, file));
    await _scheduleRefresh();
  }

  /// Replaces [file]'s bytes (e.g. a re-drawn signature/image) and re-uploads.
  Future<void> replaceBytes(T file, Uint8List bytes) async {
    target.apply(file);
    file
      ..bytes = bytes
      ..hash = '';
    await file.ensureHash();
    await _writeBytes(file);
    await handler.enqueue(_uploadOperation(FileOperationType.upload, file));
    await _scheduleRefresh();
  }

  /// Deletes [file]: a file still queued for upload is dropped from the queue
  /// (and its bytes removed); an already-persisted file is removed via a delete
  /// operation.
  Future<void> delete(T file) async {
    target.apply(file);
    // Deleted here, so it must not be carried across the next reconciliation.
    _justUploaded.remove(file.offlineKey);
    final pendingUploadOperation = _pendingUploadFor(file);
    if (pendingUploadOperation != null) {
      await handler.cancel(pendingUploadOperation);
      await _storage.removeFile(file);
      await _scheduleRefresh();
      return;
    }
    if (_isOnline(file)) {
      await handler.enqueue(_uploadOperation(FileOperationType.delete, file));
    }
    await _scheduleRefresh();
  }

  /// Renames [file] to [newName]: the displayed instance is updated at once,
  /// while the operation carries an old-name snapshot so the executor can still fetch
  /// the original bytes to re-upload under the new name.
  Future<void> rename(T file, String newName) async {
    final snapshot = file.copyWithUrl(null)
      ..linkedDocStoresFilesAsMap = file.linkedDocStoresFilesAsMap;
    file.name = newName;
    await handler.enqueue(
      FileOperation<YustFile>(
        type: FileOperationType.rename,
        file: snapshot,
        newName: newName,
      ),
    );
    await _scheduleRefresh();
  }

  /// Persists a metadata-only change to [file] (e.g. its favorite flag), which
  /// the caller has already applied to the instance.
  ///
  /// A file still queued for upload needs no operation of its own: the queued upload
  /// carries this same instance and writes the current metadata when it runs.
  Future<void> updateMetadata(T file) async {
    target.apply(file);
    if (_pendingUploadFor(file) == null) {
      await handler.enqueue(
        _uploadOperation(FileOperationType.updateMetadata, file),
      );
    }
    await _scheduleRefresh();
  }

  /// Resolves how uploading a file named [newFileName] applies to the current
  /// list, honouring [numberOfFiles] and single-file overwrite. Pure — the
  /// caller reacts (confirm dialog / block); see [resolveFileUpload].
  FileUploadDecision<T> resolveUpload({
    required String newFileName,
    required int numberOfFiles,
    required bool overwriteSingleFile,
  }) => resolveFileUpload<T>(
    currentFiles: _overlay(),
    newFileName: newFileName,
    numberOfFiles: numberOfFiles,
    overwriteSingleFile: overwriteSingleFile,
  );

  /// Retries any queued operations (e.g. on reconnect / app start).
  Future<void> flushUploads() => handler.processPendingOperations();

  /// Completes once every refresh requested so far has been applied.
  ///
  /// Refreshes are triggered by the handler's notification and run detached, so
  /// this is the only way to know the list has caught up with the queue.
  @visibleForTesting
  Future<void> get settled => _refresh;

  @override
  void dispose() {
    _disposed = true;
    handler.removeListener(_onQueueChanged);
    unawaited(_appliedSub.cancel());
    super.dispose();
  }

  void _onQueueChanged() => unawaited(_scheduleRefresh());

  /// Queues a refresh behind the one before it — so two overlapping
  /// notifications cannot interleave and leave [_pending] on the older read —
  /// and completes once it has run.
  Future<void> _scheduleRefresh() {
    _refresh = _refresh
        .then((_) => _refreshPending())
        // Keep the chain alive past a failure so one error can't wedge it.
        .catchError((Object _) {});
    return _refresh;
  }

  /// Adopts a file whose upload has just been applied into the persisted set.
  ///
  /// Without this the file would vanish the moment its operation left the queue: the
  /// pending overlay stops carrying it, and the record snapshot that would
  /// carry it has not arrived yet. The operation's file is the executor's own
  /// instance, so it already has the `path` and `url` the upload produced.
  void _onOperationApplied(FileOperation<YustFile> operation) {
    if (_disposed) return;
    if (operation.type != FileOperationType.upload ||
        !target.owns(operation.file))
      return;
    final file = operation.file as T;
    final key = file.offlineKey;
    final index = _online.indexWhere((online) => online.offlineKey == key);
    if (index == -1) {
      _online.add(file);
    } else {
      _online[index] = file;
    }
    _justUploaded[key] = file;
  }

  /// Re-reads this target's operations from the queue.
  ///
  /// The disposal check is after the await, not just before: the picker can be
  /// torn down while this read is in flight (a file added, then the screen
  /// closed), and notifying a disposed [ChangeNotifier] throws.
  Future<void> _refreshPending() async {
    if (_disposed) return;
    final all = await handler.pending();
    if (_disposed) return;
    _pending = all.where((operation) => target.owns(operation.file)).toList();
    _emitOnlineFiles();
    notifyListeners();
  }

  FileOperation<YustFile>? _pendingUploadFor(T file) {
    for (final operation in _pending) {
      if (operation.type == FileOperationType.upload &&
          operation.fileKey == file.offlineKey) {
        return operation;
      }
    }
    return null;
  }

  /// Writes [file]'s bytes (or source file) to [OfflineStorage] and sets its
  /// [YustFile.devicePath]. Stays null on web, where nothing is cached.
  Future<void> _writeBytes(YustFile file) async {
    final key = file.offlineKey;
    if (key.isEmpty || file.name == null) return;
    file.devicePath = await _storage.write(
      hash: key,
      name: file.name!,
      bytes: file.bytes,
      file: file.file,
    );
  }

  FileOperation<YustFile> _uploadOperation(
    FileOperationType type,
    YustFile file,
  ) => FileOperation<YustFile>(type: type, file: file);

  /// Reports the persisted set to the host — but only for an unlinked target.
  ///
  /// A linked target ([OfflineFileTarget.isLinked]) has a document, so the
  /// queue's own writer persists every file and the host learns about it from
  /// the document stream. Reporting there would make the host write the same
  /// list a second time, which rebuilds the picker, which reconciles, which
  /// reports again — the loop that rebuilt the screen on every keystroke.
  ///
  /// Without a document there is no writer, so the host (a picker bound to a
  /// brick's settings, an email attachment list) is the only thing that can
  /// persist the files, and it has to be told.
  void _emitOnlineFiles() {
    if (target.isLinked) return;
    onOnlineFilesChanged?.call(onlineFiles);
  }
}
