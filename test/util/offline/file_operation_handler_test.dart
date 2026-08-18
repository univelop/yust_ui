import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/file_operation.dart';
import 'package:yust_ui/src/util/offline/file_operation_handler.dart';
import 'package:yust_ui/src/util/offline/sync_queue.dart';

/// Records the name of every operation it is handed; an optional [onExecute]
/// runs first so a test can enqueue more work mid-pass, park the pass, or force
/// a failure.
class _RecordingExecutor implements FileOperationExecutor {
  _RecordingExecutor({this.onExecute});

  final Future<void> Function(FileOperation<YustFile> operation)? onExecute;
  final List<String> executed = [];

  @override
  Set<FileOperationType> get handledTypes => {
    FileOperationType.upload,
    FileOperationType.download,
  };

  @override
  Future<void> execute(FileOperation<YustFile> operation) async {
    await onExecute?.call(operation);
    executed.add(operation.file.name!);
  }
}

FileOperation<YustFile> _uploadOperation(String hash, {String? id}) =>
    FileOperation<YustFile>(
      id: id,
      type: FileOperationType.upload,
      file: YustFile(name: '$hash.pdf', hash: hash, setCreatedAtToNow: false),
    );

/// What being offline actually throws, as opposed to a permanent failure.
const _offline = SocketException('no route to host');

/// A failure no retry can fix, so it counts against the operation's failedAttempts.
final _permanent = FirebaseException(
  plugin: 'firebase_storage',
  code: 'permission-denied',
);

FileOperation<YustFile>? _queued(
  List<FileOperation<YustFile>> operations,
  String id,
) => operations.where((operation) => operation.id == id).firstOrNull;

FileOperation<YustFile> _downloadOperation(String hash) =>
    FileOperation<YustFile>(
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
    test('applies every pending operation and empties the queue', () async {
      final executor = _RecordingExecutor();
      final handler = handlerWith(executor);

      await handler.enqueueAll([
        _uploadOperation('h1'),
        _uploadOperation('h2'),
      ]);
      await handler.processPendingOperations();

      expect(executor.executed, ['h1.pdf', 'h2.pdf']);
      expect(await queue.pending(), isEmpty);
    });

    test('an operation enqueued mid-pass is applied in the same run', () async {
      late FileOperationHandler handler;
      var injected = false;
      final executor = _RecordingExecutor(
        onExecute: (operation) async {
          if (operation.file.name == 'h1.pdf' && !injected) {
            injected = true;
            await handler.enqueue(_uploadOperation('h2'));
          }
        },
      );
      handler = handlerWith(executor);

      await handler.enqueue(_uploadOperation('h1'));
      await handler.processPendingOperations();

      expect(executor.executed, ['h1.pdf', 'h2.pdf']);
      expect(await queue.pending(), isEmpty);
    });
  });

  group('enqueue does not wait on the network', () {
    test('enqueue returns while the executor is still in flight', () async {
      final gate = Completer<void>();
      final executor = _RecordingExecutor(onExecute: (_) => gate.future);
      final handler = handlerWith(executor);

      // Offline this is the real upload retrying for minutes. The picker awaits
      // enqueue, so it must return as soon as the operation is durably queued.
      await handler.enqueue(_uploadOperation('h1'));

      expect(executor.executed, isEmpty);
      expect((await queue.pending()).map((operation) => operation.file.name), [
        'h1.pdf',
      ]);

      gate.complete();
      await handler.processPendingOperations();
      expect(executor.executed, ['h1.pdf']);
    });

    test('a failing executor does not surface out of enqueue', () async {
      final executor = _RecordingExecutor(
        onExecute: (_) async => throw _offline,
      );
      final handler = handlerWith(executor);

      await handler.enqueue(_uploadOperation('h1'));
      await handler.processPendingOperations();

      expect(await queue.pending(), hasLength(1));
    });
  });

  group('a failing operation does not strand the operations behind it', () {
    test('the operations behind a failing one are still applied', () async {
      final executor = _RecordingExecutor(
        onExecute: (operation) async {
          if (operation.file.name == 'h1.pdf') throw _offline;
        },
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([
        _uploadOperation('h1'),
        _uploadOperation('h2'),
      ]);
      await handler.processPendingOperations();

      expect(executor.executed, ['h2.pdf']);
      expect((await queue.pending()).map((operation) => operation.file.name), [
        'h1.pdf',
      ]);
    });

    test('a failing upload does not block a queued download', () async {
      // The reported bug: a stuck upload sat at the head of the queue and the
      // pinned record's downloads behind it never ran.
      final executor = _RecordingExecutor(
        onExecute: (operation) async {
          if (operation.type == FileOperationType.upload) throw _offline;
        },
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([
        _uploadOperation('h1'),
        _downloadOperation('h2'),
      ]);
      await handler.processPendingOperations();

      expect(executor.executed, ['h2.pdf']);
    });

    test('a pass in which everything fails stops rather than spins', () async {
      final executor = _RecordingExecutor(
        onExecute: (_) async => throw _offline,
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([
        _uploadOperation('h1'),
        _uploadOperation('h2'),
      ]);
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
      var failedAttempts = 0;
      final executor = _RecordingExecutor(
        onExecute: (operation) async {
          if (operation.file.name == 'h1.pdf') return gate.future;
          failedAttempts++;
          // Fails on its one try of the first pass, succeeds afterwards.
          if (failedAttempts <= 1) throw _offline;
        },
      );
      final handler = handlerWith(executor, onlineStream: online.stream);

      await handler.enqueueAll([
        _uploadOperation('h1'),
        _uploadOperation('h2'),
      ]);
      await _settle(); // the pass is timed out inside h1

      online.add(true);
      await _settle(); // the reconnect lands while the pass is still running
      gate.complete();
      await handler.processPendingOperations();

      // Backoff never fires here, so only a honoured reconnect can drain h2.
      expect(executor.executed, ['h1.pdf', 'h2.pdf']);
      expect(await queue.pending(), isEmpty);
    });

    test('several reconnects during one pass collapse into one', () async {
      final online = StreamController<bool>.broadcast();
      addTearDown(online.close);
      final gate = Completer<void>();
      var failedAttempts = 0;
      final executor = _RecordingExecutor(
        onExecute: (operation) async {
          if (operation.file.name == 'h1.pdf') return gate.future;
          failedAttempts++;
          throw _offline;
        },
      );
      final handler = handlerWith(executor, onlineStream: online.stream);

      await handler.enqueueAll([
        _uploadOperation('h1'),
        _uploadOperation('h2'),
      ]);
      await _settle();

      online
        ..add(true)
        ..add(true)
        ..add(true);
      await _settle();
      gate.complete();
      await handler.processPendingOperations();

      // One try in the first pass, one in the single coalesced follow-up.
      expect(failedAttempts, 2);
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
    test('a retry is scheduled only when an operation failed', () async {
      final delays = <Duration>[];
      var shouldFail = false;
      final executor = _RecordingExecutor(
        onExecute: (_) async {
          if (shouldFail) throw StateError('offline');
        },
      );
      final handler = handlerWith(executor, delays: delays);

      await handler.enqueue(_uploadOperation('h1'));
      await handler.processPendingOperations();
      expect(delays, isEmpty);

      shouldFail = true;
      await handler.enqueue(_uploadOperation('h2'));
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

      await handler.enqueue(_uploadOperation('h1'));
      await handler.processPendingOperations();
      final firstDelay = delays.single;

      // Drain cleanly, then fail again: the delay must start from the base
      // again rather than continuing to grow.
      shouldFail = false;
      await handler.processPendingOperations();
      shouldFail = true;
      await handler.enqueue(_uploadOperation('h2'));
      await handler.processPendingOperations();

      expect(delays.last, firstDelay);
    });
  });

  group('one FIFO per file', () {
    test('a file\'s later operation waits behind its failing head', () async {
      final executor = _RecordingExecutor(
        onExecute: (operation) async {
          if (operation.id == 'first') throw _offline;
        },
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([
        _uploadOperation('h1', id: 'first'),
        _uploadOperation('h1', id: 'second'),
      ]);
      await handler.processPendingOperations();

      expect(executor.executed, isEmpty);
      expect((await queue.pending()).map((operation) => operation.id), [
        'first',
        'second',
      ]);
    });

    test('another file passes the failing one in the same pass', () async {
      final executor = _RecordingExecutor(
        onExecute: (operation) async {
          if (operation.file.name == 'h1.pdf') throw _offline;
        },
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([
        _uploadOperation('h1', id: 'blocked'),
        _uploadOperation('h1', id: 'behind'),
        _uploadOperation('h2', id: 'other'),
      ]);
      await handler.processPendingOperations();

      expect(executor.executed, ['h2.pdf']);
    });

    test('the held operation runs once its head succeeds', () async {
      var failFirst = true;
      final executor = _RecordingExecutor(
        onExecute: (operation) async {
          if (operation.id == 'first' && failFirst) throw _offline;
        },
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([
        _uploadOperation('h1', id: 'first'),
        _uploadOperation('h1', id: 'second'),
      ]);
      await handler.processPendingOperations();
      failFirst = false;
      await handler.processPendingOperations();

      expect(executor.executed, ['h1.pdf', 'h1.pdf']);
      expect(await queue.pending(), isEmpty);
    });
  });

  group('failedAttempts and parking', () {
    test('a connection failure never spends an attempt', () async {
      final executor = _RecordingExecutor(
        onExecute: (_) async => throw _offline,
      );
      final handler = handlerWith(executor);

      await handler.enqueue(_uploadOperation('h1', id: 'operation'));
      await handler.processPendingOperations();
      await handler.processPendingOperations();

      expect(_queued(await queue.pending(), 'operation')?.failedAttempts, 0);
    });

    test('a permanent failure spends one and persists it', () async {
      final executor = _RecordingExecutor(
        onExecute: (_) async => throw _permanent,
      );
      final handler = handlerWith(executor);

      // Seeded directly so exactly one pass runs; enqueue would start its own
      // and spend a second attempt.
      await queue.enqueue(_uploadOperation('h1', id: 'operation'));
      await handler.processPendingOperations();
      expect(_queued(await queue.pending(), 'operation')?.failedAttempts, 1);

      // Survives a restart: a fresh queue over the same directory sees it.
      final reopened = SyncQueue(directoryProvider: () async => root);
      expect(_queued(await reopened.pending(), 'operation')?.failedAttempts, 1);
    });

    test('an operation parks at maxFailedAttempts and stays queued', () async {
      final executor = _RecordingExecutor(
        onExecute: (_) async => throw _permanent,
      );
      final handler = handlerWith(executor);

      await handler.enqueue(_uploadOperation('h1', id: 'operation'));
      for (var i = 0; i < FileOperationHandler.maxFailedAttempts + 2; i++) {
        await handler.processPendingOperations();
      }

      expect(
        _queued(await queue.pending(), 'operation')?.failedAttempts,
        FileOperationHandler.maxFailedAttempts,
      );
      expect(executor.executed, isEmpty);
      expect(
        (await handler.timedOutOperations()).map((operation) => operation.id),
        ['operation'],
      );
    });

    test('a timed out operation holds its own file but not another', () async {
      final executor = _RecordingExecutor(
        onExecute: (operation) async {
          if (operation.file.name == 'h1.pdf') throw _permanent;
        },
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([
        _uploadOperation('h1', id: 'timed out'),
        _uploadOperation('h1', id: 'behind'),
      ]);
      for (var i = 0; i < FileOperationHandler.maxFailedAttempts; i++) {
        await handler.processPendingOperations();
      }
      await handler.enqueue(_uploadOperation('h2', id: 'other'));
      await handler.processPendingOperations();

      expect(executor.executed, ['h2.pdf']);
      expect((await queue.pending()).map((operation) => operation.id), [
        'timed out',
        'behind',
      ]);
    });

    test(
      'retryTimedOutOperations clears the count and runs the operation again',
      () async {
        var failing = true;
        final executor = _RecordingExecutor(
          onExecute: (_) async {
            if (failing) throw _permanent;
          },
        );
        final handler = handlerWith(executor);

        await handler.enqueue(_uploadOperation('h1', id: 'operation'));
        for (var i = 0; i < FileOperationHandler.maxFailedAttempts; i++) {
          await handler.processPendingOperations();
        }
        expect(await handler.timedOutOperations(), hasLength(1));

        failing = false;
        await handler.retryTimedOutOperations();

        expect(executor.executed, ['h1.pdf']);
        expect(await queue.pending(), isEmpty);
      },
    );

    test('an operation is attempted once per pass, not once per sweep', () async {
      var failedAttempts = 0;
      final executor = _RecordingExecutor(
        onExecute: (operation) async {
          if (operation.file.name != 'bad.pdf') return;
          failedAttempts++;
          throw _offline;
        },
      );
      final handler = handlerWith(executor);

      // The healthy operations keep the pass sweeping; the failing one must not be
      // retried on every sweep. Seeded directly so exactly one pass runs.
      for (final operation in [
        _uploadOperation('bad'),
        _uploadOperation('ok1'),
        _uploadOperation('ok2'),
        _uploadOperation('ok3'),
      ]) {
        await queue.enqueue(operation);
      }
      await handler.processPendingOperations();

      expect(failedAttempts, 1);
      expect(executor.executed, ['ok1.pdf', 'ok2.pdf', 'ok3.pdf']);
    });
  });

  group('isUploading', () {
    test('is true while the upload is queued, false once applied', () async {
      final executor = _RecordingExecutor();
      final handler = handlerWith(executor);
      final operation = _uploadOperation('h1');

      await handler.enqueue(operation);
      expect(handler.isUploading(operation.file), isTrue);

      await handler.processPendingOperations();
      expect(handler.isUploading(operation.file), isFalse);
    });

    test('stays true while the upload keeps failing', () async {
      final executor = _RecordingExecutor(
        onExecute: (_) => throw _offline,
      );
      final handler = handlerWith(executor);
      final operation = _uploadOperation('h1');

      await handler.enqueue(operation);
      await handler.processPendingOperations();

      expect(handler.isUploading(operation.file), isTrue);
    });

    test('is false once the upload has timed out', () async {
      final executor = _RecordingExecutor(onExecute: (_) => throw _permanent);
      final handler = handlerWith(executor);
      final operation = _uploadOperation('h1');

      await handler.enqueue(operation);
      for (
        var attempt = 0;
        attempt < FileOperationHandler.maxFailedAttempts;
        attempt++
      ) {
        await handler.processPendingOperations();
      }

      // A timed out operation stays queued forever, waiting for the user. Any
      // progress indicator asking this would otherwise never stop spinning.
      expect(await handler.timedOutOperations(), hasLength(1));
      expect(handler.isUploading(operation.file), isFalse);
    });

    test('ignores operations that are not uploads', () async {
      final executor = _RecordingExecutor();
      final handler = handlerWith(executor);
      final operation = _downloadOperation('h1');

      await handler.enqueue(operation);

      expect(handler.isUploading(operation.file), isFalse);
    });
  });
}
