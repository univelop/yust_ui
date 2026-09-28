import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation_error.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation_handler.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation_manager.dart';
import 'package:yust_ui/src/util/offline/yust_sync_queue.dart';

/// Records the name of every operation it is handed; an optional [onExecute]
/// runs first so a test can enqueue more work mid-pass, park the pass, or force
/// a failure.
class _RecordingManager implements YustFileOperationManager {
  _RecordingManager({this.onExecute});

  final Future<void> Function(YustFileOperation<YustFile> operation)? onExecute;
  final List<String> executed = [];

  @override
  Future<void> execute(YustFileOperation<YustFile> operation) async {
    await onExecute?.call(operation);
    executed.add(operation.file.name!);
  }
}

/// [fileName] fixes the file's identity (its `fileKey`); [contentHash] fixes
/// its bytes (its `byteKey`) and defaults to [fileName]. Pass a distinct
/// [contentHash] to queue two non-duplicate uploads of the *same* file entry —
/// a re-upload of new bytes — which the queue keeps rather than dedupes.
YustFileOperation<YustFile> _uploadOperation(
  String fileName, {
  String? id,
  String? contentHash,
}) => YustFileOperation<YustFile>(
  id: id,
  type: YustFileOperationType.upload,
  file: YustFile(
    name: '$fileName.pdf',
    hash: contentHash ?? fileName,
    storageFolderPath: 'records/rec1',
    setCreatedAtToNow: false,
  ),
);

/// What being offline actually throws, as opposed to a permanent failure.
const _offline = SocketException('no route to host');

/// A failure no retry can fix, so it ends the operation.
final _permanent = FirebaseException(
  plugin: 'firebase_storage',
  code: 'permission-denied',
);

YustFileOperation<YustFile>? _queued(
  List<YustFileOperation<YustFile>> operations,
  String id,
) => operations.where((operation) => operation.id == id).firstOrNull;

YustFileOperation<YustFile> _downloadOperation(String hash) =>
    YustFileOperation<YustFile>(
      type: YustFileOperationType.download,
      file: YustFile(
        name: '$hash.pdf',
        hash: hash,
        storageFolderPath: 'records/rec1',
        setCreatedAtToNow: false,
      ),
    );

/// Lets an unawaited drain reach its next suspension point. `Duration.zero` is
/// timer-based, so the queue's file IO gets to complete between turns.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late YustSyncQueue queue;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    queue = YustSyncQueue();
  });

  /// A handler whose backoff never fires, so a test observes exactly the passes
  /// it triggers itself. [delays] collects what the backoff asked for.
  YustFileOperationHandler handlerWith(
    YustFileOperationManager executor, {
    Stream<bool>? connectivityStream,
    List<Duration>? delays,
  }) {
    final handler = YustFileOperationHandler(
      manager: executor,
      queue: queue,
      connectivityStream: connectivityStream ?? const Stream<bool>.empty(),
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
      final executor = _RecordingManager();
      final handler = handlerWith(executor);

      await handler.enqueueAll([
        _uploadOperation('h1'),
        _uploadOperation('h2'),
      ]);
      await handler.processPendingOperations();

      expect(executor.executed, ['h1.pdf', 'h2.pdf']);
      expect(await queue.getPendingOperations(), isEmpty);
    });

    test('an operation enqueued mid-pass is applied in the same run', () async {
      late YustFileOperationHandler handler;
      var injected = false;
      final executor = _RecordingManager(
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
      expect(await queue.getPendingOperations(), isEmpty);
    });
  });

  group('enqueue does not wait on the network', () {
    test('enqueue returns while the executor is still in flight', () async {
      final gate = Completer<void>();
      final executor = _RecordingManager(onExecute: (_) => gate.future);
      final handler = handlerWith(executor);

      // Offline this is the real upload retrying for minutes. The picker awaits
      // enqueue, so it must return as soon as the operation is durably queued.
      await handler.enqueue(_uploadOperation('h1'));

      expect(executor.executed, isEmpty);
      expect(
        (await queue.getPendingOperations()).map(
          (operation) => operation.file.name,
        ),
        [
          'h1.pdf',
        ],
      );

      gate.complete();
      await handler.processPendingOperations();
      expect(executor.executed, ['h1.pdf']);
    });

    test('a failing executor does not surface out of enqueue', () async {
      final executor = _RecordingManager(
        onExecute: (_) async => throw _offline,
      );
      final handler = handlerWith(executor);

      await handler.enqueue(_uploadOperation('h1'));
      await handler.processPendingOperations();

      expect(await queue.getPendingOperations(), hasLength(1));
    });
  });

  group('a failing operation does not strand the operations behind it', () {
    test('the operations behind a failing one are still applied', () async {
      final executor = _RecordingManager(
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
      expect(
        (await queue.getPendingOperations()).map(
          (operation) => operation.file.name,
        ),
        [
          'h1.pdf',
        ],
      );
    });

    test('a failing upload does not block a queued download', () async {
      // The reported bug: a stuck upload sat at the head of the queue and the
      // pinned record's downloads behind it never ran.
      final executor = _RecordingManager(
        onExecute: (operation) async {
          if (operation.type == YustFileOperationType.upload) throw _offline;
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
      final executor = _RecordingManager(
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
      expect(await queue.getPendingOperations(), hasLength(2));
    });
  });

  group('reconnect handling', () {
    test('a reconnect arriving mid-pass is honoured once it ends', () async {
      final online = StreamController<bool>.broadcast();
      addTearDown(online.close);
      final gate = Completer<void>();
      var failedAttempts = 0;
      final executor = _RecordingManager(
        onExecute: (operation) async {
          if (operation.file.name == 'h1.pdf') return gate.future;
          failedAttempts++;
          // Fails on its one try of the first pass, succeeds afterwards.
          if (failedAttempts <= 1) throw _offline;
        },
      );
      final handler = handlerWith(executor, connectivityStream: online.stream);

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
      expect(await queue.getPendingOperations(), isEmpty);
    });

    test('several reconnects during one pass collapse into one', () async {
      final online = StreamController<bool>.broadcast();
      addTearDown(online.close);
      final gate = Completer<void>();
      var failedAttempts = 0;
      final executor = _RecordingManager(
        onExecute: (operation) async {
          if (operation.file.name == 'h1.pdf') return gate.future;
          failedAttempts++;
          throw _offline;
        },
      );
      final handler = handlerWith(executor, connectivityStream: online.stream);

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
      final executor = _RecordingManager();
      handlerWith(executor, connectivityStream: online.stream);

      online.add(true);
      await _settle();

      expect(executor.executed, isEmpty);
    });
  });

  group('backoff', () {
    test('a retry is scheduled only when an operation failed', () async {
      final delays = <Duration>[];
      var shouldFail = false;
      final executor = _RecordingManager(
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
      final executor = _RecordingManager(
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
      final executor = _RecordingManager(
        onExecute: (operation) async {
          if (operation.id == 'first') throw _offline;
        },
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([
        _uploadOperation('h1', id: 'first', contentHash: 'v1'),
        _uploadOperation('h1', id: 'second', contentHash: 'v2'),
      ]);
      await handler.processPendingOperations();

      expect(executor.executed, isEmpty);
      expect(
        (await queue.getPendingOperations()).map((operation) => operation.id),
        [
          'first',
          'second',
        ],
      );
    });

    test('another file passes the failing one in the same pass', () async {
      final executor = _RecordingManager(
        onExecute: (operation) async {
          if (operation.file.name == 'h1.pdf') throw _offline;
        },
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([
        _uploadOperation('h1', id: 'blocked', contentHash: 'v1'),
        _uploadOperation('h1', id: 'behind', contentHash: 'v2'),
        _uploadOperation('h2', id: 'other'),
      ]);
      await handler.processPendingOperations();

      expect(executor.executed, ['h2.pdf']);
    });

    test('the held operation runs once its head succeeds', () async {
      var failFirst = true;
      final executor = _RecordingManager(
        onExecute: (operation) async {
          if (operation.id == 'first' && failFirst) throw _offline;
        },
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([
        _uploadOperation('h1', id: 'first', contentHash: 'v1'),
        _uploadOperation('h1', id: 'second', contentHash: 'v2'),
      ]);
      await handler.processPendingOperations();
      failFirst = false;
      await handler.processPendingOperations();

      expect(executor.executed, ['h1.pdf', 'h1.pdf']);
      expect(await queue.getPendingOperations(), isEmpty);
    });
  });

  group('permanent failures', () {
    /// One operation of [type] on [fileName], so a test can fail one of each
    /// kind and watch what the handler does with it.
    YustFileOperation<YustFile> operationOf(
      YustFileOperationType type, {
      String fileName = 'h1',
      String? id,
    }) => YustFileOperation<YustFile>(
      id: id,
      type: type,
      newName: type == YustFileOperationType.rename ? 'renamed.pdf' : null,
      file: YustFile(
        name: '$fileName.pdf',
        hash: fileName,
        storageFolderPath: 'records/rec1',
        setCreatedAtToNow: false,
      ),
    );

    test('a connection failure records nothing and is attempted again', () async {
      var attempts = 0;
      final executor = _RecordingManager(
        onExecute: (_) async {
          attempts++;
          throw _offline;
        },
      );
      final handler = handlerWith(executor);

      // Seeded directly so exactly the passes below run; enqueue starts its own.
      await queue.enqueueOperation(_uploadOperation('h1', id: 'operation'));
      await handler.processPendingOperations();
      await handler.processPendingOperations();

      expect(attempts, 2);
      expect(
        _queued(await queue.getPendingOperations(), 'operation')?.failure,
        isNull,
      );
    });

    test('one permanent failure ends the upload and is persisted', () async {
      var attempts = 0;
      final executor = _RecordingManager(
        onExecute: (_) async {
          attempts++;
          throw _permanent;
        },
      );
      final handler = handlerWith(executor);

      await queue.enqueueOperation(_uploadOperation('h1', id: 'operation'));
      await handler.processPendingOperations();
      await handler.processPendingOperations();
      await handler.processPendingOperations();

      // Attempted once, not once per pass and not five times.
      expect(attempts, 1);
      expect(
        _queued(await queue.getPendingOperations(), 'operation')?.failure,
        YustFileOperationFailureReason.noPermission,
      );

      // Survives a restart: a fresh queue over the same preferences sees it.
      final reopened = YustSyncQueue();
      expect(
        _queued(await reopened.getPendingOperations(), 'operation')?.failure,
        YustFileOperationFailureReason.noPermission,
      );
    });

    test('a failed upload holds its own file but not another', () async {
      final executor = _RecordingManager(
        onExecute: (operation) async {
          if (operation.file.name == 'h1.pdf') throw _permanent;
        },
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([
        _uploadOperation('h1', id: 'failed', contentHash: 'v1'),
        _uploadOperation('h1', id: 'behind', contentHash: 'v2'),
      ]);
      await handler.enqueue(_uploadOperation('h2', id: 'other'));
      await handler.processPendingOperations();

      expect(executor.executed, ['h2.pdf']);
      expect(
        (await queue.getPendingOperations()).map((operation) => operation.id),
        ['failed', 'behind'],
      );
    });

    test('an operation that is not an upload is dropped instead', () async {
      final executor = _RecordingManager(
        onExecute: (_) async => throw _permanent,
      );
      final handler = handlerWith(executor);

      // One file each, so all four are eligible in the same sweep.
      await handler.enqueueAll([
        operationOf(YustFileOperationType.rename, fileName: 'h1'),
        operationOf(YustFileOperationType.delete, fileName: 'h2'),
        operationOf(YustFileOperationType.updateMetadata, fileName: 'h3'),
        operationOf(YustFileOperationType.download, fileName: 'h4'),
      ]);
      await handler.processPendingOperations();

      // Nothing kept and nothing to acknowledge: the change simply did not
      // happen, and the display is the document snapshot overlaid with this
      // queue.
      expect(await queue.getPendingOperations(), isEmpty);
    });

    test(
      'discarding a file drops its failure and the chain behind it',
      () async {
        final executor = _RecordingManager(
          onExecute: (operation) async {
            if (operation.file.name == 'h1.pdf') throw _permanent;
          },
        );
        final handler = handlerWith(executor);

        await handler.enqueueAll([
          _uploadOperation('h1', id: 'failed', contentHash: 'v1'),
          _uploadOperation('h1', id: 'behind', contentHash: 'v2'),
          _uploadOperation('h2', id: 'other'),
        ]);
        await handler.processPendingOperations();
        final failedFileKey =
            (await queue.getPendingOperations()).first.fileKey;

        var notifications = 0;
        handler.addListener(() => notifications++);
        await handler.discardOperationsForFile(failedFileKey);

        expect(await queue.getPendingOperations(), isEmpty);
        expect(notifications, 1);
      },
    );

    test('discarding leaves another file\'s operations alone', () async {
      final executor = _RecordingManager(
        onExecute: (_) async => throw _offline,
      );
      final handler = handlerWith(executor);

      await handler.enqueueAll([
        _uploadOperation('h1', id: 'discarded'),
        _uploadOperation('h2', id: 'kept'),
      ]);
      await handler.processPendingOperations();
      final discardedFileKey = _queued(
        await queue.getPendingOperations(),
        'discarded',
      )!.fileKey;

      await handler.discardOperationsForFile(discardedFileKey);

      expect(
        (await queue.getPendingOperations()).map((operation) => operation.id),
        ['kept'],
      );
    });

    test('an operation is attempted once per pass, not once per sweep', () async {
      var attempts = 0;
      final executor = _RecordingManager(
        onExecute: (operation) async {
          if (operation.file.name != 'bad.pdf') return;
          attempts++;
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
        await queue.enqueueOperation(operation);
      }
      await handler.processPendingOperations();

      expect(attempts, 1);
      expect(executor.executed, ['ok1.pdf', 'ok2.pdf', 'ok3.pdf']);
    });
  });

  group('isUploading', () {
    test('is true while the upload is queued, false once applied', () async {
      final executor = _RecordingManager();
      final handler = handlerWith(executor);
      final operation = _uploadOperation('h1');

      await handler.enqueue(operation);
      expect(handler.isUploading(operation.file), isTrue);

      await handler.processPendingOperations();
      expect(handler.isUploading(operation.file), isFalse);
    });

    test('stays true while the upload keeps failing', () async {
      final executor = _RecordingManager(
        onExecute: (_) => throw _offline,
      );
      final handler = handlerWith(executor);
      final operation = _uploadOperation('h1');

      await handler.enqueue(operation);
      await handler.processPendingOperations();

      expect(handler.isUploading(operation.file), isTrue);
    });

    test('is false once the upload has failed for good', () async {
      final executor = _RecordingManager(onExecute: (_) => throw _permanent);
      final handler = handlerWith(executor);
      final operation = _uploadOperation('h1');

      await handler.enqueue(operation);
      await handler.processPendingOperations();

      // A failed upload stays queued, waiting for the user. Any progress
      // indicator asking this would otherwise never stop spinning.
      expect(await handler.pending(), hasLength(1));
      expect(handler.isUploading(operation.file), isFalse);
    });

    test('ignores operations that are not uploads', () async {
      final executor = _RecordingManager();
      final handler = handlerWith(executor);
      final operation = _downloadOperation('h1');

      await handler.enqueue(operation);

      expect(handler.isUploading(operation.file), isFalse);
    });
  });

  group('rejects an operation the executor could not address', () {
    YustFileOperation<YustFile> operationOn(
      YustFileOperationType type,
      YustFile file,
    ) => YustFileOperation<YustFile>(type: type, file: file);

    test('an upload with no storage folder', () async {
      final handler = handlerWith(_RecordingManager());
      final operation = operationOn(
        YustFileOperationType.upload,
        YustFile(name: 'a.pdf', hash: 'h1', setCreatedAtToNow: false),
      );

      // Otherwise `storageFolderPath!` throws a transient TypeError forever.
      await expectLater(
        handler.enqueue(operation),
        throwsA(isA<ArgumentError>()),
      );
      expect(await handler.pending(), isEmpty);
    });

    test('a file with no name', () async {
      final handler = handlerWith(_RecordingManager());
      final operation = operationOn(
        YustFileOperationType.upload,
        YustFile(storageFolderPath: 'records/rec1', setCreatedAtToNow: false),
      );

      await expectLater(
        handler.enqueue(operation),
        throwsA(isA<ArgumentError>()),
      );
      expect(await handler.pending(), isEmpty);
    });

    test('but accepts a download addressed only by path', () async {
      final handler = handlerWith(_RecordingManager());
      final operation = operationOn(
        YustFileOperationType.download,
        YustFile(
          name: 'a.pdf',
          hash: 'h1',
          path: 'records/rec1',
          setCreatedAtToNow: false,
        ),
      );

      await handler.enqueue(operation);

      expect(await handler.pending(), hasLength(1));
    });

    test(
      'a batch skips its unaddressable operations and keeps the rest',
      () async {
        // Rejecting a whole record's files over one bad file stopped that
        // record from ever syncing.
        final manager = _RecordingManager();
        final handler = handlerWith(manager);

        await handler.enqueueAll([
          _uploadOperation('h1'),
          operationOn(
            YustFileOperationType.upload,
            YustFile(name: 'a.pdf', hash: 'h2', setCreatedAtToNow: false),
          ),
        ]);
        await handler.processPendingOperations();

        expect(manager.executed, ['h1.pdf']);
        expect(await handler.pending(), isEmpty);
      },
    );
  });
}
