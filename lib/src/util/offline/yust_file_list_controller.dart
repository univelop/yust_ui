import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

import 'yust_file_operation.dart';
import 'yust_file_operation_handler.dart';
import 'yust_firebase_file_location.dart';
import 'yust_offline_storage.dart';

/// Widget-facing model for a host's file list.
///
/// Shows the document's persisted files overlaid with the pending operations in
/// the shared [YustFileOperationHandler]'s queue: a pending add shows from its
/// on-device bytes, a pending delete is hidden, a pending rename shows the new
/// name. Every change is a command (write local bytes, enqueue an operation);
/// the display is derived from the queue.
class YustFileListController<T extends YustFile> extends ChangeNotifier {
  YustFileListController({
    required this.handler,
    required this.firebaseLocation,
    YustOfflineStorage? storage,
    this.newestFirst = false,
    this.onOnlineFilesChanged,
  }) : _storage = storage ?? YustOfflineStorage.forDevice() {
    handler.addListener(_onQueueChanged);
    _appliedSub = handler.applied.listen(_onOperationApplied);
  }

  /// The one app-scoped handler every file change flows through.
  final YustFileOperationHandler handler;

  /// Where this host's files live (stamps files, filters pending operations).
  final YustFirebaseFileLocation firebaseLocation;

  final YustOfflineStorage? _storage;

  /// Whether the newest file is shown first.
  bool newestFirst;

  /// Notified with the current online files when this host is the one that has
  /// to persist them — see [_emitOnlineFiles].
  final void Function(List<T>)? onOnlineFilesChanged;

  /// Persisted files from the document snapshot (last [setOnlineFiles]).
  final List<T> _online = [];

  /// Signature of the last [setOnlineFilesIfChanged] call, so a host that seeds
  /// from its build (a widget that is rebuilt each frame) skips
  /// reconciling to a value it already holds — and cannot loop through the
  /// notifyListeners that [setOnlineFiles] ends with.
  String? _lastOnlineFilesSignature;

  /// This location's pending operations, oldest-first (mirrors the queue).
  List<YustFileOperation<YustFile>> _pendingOperations = [];

  /// Files this device has just uploaded, carried across one reconciliation.
  ///
  /// The document write and the document stream race, so a snapshot in flight
  /// when the write landed still lacks the file. Held for a single
  /// [setOnlineFiles] only, so a file another device deleted stays deleted.
  final Map<String, T> _recentlyUploaded = {};

  late final StreamSubscription<YustFileOperation<YustFile>> _appliedSub;

  /// The chain of refreshes requested so far; see [settled].
  Future<void> _refresh = Future<void>.value();

  bool _disposed = false;

  /// The files to display: the document snapshot overlaid with pending operations,
  /// honouring [newestFirst].
  List<T> get files {
    final currentFiles = _currentFilesIncludingPendingChanges();
    return newestFirst
        ? currentFiles.reversed.toList(growable: false)
        : currentFiles;
  }

  /// Files already persisted in the document.
  List<T> get onlineFiles =>
      _currentFilesIncludingPendingChanges().where(_isOnline).toList();

  /// Whether [file] is still queued for upload, i.e. it exists on this device
  /// but not yet in Storage. Drives the "not yet uploaded" marker.
  bool isPendingUpload(T file) => _pendingUploadFor(file) != null;

  /// [file]'s upload that failed for good, or null while none has. Drives the
  /// "could not be uploaded" marker and the alert behind it.
  ///
  /// Only an upload is ever kept for the user — see
  /// [YustFileOperationHandler.discardOperationsForFile].
  YustFileOperation<YustFile>? failedUploadFor(T file) =>
      _pendingOperations.firstWhereOrNull(
        (operation) =>
            operation.fileKey == file.offlineKey && operation.hasFailed,
      );

  /// Drops every queued operation for [file], once the user has acknowledged
  /// the failure. The display falls back to the document snapshot, which is the
  /// server's state.
  Future<void> discardFailedUploadFor(T file) async {
    await handler.discardOperationsForFile(file.offlineKey);
    await _scheduleRefresh();
  }

  /// Whether [file] is persisted in the document.
  ///
  /// A queued upload disqualifies it: the pickers set `path` at pick time, so a
  /// storage location alone cannot tell a picked file from an uploaded one.
  bool _isOnline(T file) =>
      _pendingUploadFor(file) == null &&
      // ignore: deprecated_member_use
      (file.path != null || file.url != null);

  /// The document snapshot with the pending operations applied, keyed by
  /// [YustFileOfflineKey.offlineKey]. A pending add or replace contributes its
  /// local bytes; a pending delete drops its entry. A rename or metadata update
  /// is already on the online instance, so neither needs an entry.
  List<T> _currentFilesIncludingPendingChanges() {
    final fileByOfflineKey = <String, T>{
      for (final file in _online) file.offlineKey: file,
    };
    for (final operation in _pendingOperations) {
      switch (operation.type) {
        case YustFileOperationType.upload:
          fileByOfflineKey[operation.fileKey] = operation.file as T;
        case YustFileOperationType.delete:
          fileByOfflineKey.remove(operation.fileKey);
        case YustFileOperationType.rename:
        case YustFileOperationType.updateMetadata:
        case YustFileOperationType.download:
          break;
      }
    }
    return List<T>.unmodifiable(fileByOfflineKey.values);
  }

  /// Like [setOnlineFiles], but reconciles — and notifies — only when
  /// [incomingFiles] differs from the previous call. For a host that seeds on
  /// every rebuild (a widget); [setOnlineFiles] always reconciles.
  Future<void> setOnlineFilesIfChanged(List<T> incomingFiles) {
    final signature = incomingFiles
        .map(
          (file) =>
              '${file.offlineKey}|${file.name}|${file.hash}|${file.getOriginalUrl()}',
        )
        .join(',,');
    if (signature == _lastOnlineFilesSignature) return Future<void>.value();
    _lastOnlineFilesSignature = signature;
    return setOnlineFiles(incomingFiles);
  }

  /// Reconciles the list with the [incomingFiles] online files from the document.
  /// Call on init and whenever the host value changes.
  ///
  /// A file uploaded here since the last reconciliation is carried over when
  /// [incomingFiles] does not have it yet — see [_recentlyUploaded].
  Future<void> setOnlineFiles(List<T> incomingFiles) async {
    final incomingKeys = incomingFiles.map((file) => file.offlineKey).toSet();
    final carried = _recentlyUploaded.values
        .where((file) => !incomingKeys.contains(file.offlineKey))
        .toList();
    _recentlyUploaded.clear();
    _online
      ..clear()
      ..addAll(incomingFiles)
      ..addAll(carried);
    for (final file in _online) {
      firebaseLocation.apply(file);
      final path = await _storage?.pathForFile(file.byteKey);
      if (path != null) file.devicePath = path;
    }
    await _refreshPending();
  }

  /// Adds [file]: writes its bytes to the device, then enqueues the upload.
  /// Returns once the pending overlay reflects the new operation, which is what
  /// the caller reads [onlineFiles] against.
  Future<void> add(T file) async {
    firebaseLocation.apply(file);
    await file.ensureHash();
    await _writeBytes(file);
    await handler.enqueue(
      YustFileOperation<YustFile>(
        type: YustFileOperationType.upload,
        file: file,
      ),
    );
    await _scheduleRefresh();
  }

  /// Replaces [file]'s bytes (e.g. a re-drawn signature/image) and re-uploads.
  /// Clearing the hash makes [add] recompute it for the new content.
  Future<void> replaceBytes(T file, Uint8List bytes) {
    file
      ..bytes = bytes
      ..hash = '';
    return add(file);
  }

  /// Deletes [file]: a file still queued for upload is dropped from the queue
  /// rather than uploaded and then deleted; an already-persisted file is removed
  /// via a delete operation.
  ///
  /// Neither path frees the on-device bytes — they are keyed by content hash and
  /// so shared with every other entry holding the same bytes, which a delete
  /// here must leave available offline. Whoever owns the offline selection
  /// frees them instead, by cleaning the byte store of everything no selected
  /// record holds.
  Future<void> delete(T file) async {
    firebaseLocation.apply(file);
    // Deleted here, so it must not be carried across the next reconciliation.
    _recentlyUploaded.remove(file.offlineKey);
    final pendingUpload = await _queuedUploadFor(file);
    if (pendingUpload != null) {
      await handler.cancel(pendingUpload);
      await _scheduleRefresh();
      return;
    }
    // ignore: deprecated_member_use
    if (file.path != null || file.url != null) {
      await handler.enqueue(
        YustFileOperation<YustFile>(
          type: YustFileOperationType.delete,
          file: file,
        ),
      );
    }
    await _scheduleRefresh();
  }

  /// Writes [file]'s bytes (or source file) to the byte store and records the
  /// resulting [YustFile.devicePath]. Stays null on web, where there is no store.
  Future<void> _writeBytes(T file) async {
    final byteKey = file.byteKey;
    if (byteKey.isEmpty || !file.hasName) return;
    file.devicePath = await _storage?.writeBytes(
      byteKey: byteKey,
      name: file.name!,
      bytes: file.bytes,
      file: file.file,
    );
  }

  /// The upload of [file] still in the queue, read live rather than from the
  /// cached overlay so a host that only issues commands (no online list) can
  /// still cancel a not-yet-applied upload.
  Future<YustFileOperation<YustFile>?> _queuedUploadFor(T file) async {
    for (final operation in await handler.pending()) {
      if (operation.type == YustFileOperationType.upload &&
          operation.fileKey == file.offlineKey) {
        return operation;
      }
    }
    return null;
  }

  /// Renames [file] to [newName]. The operation carries an old-name snapshot so
  /// the executor can still fetch the original bytes; the display picks up the
  /// new name from the queued rename on the next refresh.
  Future<void> rename(T file, String newName) async {
    final snapshot = file.copyWithUrl(null);
    await handler.enqueue(
      YustFileOperation<YustFile>(
        type: YustFileOperationType.rename,
        file: snapshot,
        newName: newName,
      ),
    );
    await _scheduleRefresh();
  }

  /// Persists a metadata-only change to [file] (e.g. its favorite flag), which
  /// the caller has already applied to the instance. A file queued for upload
  /// needs no operation — that upload carries the same instance.
  Future<void> updateMetadata(T file) async {
    firebaseLocation.apply(file);
    if (_pendingUploadFor(file) == null) {
      await handler.enqueue(
        YustFileOperation<YustFile>(
          type: YustFileOperationType.updateMetadata,
          file: file,
        ),
      );
    }
    await _scheduleRefresh();
  }

  /// Completes once every refresh requested so far has been applied.
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

  /// Queues a refresh behind the one before it, so two overlapping
  /// notifications cannot leave [_pendingOperations] on the older read.
  Future<void> _scheduleRefresh() {
    _refresh = _refresh
        .then((_) => _refreshPending())
        // Keep the chain alive past a failure so one error can't wedge it.
        .catchError((Object _) {});
    return _refresh;
  }

  /// Adopts a file whose upload has just been applied into the persisted set,
  /// covering the gap between it leaving the queue and the document snapshot
  /// carrying it. The operation's file already has the `path` and `url`.
  void _onOperationApplied(YustFileOperation<YustFile> operation) {
    if (_disposed) return;
    if (operation.type != YustFileOperationType.upload ||
        !firebaseLocation.owns(operation.file)) {
      return;
    }
    final file = operation.file as T;
    final key = file.offlineKey;
    final index = _online.indexWhere((online) => online.offlineKey == key);
    if (index == -1) {
      _online.add(file);
    } else {
      _online[index] = file;
    }
    _recentlyUploaded[key] = file;
  }

  /// Re-reads this location's operations from the queue. Checked for disposal on
  /// both sides of the await, since the host can be torn down mid-read.
  Future<void> _refreshPending() async {
    if (_disposed) return;
    final allOperations = await handler.pending();
    if (_disposed) return;
    _pendingOperations = allOperations
        .where((operation) => firebaseLocation.owns(operation.file))
        .toList();
    // A rename shows by renaming the live online entry; the operation keeps the
    // old-name snapshot for the executor.
    for (final operation in _pendingOperations) {
      if (operation.type == YustFileOperationType.rename) {
        _online
            .firstWhereOrNull((file) => file.offlineKey == operation.fileKey)
            ?.name = operation
            .newName;
      }
    }
    _emitOnlineFiles();
    notifyListeners();
  }

  YustFileOperation<YustFile>? _pendingUploadFor(T file) =>
      _pendingOperations.firstWhereOrNull(
        (operation) =>
            operation.type == YustFileOperationType.upload &&
            operation.fileKey == file.offlineKey,
      );

  /// Reports the persisted set to the host, for an unlinked location only.
  ///
  /// A linked location ([YustFirebaseFileLocation.isLinked]) is persisted by the
  /// queue's own writer and reaches the host through the document stream.
  /// Without a document there is no writer, so the host — a standalone picker,
  /// an email attachment list — has to be told.
  void _emitOnlineFiles() {
    if (firebaseLocation.isLinked) return;
    onOnlineFilesChanged?.call(onlineFiles);
  }
}
