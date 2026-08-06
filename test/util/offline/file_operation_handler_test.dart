import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/file_operation.dart';
import 'package:yust_ui/src/util/offline/file_operation_handler.dart';
import 'package:yust_ui/src/util/offline/sync_queue.dart';

/// Records every op it is handed; an optional [onExecute] runs first so a test
/// can enqueue more work mid-pass, park the pass, or force a failure.
class _RecordingExecutor implements FileOperationExecutor {
  _RecordingExecutor({this.onExecute});

  final Future<void> Function(FileOperation<YustFile> op)? onExecute;
  final List<String> executed = [];

  @override
  Set<FileOperationType> get handledTypes => {
    FileOperationType.upload,
    FileOperationType.download,
  };

  @override
  Future<void> execute(FileOperation<YustFile> op) async {
    await onExecute?.call(op);
    executed.add(op.fileKey);
  }
}

FileOperation<YustFile> _op(String hash) => FileOperation<YustFile>(
  type: FileOperationType.upload,
  file: YustFile(name: '$hash.pdf', hash: hash, setCreatedAtToNow: false),
);

FileOperation<YustFile> _downloadOp(String hash) => FileOperation<YustFile>(
  type: FileOperationType.download,
  file: YustFile(name: '$hash.pdf', hash: hash, setCreatedAtToNow: false),
);

/// Lets an unawaited drain reach its next suspension point. `Duration.zero` is
/// timer-based, so the queue's file IO gets to complete between turns.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Directory root;
  late SyncQueue queue;

  setUp(() {
    root = Directory.systemTemp.createTempSync('file_op_handler_test');
    queue = SyncQueue(directoryProvider: () async => root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// A handler whose backoff never fires, so a test observes exactly the passes
  /// it triggers itself. [delays] collects what the backoff asked for.
  FileOperationHandler handlerWith(
    FileOperationExecutor executor, {
    Stream<bool>? onlineStream,
    List<Duration>? delays,
  }) {
    final handler = FileOperationHandler(
      executors: [executor],
      queue: queue,
      onlineStream: onlineStream ?? const Stream<bool>.empty(),
      delay: (duration) {
        delays?.add(duration);
        return Completer<void>().future;
      },
    );
    addTearDown(handler.dispose);
    return handler;
  }

  group('draining', () {
    test('applies every pending op and empties the queue', () async {
      final executor = _RecordingExecutor();
      final handler = handlerWith(executor);

      await handler.enqueueAll([_op('h1'), _op('h2')]);
      await handler.processPendingOperations();

      expect(executor.executed, ['h1', 'h2']);
      expect(await queue.pending(), isEmpty);
    });

    test('an op enqueued mid-pass is applied in the same run', () async {
      late FileOperationHandler handler;
      var injected = false;
      final executor = _RecordingExecutor(
        onExecute: (op) async {
          if (op.fileKey == 'h1' && !injected) {
            injected = true;
            await handler.enqueue(_op('h2'));
          }
        },
      );
      handler = handlerWith(executor);

      await handler.enqueue(_op('h1'));
      await handler.processPendingOperations();

      expect(executor.executed, ['h1', 'h2']);
      expect(await queue.pending(), isEmpty);
    });
  });

  group('enqueue does not wait on the network', () {
    test('enqueue returns while the executor is still in flight', () async {
      final gate = Completer<void>();
      final executor = _RecordingExecutor(onExecute: (_) => gate.future);
      final handler = handlerWith(executor);

      // Offline this is the real upload retrying for minutes. The picker awaits
      // enqueue, so it must return as soon as the op is durably queued.
      await handler.enqueue(_op('h1'));

      expect(executor.executed, isEmpty);
      expect((await queue.pending()).map((op) => op.fileKey), ['h1']);

      gate.complete();
      await handler.processPendingOperations();
      expect(executor.executed, ['h1']);
    });

    test('a failing executor does not surface out of enqueue', () async {
      final executor = _RecordingExecutor(
        onExecute: (_) async => throw StateError('offline'),
      );
      final handler = handlerWith(executor);

      await handler.enqueue(_op('h1'));
      await handler.processPendingOperations();

      expect(await queue.pending(), hasLength(1));
    });
  });

  group('a failing op does not strand the ops behind it', () {
    test('the ops behind a failing one are still applied', () async {
      final executor = _RecordingExecutor(
        onExecute: (op) async {
          if (op.fileKey == 'h1') throw StateError('boom');
        },
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([_op('h1'), _op('h2')]);
      await handler.processPendingOperations();

      expect(executor.executed, ['h2']);
      expect((await queue.pending()).map((op) => op.fileKey), ['h1']);
    });

    test('a failing upload does not block a queued download', () async {
      // The reported bug: a stuck upload sat at the head of the queue and the
      // pinned record's downloads behind it never ran.
      final executor = _RecordingExecutor(
        onExecute: (op) async {
          if (op.type == FileOperationType.upload) throw StateError('offline');
        },
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([_op('h1'), _downloadOp('h2')]);
      await handler.processPendingOperations();

      expect(executor.executed, ['h2']);
    });

    test('a pass in which everything fails stops rather than spins', () async {
      final executor = _RecordingExecutor(
        onExecute: (_) async => throw StateError('offline'),
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([_op('h1'), _op('h2')]);
      await handler.processPendingOperations().timeout(
        const Duration(seconds: 5),
      );

      expect(executor.executed, isEmpty);
      expect(await queue.pending(), hasLength(2));
    });
  });

  group('reconnect handling', () {
    test('a reconnect arriving mid-pass is honoured once it ends', () async {
      final online = StreamController<bool>.broadcast();
      addTearDown(online.close);
      final gate = Completer<void>();
      var attempts = 0;
      final executor = _RecordingExecutor(
        onExecute: (op) async {
          if (op.fileKey == 'h1') return gate.future;
          attempts++;
          // Fails for both tries of the first pass, succeeds afterwards.
          if (attempts <= 2) throw StateError('offline');
        },
      );
      final handler = handlerWith(executor, onlineStream: online.stream);

      await handler.enqueueAll([_op('h1'), _op('h2')]);
      await _settle(); // the pass is parked inside h1

      online.add(true);
      await _settle(); // the reconnect lands while the pass is still running
      gate.complete();
      await handler.processPendingOperations();

      // Backoff never fires here, so only a honoured reconnect can drain h2.
      expect(executor.executed, ['h1', 'h2']);
      expect(await queue.pending(), isEmpty);
    });

    test('several reconnects during one pass collapse into one', () async {
      final online = StreamController<bool>.broadcast();
      addTearDown(online.close);
      final gate = Completer<void>();
      var attempts = 0;
      final executor = _RecordingExecutor(
        onExecute: (op) async {
          if (op.fileKey == 'h1') return gate.future;
          attempts++;
          throw StateError('offline');
        },
      );
      final handler = handlerWith(executor, onlineStream: online.stream);

      await handler.enqueueAll([_op('h1'), _op('h2')]);
      await _settle();

      online
        ..add(true)
        ..add(true)
        ..add(true);
      await _settle();
      gate.complete();
      await handler.processPendingOperations();

      // Two tries in the first pass, one in the single coalesced follow-up.
      expect(attempts, 3);
    });

    test('a reconnect with an empty queue is a no-op', () async {
      final online = StreamController<bool>.broadcast();
      addTearDown(online.close);
      final executor = _RecordingExecutor();
      handlerWith(executor, onlineStream: online.stream);

      online.add(true);
      await _settle();

      expect(executor.executed, isEmpty);
    });
  });

  group('backoff', () {
    test('a retry is scheduled only when an op failed', () async {
      final delays = <Duration>[];
      var shouldFail = false;
      final executor = _RecordingExecutor(
        onExecute: (_) async {
          if (shouldFail) throw StateError('offline');
        },
      );
      final handler = handlerWith(executor, delays: delays);

      await handler.enqueue(_op('h1'));
      await handler.processPendingOperations();
      expect(delays, isEmpty);

      shouldFail = true;
      await handler.enqueue(_op('h2'));
      await handler.processPendingOperations();
      expect(delays, isNotEmpty);
    });

    test('backoff resets once the queue fully drains', () async {
      final delays = <Duration>[];
      var shouldFail = true;
      final executor = _RecordingExecutor(
        onExecute: (_) async {
          if (shouldFail) throw StateError('offline');
        },
      );
      final handler = handlerWith(executor, delays: delays);

      await handler.enqueue(_op('h1'));
      await handler.processPendingOperations();
      final firstDelay = delays.single;

      // Drain cleanly, then fail again: the delay must start from the base
      // again rather than continuing to grow.
      shouldFail = false;
      await handler.processPendingOperations();
      shouldFail = true;
      await handler.enqueue(_op('h2'));
      await handler.processPendingOperations();

      expect(delays.last, firstDelay);
    });
  });
}
