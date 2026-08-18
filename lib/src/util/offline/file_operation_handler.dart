import 'dart:async';
import 'dart:io';

// FirebaseException, re-exported by cloud_firestore, covers Storage errors too.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart';
import 'package:yust/yust.dart';

import '../yust_file_helpers.dart';
import 'file_operation.dart';
import 'sync_queue.dart';

/// Carries out one kind of [FileOperation].
///
/// The upload and download managers implement this. They know nothing about the
/// queue, connectivity or retries.
abstract interface class FileOperationExecutor {
  /// The operation kinds this executor owns.
  Set<FileOperationType> get handledTypes;

  /// Carries out [operation]: its byte work and record write.
  Future<void> execute(FileOperation<YustFile> operation);
}

/// Drives every file change through the one [SyncQueue].
///
/// This is the single offline-aware component. [processPendingOperations]
/// applies the queue oldest-first and routes each operation to the
/// [FileOperationExecutor] that owns its type, removing it only on success.
///
/// The flat queue is read as one FIFO per file: only a file's oldest queued
/// operation is eligible per sweep, so its own operations stay in order while
/// other files pass freely. A sweep that applied nothing ends the pass; any
/// failure schedules a retry with capped exponential backoff (1s, 2s, 4s … 30s).
///
/// Operations are always attempted, never gated on a connectivity check.
/// Connectivity is a hint to retry sooner: a regained event resets the backoff
/// and requests another pass, coalescing if one is already running.
///
/// Failures are classified. Connection failures retry forever, untracked. A
/// failure retrying cannot fix ([isPermanentOperationError]) spends one of the
/// operation's [FileOperation.failedAttempts]; at [maxFailedAttempts] it is
/// timed out — kept in the queue, reported via [timedOutOperations], cleared by
/// [retryTimedOutOperations]. Nothing is dropped, and an unrecognised error
/// counts as transient.
///
/// [enqueue] waits only for the operation to be durably queued, never for the
/// transfer.
///
/// Notifies whenever the queue changes, so a [FileListController] can rebuild
/// its pending-operation overlay without polling.
class FileOperationHandler extends ChangeNotifier {
  FileOperationHandler({
    required List<FileOperationExecutor> executors,
    SyncQueue? queue,
    Stream<bool>? onlineStream,
    Future<void> Function(Duration)? delay,
  }) : queue = queue ?? SyncQueue(),
       _delay = delay ?? ((duration) => Future<void>.delayed(duration)) {
    for (final executor in executors) {
      for (final type in executor.handledTypes) {
        _executors[type] = executor;
      }
    }
    _onlineSub = (onlineStream ?? _defaultOnlineStream).listen(_onConnectivity);
  }

  /// The queue every operation — inbound and outbound — flows through.
  final SyncQueue queue;
  final Future<void> Function(Duration) _delay;
  final Map<FileOperationType, FileOperationExecutor> _executors = {};

  /// Emits each operation right after it is applied and dropped from the queue.
  ///
  /// A listener receives the executor's own instance, so an applied upload
  /// already carries its `path` and `url`. Synchronous, so a listener has
  /// updated its state before the [notifyListeners] that follows.
  Stream<FileOperation<YustFile>> get applied => _applied.stream;

  final StreamController<FileOperation<YustFile>> _applied =
      StreamController<FileOperation<YustFile>>.broadcast(sync: true);

  static const _base = Duration(seconds: 1);
  static const _cap = Duration(seconds: 30);

  /// Permanent failures an operation may collect before it is timed out.
  static const maxFailedAttempts = 5;

  late final StreamSubscription<bool> _onlineSub;
  int _attempt = 0;
  bool _isProcessing = false;
  bool _retryScheduled = false;
  bool _disposed = false;

  /// The pass in flight, so overlapping callers can await the one drain.
  Future<void>? _pass;

  /// Set when a pass is requested while one is already running, so the drain
  /// loops once more instead of the request being dropped.
  bool _processAgain = false;

  /// Appends [operation] and starts a drain, returning as soon as it is durably
  /// queued. The transfer itself is not awaited.
  ///
  /// Throws [ArgumentError] for a file the executor could not address.
  Future<void> enqueue(FileOperation<YustFile> operation) async {
    _assertAddressable(operation);
    await queue.enqueue(operation);
    await _notifyQueueChanged();
    unawaited(processPendingOperations());
  }

  /// Appends every operation in [operations], then starts one drain. Rejects
  /// the whole batch if any operation is unaddressable.
  Future<void> enqueueAll(Iterable<FileOperation<YustFile>> operations) async {
    final batch = operations.toList();
    batch.forEach(_assertAddressable);
    for (final operation in batch) {
      await queue.enqueue(operation);
    }
    if (batch.isEmpty) return;
    await _notifyQueueChanged();
    unawaited(processPendingOperations());
  }

  /// Rejects an operation whose file the executor could not act on.
  ///
  /// [ArgumentError] because [isPermanentOperationError] counts it as permanent;
  /// a `TypeError` from a null `!` counts as transient and retries forever.
  void _assertAddressable(FileOperation<YustFile> operation) {
    final file = operation.file;
    if (!file.hasName) {
      throw ArgumentError('Cannot queue a file without a name.');
    }
    // Writes need the Storage folder; a download can read from `path`.
    final addressable = operation.type == FileOperationType.download
        ? file.hasStorageLocation
        : file.storageFolderPath?.isNotEmpty == true;
    if (!addressable) {
      throw ArgumentError(
        'Cannot queue ${operation.type.name} of "${file.name}" without a '
        'storage location.',
      );
    }
  }

  /// Drops a still-pending [operation] without applying it, e.g. a file deleted
  /// before its upload ran.
  Future<void> cancel(FileOperation<YustFile> operation) async {
    await queue.remove(operation);
    await _notifyQueueChanged();
  }

  /// This manager's pending operations, oldest-first.
  Future<List<FileOperation<YustFile>>> pending() => queue.pending();

  /// Whether [file]'s bytes are still on their way to Storage. Synchronous, so
  /// a widget can ask while it builds; listen to this handler to rebuild when it
  /// changes.
  ///
  /// A timed out upload is not in flight — [timedOutOperations] reports those.
  bool isUploading(YustFile file) =>
      _uploadingFileKeys.contains(file.offlineKey);

  /// Backs [isUploading]. Refreshed with every change to the queue, since the
  /// queue itself can only be read asynchronously.
  Set<String> _uploadingFileKeys = {};

  /// Re-reads the queue, then notifies. The one way this handler announces a
  /// change, so [isUploading] can never disagree with the listeners it wakes.
  Future<void> _notifyQueueChanged() async {
    _uploadingFileKeys = (await queue.pending())
        .where(
          (operation) =>
              operation.type == FileOperationType.upload &&
              !_hasTimedOut(operation),
        )
        .map((operation) => operation.fileKey)
        .toSet();
    if (!_disposed) notifyListeners();
  }

  /// Ops that hit [maxFailedAttempts] and sit in the queue untouched — a change the
  /// user made that has not reached the server.
  Future<List<FileOperation<YustFile>>> timedOutOperations() async =>
      (await queue.pending()).where(_hasTimedOut).toList();

  /// Clears the failure count on every timed out operation and drains again.
  Future<void> retryTimedOutOperations() async {
    for (final operation in await timedOutOperations()) {
      await queue.replace(operation.withResetFailedAttempts());
    }
    _attempt = 0;
    await _notifyQueueChanged();
    await processPendingOperations();
  }

  /// Whether [operation] has exhausted its failedAttempts; see [timedOutOperations].
  bool _hasTimedOut(FileOperation<YustFile> operation) =>
      operation.failedAttempts >= maxFailedAttempts;

  /// Drains the queue, and completes when the drain in flight does.
  ///
  /// Only one drain runs at a time so two passes never race on the same operation. A
  /// caller arriving while one is running joins it rather than being dropped:
  /// it gets the running pass to await, and asks for one more pass afterwards
  /// so work that arrived mid-pass — a reconnect, a freshly enqueued operation — is
  /// never missed.
  Future<void> processPendingOperations() {
    if (_disposed) return Future<void>.value();
    if (_isProcessing) {
      _processAgain = true;
      return _pass ?? Future<void>.value();
    }
    _isProcessing = true;
    final pass = _drainUntilSettled().whenComplete(() {
      _isProcessing = false;
      _pass = null;
    });
    _pass = pass;
    return pass;
  }

  /// Runs passes until no further one was requested while the last was running.
  Future<void> _drainUntilSettled() async {
    do {
      _processAgain = false;
      await _drain();
    } while (_processAgain && !_disposed);
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
      var pending = await queue.pending();
      pending.isNotEmpty;
      pending = await queue.pending()
    ) {
      var applied = 0;
      for (final operation in _nextOperationPerFile(pending)) {
        if (_disposed) return;
        // One attempt per operation per pass; the backoff owns the next one.
        if (failedOperationIdsThisPass.contains(operation.id)) continue;
        try {
          await _executorFor(operation).execute(operation);
          await queue.remove(operation);
          _applied.add(operation);
          await _notifyQueueChanged();
          applied++;
        } catch (error) {
          failed = true;
          failedOperationIdsThisPass.add(operation.id);
          await _recordFailedAttempt(operation, error);
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
    unawaited(_onlineSub.cancel());
    unawaited(_applied.close());
    super.dispose();
  }

  /// The oldest queued operation of each file, in the order the files first appear —
  /// the flat queue read as one FIFO per file. A timed out file yields nothing,
  /// holding its whole chain until the user retries.
  Iterable<FileOperation<YustFile>> _nextOperationPerFile(
    List<FileOperation<YustFile>> pending,
  ) {
    final heads = <String, FileOperation<YustFile>>{};
    for (final operation in pending) {
      heads.putIfAbsent(operation.fileKey, () => operation);
    }
    return heads.values.where((operation) => !_hasTimedOut(operation));
  }

  /// Logs why [operation] failed and, for a permanent failure, spends one of its
  /// failedAttempts. The operation stays queued either way.
  Future<void> _recordFailedAttempt(
    FileOperation<YustFile> operation,
    Object error,
  ) async {
    if (!isPermanentOperationError(error)) {
      debugPrint(
        '[offline-sync] ${operation.type.name} of "${operation.file.name}" could not '
        'reach the server, staying queued: $error',
      );
      return;
    }
    final failed = operation.withFailedAttempt();
    await queue.replace(failed);
    debugPrint(
      '[offline-sync] ${operation.type.name} of "${operation.file.name}" failed '
      '(${failed.failedAttempts}/$maxFailedAttempts, not retryable): $error',
    );
    if (_hasTimedOut(failed)) {
      debugPrint(
        '[offline-sync] "${operation.file.name}" timed out — it will not be retried '
        'until the user asks for it',
      );
      await _notifyQueueChanged();
    }
  }

  FileOperationExecutor _executorFor(FileOperation<YustFile> operation) {
    final executor = _executors[operation.type];
    if (executor == null) {
      throw StateError('No executor registered for ${operation.type}');
    }
    return executor;
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
    final raw = _base.inMilliseconds * (1 << _attempt);
    return Duration(
      milliseconds: raw < _cap.inMilliseconds ? raw : _cap.inMilliseconds,
    );
  }

  Stream<bool> get _defaultOnlineStream => YustFileHelpers.connectivityStream
      .map((results) => results.any((r) => r != ConnectivityResult.none));
}

/// The bytes an operation needs are not in Storage at all.
///
/// Raised where the file service reports a failed transfer as empty bytes
/// rather than throwing, so the queue can tell "the object is gone" — which no
/// retry fixes — apart from "the server was unreachable", which every retry
/// might.
class MissingStorageObjectException implements Exception {
  MissingStorageObjectException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Firebase codes no retry gets past: not allowed, or the target is gone.
/// Everything else (`unavailable`, `retry-limit-exceeded`, …) is a connection
/// problem wearing a code.
const _permanentFirebaseCodes = {
  'permission-denied',
  'unauthenticated',
  'unauthorized',
  'not-found',
  'object-not-found',
  'invalid-argument',
  'storage/unauthorized',
  'storage/object-not-found',
  'storage/invalid-argument',
};

/// Whether [error] means the operation can never succeed, so it counts against
/// the operation's attempt budget instead of retrying forever. Unrecognised
/// errors count as transient.
bool isPermanentOperationError(Object error) => switch (error) {
  // Bad input this code produced; retrying replays the same arguments.
  ArgumentError() => true,
  StateError() => true,
  // The object is not in Storage; no number of retries puts it there.
  MissingStorageObjectException() => true,
  // Listed explicitly so no subtype falls through to a permanent verdict.
  SocketException() ||
  TimeoutException() ||
  HttpException() ||
  ClientException() => false,
  FirebaseException(:final code) => _permanentFirebaseCodes.contains(code),
  _ => false,
};
