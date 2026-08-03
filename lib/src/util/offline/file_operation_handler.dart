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
/// that owns its type, and removes it only on success. On the first failure it
/// stops and retries later with capped exponential backoff (1s, 2s, 4s … capped
/// at 30s, forever); a connectivity-regained event resets the backoff and
/// processes immediately, the backoff timer covering a missed callback. Online =
/// [enqueue] + process now; offline = enqueue, processes on reconnect. Failures
/// are not classified — last-write-wins, retry everything (no dead-letter).
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

  static const _base = Duration(seconds: 1);
  static const _cap = Duration(seconds: 30);

  late final StreamSubscription<bool> _onlineSub;
  int _attempt = 0;
  bool _isProcessing = false;
  bool _retryScheduled = false;
  bool _disposed = false;

  /// Appends [op] and processes the queue. Online this applies it now; offline
  /// the pass is a no-op and retries once connectivity returns.
  Future<void> enqueue(FileOperation<YustFile> op) async {
    await queue.enqueue(op);
    notifyListeners();
    await processPendingOperations();
  }

  /// Appends every op in [ops], then processes once — so a batch of downloads
  /// isn't processed per file.
  Future<void> enqueueAll(Iterable<FileOperation<YustFile>> ops) async {
    var enqueued = false;
    for (final op in ops) {
      await queue.enqueue(op);
      enqueued = true;
    }
    if (!enqueued) return;
    notifyListeners();
    await processPendingOperations();
  }

  /// Drops a still-pending [op] without applying it — e.g. a file deleted before
  /// its upload ran.
  Future<void> cancel(FileOperation<YustFile> op) async {
    await queue.remove(op);
    notifyListeners();
  }

  /// This manager's pending ops, oldest-first.
  Future<List<FileOperation<YustFile>>> pending() => queue.pending();

  /// Applies the pending ops oldest-first, removing each on success. On the
  /// first failure it stops and schedules a backed-off retry.
  ///
  /// The guard makes overlapping calls a no-op so two passes never race on the
  /// same op — a call arriving while one is running (e.g. from [enqueue]) just
  /// returns. To cover the op that call added after this pass took its snapshot,
  /// the loop re-reads the queue after each pass and keeps going until it is
  /// empty, so nothing waits for the next enqueue or reconnect.
  Future<void> processPendingOperations() async {
    if (_isProcessing || _disposed) return;
    _isProcessing = true;
    try {
      for (
        var pending = await queue.pending();
        pending.isNotEmpty;
        pending = await queue.pending()
      ) {
        for (final op in pending) {
          try {
            await _executorFor(op).execute(op);
            await queue.remove(op);
            notifyListeners();
          } catch (_) {
            _scheduleRetry();
            return;
          }
        }
      }
      _attempt = 0; // fully drained → reset backoff
    } finally {
      _isProcessing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_onlineSub.cancel());
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
