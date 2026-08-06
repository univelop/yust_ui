import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

import '../yust_file_helpers.dart';
import 'file_operation.dart';
import 'sync_queue.dart';

/// Carries out one kind of [FileOperation].
///
/// The upload and download managers implement this. They are handed only the op
/// to carry out and know nothing about the queue, connectivity or retries — the
/// same code runs whether the app is online or offline.
abstract interface class FileOperationExecutor {
  /// The op kinds this executor owns.
  Set<FileOperationType> get handledTypes;

  /// Carries out [op]: its byte work and record write.
  Future<void> execute(FileOperation<YustFile> op);
}

/// Drives every file change through the one [SyncQueue].
///
/// This is the single offline-aware component. [processPendingOperations]
/// applies the queue oldest-first, routes each op to the [FileOperationExecutor]
/// that owns its type, and removes it only on success. A failing op is skipped
/// and left queued so the ops behind it still run — one unsendable file must not
/// strand a pinned record's downloads. A pass that applied nothing stops instead
/// of re-reading the same failing snapshot, and any pass with a failure
/// schedules a retry with capped exponential backoff (1s, 2s, 4s … capped at
/// 30s, forever).
///
/// Ops are always attempted, never gated on a connectivity check: an interface
/// being up does not mean the network works (captive portals, dead wifi), so a
/// gate cannot prevent a doomed attempt while adding a signal that lies in both
/// directions. Connectivity is only a hint to retry sooner — a regained event
/// resets the backoff and requests another pass, coalescing if one is already
/// running. Failures are not classified — last-write-wins, retry everything (no
/// dead-letter).
///
/// [enqueue] only waits for the op to be durably queued, never for the transfer:
/// offline, a real upload retries internally for minutes before failing, and the
/// picker awaiting it is what left a spinner on screen.
///
/// It is a [ChangeNotifier]: it notifies whenever the queue changes (an op is
/// enqueued, cancelled or applied), so a [FileListController] can rebuild its
/// pending-op overlay without polling.
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

  /// The queue every op — inbound and outbound — flows through.
  final SyncQueue queue;
  final Future<void> Function(Duration) _delay;
  final Map<FileOperationType, FileOperationExecutor> _executors = {};

  /// Emits each op right after it has been applied and dropped from the queue.
  ///
  /// A listener receives the executor's own instance, so an applied upload
  /// already carries the `path` and `url` it was given — the file can be
  /// adopted as persisted without waiting for the record to come back around.
  /// Synchronous, so a listener has updated its state before the
  /// [notifyListeners] that follows.
  Stream<FileOperation<YustFile>> get applied => _applied.stream;

  final StreamController<FileOperation<YustFile>> _applied =
      StreamController<FileOperation<YustFile>>.broadcast(sync: true);

  static const _base = Duration(seconds: 1);
  static const _cap = Duration(seconds: 30);

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

  /// Appends [op] and starts a drain, returning as soon as the op is durably
  /// queued. The transfer itself is not awaited — see the class doc.
  Future<void> enqueue(FileOperation<YustFile> op) async {
    await queue.enqueue(op);
    notifyListeners();
    unawaited(processPendingOperations());
  }

  /// Appends every op in [ops], then starts one drain — so a batch of downloads
  /// isn't processed per file.
  Future<void> enqueueAll(Iterable<FileOperation<YustFile>> ops) async {
    var enqueued = false;
    for (final op in ops) {
      await queue.enqueue(op);
      enqueued = true;
    }
    if (!enqueued) return;
    notifyListeners();
    unawaited(processPendingOperations());
  }

  /// Drops a still-pending [op] without applying it — e.g. a file deleted before
  /// its upload ran.
  Future<void> cancel(FileOperation<YustFile> op) async {
    await queue.remove(op);
    notifyListeners();
  }

  /// This manager's pending ops, oldest-first.
  Future<List<FileOperation<YustFile>>> pending() => queue.pending();

  /// Drains the queue, and completes when the drain in flight does.
  ///
  /// Only one drain runs at a time so two passes never race on the same op. A
  /// caller arriving while one is running joins it rather than being dropped:
  /// it gets the running pass to await, and asks for one more pass afterwards
  /// so work that arrived mid-pass — a reconnect, a freshly enqueued op — is
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
  /// The queue is re-read after each sweep so an op enqueued mid-pass is picked
  /// up without waiting for the next trigger. A sweep that applied nothing ends
  /// the pass — re-reading would hand back the same failing ops and spin.
  Future<void> _drain() async {
    var failed = false;
    for (
      var pending = await queue.pending();
      pending.isNotEmpty;
      pending = await queue.pending()
    ) {
      var applied = 0;
      for (final op in pending) {
        if (_disposed) return;
        try {
          await _executorFor(op).execute(op);
          await queue.remove(op);
          _applied.add(op);
          notifyListeners();
          applied++;
        } catch (error) {
          debugPrint(
            '[offline-sync] ${op.type.name} of "${op.file.name}" '
            'failed, staying queued: $error',
          );
          failed = true;
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

  FileOperationExecutor _executorFor(FileOperation<YustFile> op) {
    final executor = _executors[op.type];
    if (executor == null) {
      throw StateError('No executor registered for ${op.type}');
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
