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
import 'package:yust_ui/src/util/offline/yust_file_operation_manager.dart';
import 'package:yust_ui/src/util/offline/yust_offline_storage.dart';
import 'package:yust_ui/src/util/offline/yust_sync_queue.dart';

import 'fake_file_service.dart';

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
  late FakeFileService fileService;
  late Directory root;
  late YustOfflineStorage storage;
  late List<String> executed;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    queue = YustSyncQueue();
    fileService = FakeFileService();
    Yust.fileService = fileService;
    root = Directory.systemTemp.createTempSync('file_operation_queue_test');
    storage = YustOfflineStorage(directoryProvider: () async => root);
    executed = [];
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// A manager whose Storage transfers and document writes run through
  /// [fileService], awaiting [onStep] before each; every applied operation's
  /// file name lands in [executed]. Its retry never fires.
  YustFileOperationManager managerWith({
    Future<void> Function(FakeFileStep step)? onStep,
    Stream<bool>? connectivityStream,
    List<Duration>? delays,
  }) {
    fileService.onStep = onStep;
    final manager = YustFileOperationManager(
      queue: queue,
      documentWriterFor: (_) => fileService.documentWriter,
      storage: storage,
      connectivityStream: connectivityStream ?? const Stream<bool>.empty(),
      delay: (duration) {
        delays?.add(duration);
        return Completer<void>().future;
      },
    );
    final appliedSubscription = manager.applied.listen(
      (operation) => executed.add(operation.file.name!),
    );
    addTearDown(appliedSubscription.cancel);
    addTearDown(manager.dispose);
    return manager;
  }

  group('draining', () {
    test('applies every pending operation and empties the queue', () async {
      final manager = managerWith();

      await manager.enqueueAll([
        _uploadOperation('h1'),
        _uploadOperation('h2'),
      ]);
      await manager.processPendingOperations();

      expect(executed, ['h1.pdf', 'h2.pdf']);
      expect(await queue.getPendingOperations(), isEmpty);
    });

    test('an operation enqueued mid-pass is applied in the same run', () async {
      late YustFileOperationManager manager;
      var injected = false;
      manager = managerWith(
        onStep: (step) async {
          if (step.fileName == 'h1.pdf' && !injected) {
            injected = true;
            await manager.enqueue(_uploadOperation('h2'));
          }
        },
      );

      await manager.enqueue(_uploadOperation('h1'));
      await manager.processPendingOperations();

      expect(executed, ['h1.pdf', 'h2.pdf']);
      expect(await queue.getPendingOperations(), isEmpty);
    });
  });

  group('enqueue does not wait on the network', () {
    test('enqueue returns while the executor is still in flight', () async {
      final gate = Completer<void>();
      final manager = managerWith(onStep: (_) => gate.future);

      // Offline this is the real upload retrying for minutes. The picker awaits
      // enqueue, so it must return as soon as the operation is durably queued.
      await manager.enqueue(_uploadOperation('h1'));

      expect(executed, isEmpty);
      expect(
        (await queue.getPendingOperations()).map(
          (operation) => operation.file.name,
        ),
        [
          'h1.pdf',
        ],
      );

      gate.complete();
      await manager.processPendingOperations();
      expect(executed, ['h1.pdf']);
    });

    test('a failing executor does not surface out of enqueue', () async {
      final manager = managerWith(onStep: (_) async => throw _offline);

      await manager.enqueue(_uploadOperation('h1'));
      await manager.processPendingOperations();

      expect(await queue.getPendingOperations(), hasLength(1));
    });
  });

  group('a failing operation does not strand the operations behind it', () {
    test('the operations behind a failing one are still applied', () async {
      final manager = managerWith(
        onStep: (step) async {
          if (step.fileName == 'h1.pdf') throw _offline;
        },
      );

      await manager.enqueueAll([
        _uploadOperation('h1'),
        _uploadOperation('h2'),
      ]);
      await manager.processPendingOperations();

      expect(executed, ['h2.pdf']);
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
      final manager = managerWith(
        onStep: (step) async {
          if (step.kind == FakeFileStepKind.upload) throw _offline;
        },
      );

      await manager.enqueueAll([
        _uploadOperation('h1'),
        _downloadOperation('h2'),
      ]);
      await manager.processPendingOperations();

      expect(executed, ['h2.pdf']);
    });

    test('a pass in which everything fails stops rather than spins', () async {
      final manager = managerWith(onStep: (_) async => throw _offline);

      await manager.enqueueAll([
        _uploadOperation('h1'),
        _uploadOperation('h2'),
      ]);
      await manager.processPendingOperations().timeout(
        const Duration(seconds: 5),
      );

      expect(executed, isEmpty);
      expect(await queue.getPendingOperations(), hasLength(2));
    });
  });

  group('reconnect handling', () {
    test('a reconnect arriving mid-pass is honoured once it ends', () async {
      final online = StreamController<bool>.broadcast();
      addTearDown(online.close);
      final gate = Completer<void>();
      var failedAttempts = 0;
      final manager = managerWith(
        onStep: (step) async {
          if (step.fileName == 'h1.pdf') return gate.future;
          failedAttempts++;
          // Fails on its one try of the first pass, succeeds afterwards.
          if (failedAttempts <= 1) throw _offline;
        },
        connectivityStream: online.stream,
      );

      await manager.enqueueAll([
        _uploadOperation('h1'),
        _uploadOperation('h2'),
      ]);
      await _settle(); // the pass is timed out inside h1

      online.add(true);
      await _settle(); // the reconnect lands while the pass is still running
      gate.complete();
      await manager.processPendingOperations();

      // Backoff never fires here, so only a honoured reconnect can drain h2.
      expect(executed, ['h1.pdf', 'h2.pdf']);
      expect(await queue.getPendingOperations(), isEmpty);
    });

    test('several reconnects during one pass collapse into one', () async {
      final online = StreamController<bool>.broadcast();
      addTearDown(online.close);
      final gate = Completer<void>();
      var failedAttempts = 0;
      final manager = managerWith(
        onStep: (step) async {
          if (step.fileName == 'h1.pdf') return gate.future;
          failedAttempts++;
          throw _offline;
        },
        connectivityStream: online.stream,
      );

      await manager.enqueueAll([
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
      await manager.processPendingOperations();

      // One try in the first pass, one in the single coalesced follow-up.
      expect(failedAttempts, 2);
    });

    test('a reconnect with an empty queue is a no-op', () async {
      final online = StreamController<bool>.broadcast();
      addTearDown(online.close);
      managerWith(connectivityStream: online.stream);

      online.add(true);
      await _settle();

      expect(executed, isEmpty);
    });
  });

  group('backoff', () {
    test('a retry is scheduled only when an operation failed', () async {
      final delays = <Duration>[];
      var shouldFail = false;
      final manager = managerWith(
        onStep: (_) async {
          if (shouldFail) throw StateError('offline');
        },
        delays: delays,
      );

      await manager.enqueue(_uploadOperation('h1'));
      await manager.processPendingOperations();
      expect(delays, isEmpty);

      shouldFail = true;
      await manager.enqueue(_uploadOperation('h2'));
      await manager.processPendingOperations();
      expect(delays, isNotEmpty);
    });

    test('backoff resets once the queue fully drains', () async {
      final delays = <Duration>[];
      var shouldFail = true;
      final manager = managerWith(
        onStep: (_) async {
          if (shouldFail) throw StateError('offline');
        },
        delays: delays,
      );

      await manager.enqueue(_uploadOperation('h1'));
      await manager.processPendingOperations();
      final firstDelay = delays.single;

      // Drain cleanly, then fail again: the delay must start from the base
      // again rather than continuing to grow.
      shouldFail = false;
      await manager.processPendingOperations();
      shouldFail = true;
      await manager.enqueue(_uploadOperation('h2'));
      await manager.processPendingOperations();

      expect(delays.last, firstDelay);
    });
  });

  group('one FIFO per file', () {
    test('a file\'s later operation waits behind its failing head', () async {
      final manager = managerWith(
        onStep: (step) async {
          throw _offline;
        },
      );

      await manager.enqueueAll([
        _uploadOperation('h1', id: 'first', contentHash: 'v1'),
        _uploadOperation('h1', id: 'second', contentHash: 'v2'),
      ]);
      await manager.processPendingOperations();

      expect(executed, isEmpty);
      expect(
        (await queue.getPendingOperations()).map((operation) => operation.id),
        [
          'first',
          'second',
        ],
      );
    });

    test('another file passes the failing one in the same pass', () async {
      final manager = managerWith(
        onStep: (step) async {
          if (step.fileName == 'h1.pdf') throw _offline;
        },
      );

      await manager.enqueueAll([
        _uploadOperation('h1', id: 'blocked', contentHash: 'v1'),
        _uploadOperation('h1', id: 'behind', contentHash: 'v2'),
        _uploadOperation('h2', id: 'other'),
      ]);
      await manager.processPendingOperations();

      expect(executed, ['h2.pdf']);
    });

    test('the held operation runs once its head succeeds', () async {
      var failFirst = true;
      final manager = managerWith(
        onStep: (step) async {
          if (failFirst) throw _offline;
        },
      );

      await manager.enqueueAll([
        _uploadOperation('h1', id: 'first', contentHash: 'v1'),
        _uploadOperation('h1', id: 'second', contentHash: 'v2'),
      ]);
      await manager.processPendingOperations();
      failFirst = false;
      await manager.processPendingOperations();

      expect(executed, ['h1.pdf', 'h1.pdf']);
      expect(await queue.getPendingOperations(), isEmpty);
    });
  });

  group('permanent failures', () {
    /// One operation of [type] on [fileName], so a test can fail one of each
    /// kind and watch what the manager does with it.
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
      final manager = managerWith(
        onStep: (_) async {
          attempts++;
          throw _offline;
        },
      );

      // Seeded directly so exactly the passes below run; enqueue starts its own.
      await queue.enqueueOperation(_uploadOperation('h1', id: 'operation'));
      await manager.processPendingOperations();
      await manager.processPendingOperations();

      expect(attempts, 2);
      expect(
        _queued(await queue.getPendingOperations(), 'operation')?.failure,
        isNull,
      );
    });

    test('one permanent failure ends the upload and is persisted', () async {
      var attempts = 0;
      final manager = managerWith(
        onStep: (_) async {
          attempts++;
          throw _permanent;
        },
      );

      await queue.enqueueOperation(_uploadOperation('h1', id: 'operation'));
      await manager.processPendingOperations();
      await manager.processPendingOperations();
      await manager.processPendingOperations();

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
      final manager = managerWith(
        onStep: (step) async {
          if (step.fileName == 'h1.pdf') throw _permanent;
        },
      );

      await manager.enqueueAll([
        _uploadOperation('h1', id: 'failed', contentHash: 'v1'),
        _uploadOperation('h1', id: 'behind', contentHash: 'v2'),
      ]);
      await manager.enqueue(_uploadOperation('h2', id: 'other'));
      await manager.processPendingOperations();

      expect(executed, ['h2.pdf']);
      expect(
        (await queue.getPendingOperations()).map((operation) => operation.id),
        ['failed', 'behind'],
      );
    });

    test('an operation that is not an upload is dropped instead', () async {
      final manager = managerWith(onStep: (_) async => throw _permanent);

      // One file each, so all four are eligible in the same sweep.
      await manager.enqueueAll([
        operationOf(YustFileOperationType.rename, fileName: 'h1'),
        operationOf(YustFileOperationType.delete, fileName: 'h2'),
        operationOf(YustFileOperationType.updateMetadata, fileName: 'h3'),
        operationOf(YustFileOperationType.download, fileName: 'h4'),
      ]);
      await manager.processPendingOperations();

      // Nothing kept and nothing to acknowledge: the change simply did not
      // happen, and the display is the document snapshot overlaid with this
      // queue.
      expect(await queue.getPendingOperations(), isEmpty);
    });

    test(
      'discarding a file drops its failure and the chain behind it',
      () async {
        final manager = managerWith(
          onStep: (step) async {
            if (step.fileName == 'h1.pdf') throw _permanent;
          },
        );

        await manager.enqueueAll([
          _uploadOperation('h1', id: 'failed', contentHash: 'v1'),
          _uploadOperation('h1', id: 'behind', contentHash: 'v2'),
          _uploadOperation('h2', id: 'other'),
        ]);
        await manager.processPendingOperations();
        final failedFileKey =
            (await queue.getPendingOperations()).first.fileKey;

        var notifications = 0;
        manager.addListener(() => notifications++);
        await manager.discardOperationsForFile(failedFileKey);

        expect(await queue.getPendingOperations(), isEmpty);
        expect(notifications, 1);
      },
    );

    test('discarding leaves another file\'s operations alone', () async {
      final manager = managerWith(onStep: (_) async => throw _offline);

      await manager.enqueueAll([
        _uploadOperation('h1', id: 'discarded'),
        _uploadOperation('h2', id: 'kept'),
      ]);
      await manager.processPendingOperations();
      final discardedFileKey = _queued(
        await queue.getPendingOperations(),
        'discarded',
      )!.fileKey;

      await manager.discardOperationsForFile(discardedFileKey);

      expect(
        (await queue.getPendingOperations()).map((operation) => operation.id),
        ['kept'],
      );
    });

    test('an operation is attempted once per pass, not once per sweep', () async {
      var attempts = 0;
      final manager = managerWith(
        onStep: (step) async {
          if (step.fileName != 'bad.pdf') return;
          attempts++;
          throw _offline;
        },
      );

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
      await manager.processPendingOperations();

      expect(attempts, 1);
      expect(executed, ['ok1.pdf', 'ok2.pdf', 'ok3.pdf']);
    });
  });

  group('isUploading', () {
    test('is true while the upload is queued, false once applied', () async {
      final manager = managerWith();
      final operation = _uploadOperation('h1');

      await manager.enqueue(operation);
      expect(manager.isUploading(operation.file), isTrue);

      await manager.processPendingOperations();
      expect(manager.isUploading(operation.file), isFalse);
    });

    test('stays true while the upload keeps failing', () async {
      final manager = managerWith(onStep: (_) => throw _offline);
      final operation = _uploadOperation('h1');

      await manager.enqueue(operation);
      await manager.processPendingOperations();

      expect(manager.isUploading(operation.file), isTrue);
    });

    test('is false once the upload has failed for good', () async {
      final manager = managerWith(onStep: (_) => throw _permanent);
      final operation = _uploadOperation('h1');

      await manager.enqueue(operation);
      await manager.processPendingOperations();

      // A failed upload stays queued, waiting for the user. Any progress
      // indicator asking this would otherwise never stop spinning.
      expect(await manager.pending(), hasLength(1));
      expect(manager.isUploading(operation.file), isFalse);
    });

    test('ignores operations that are not uploads', () async {
      final manager = managerWith();
      final operation = _downloadOperation('h1');

      await manager.enqueue(operation);

      expect(manager.isUploading(operation.file), isFalse);
    });
  });

  group('rejects an operation the executor could not address', () {
    YustFileOperation<YustFile> operationOn(
      YustFileOperationType type,
      YustFile file,
    ) => YustFileOperation<YustFile>(type: type, file: file);

    test('an upload with no storage folder', () async {
      final manager = managerWith();
      final operation = operationOn(
        YustFileOperationType.upload,
        YustFile(name: 'a.pdf', hash: 'h1', setCreatedAtToNow: false),
      );

      // Otherwise `storageFolderPath!` throws a transient TypeError forever.
      await expectLater(
        manager.enqueue(operation),
        throwsA(isA<ArgumentError>()),
      );
      expect(await manager.pending(), isEmpty);
    });

    test('a file with no name', () async {
      final manager = managerWith();
      final operation = operationOn(
        YustFileOperationType.upload,
        YustFile(storageFolderPath: 'records/rec1', setCreatedAtToNow: false),
      );

      await expectLater(
        manager.enqueue(operation),
        throwsA(isA<ArgumentError>()),
      );
      expect(await manager.pending(), isEmpty);
    });

    test('but accepts a download addressed only by path', () async {
      final manager = managerWith();
      final operation = operationOn(
        YustFileOperationType.download,
        YustFile(
          name: 'a.pdf',
          hash: 'h1',
          path: 'records/rec1',
          setCreatedAtToNow: false,
        ),
      );

      await manager.enqueue(operation);

      expect(await manager.pending(), hasLength(1));
    });

    test(
      'a batch skips its unaddressable operations and keeps the rest',
      () async {
        // Rejecting a whole record's files over one bad file stopped that
        // record from ever syncing.
        final manager = managerWith();

        await manager.enqueueAll([
          _uploadOperation('h1'),
          operationOn(
            YustFileOperationType.upload,
            YustFile(name: 'a.pdf', hash: 'h2', setCreatedAtToNow: false),
          ),
        ]);
        await manager.processPendingOperations();

        expect(executed, ['h1.pdf']);
        expect(await manager.pending(), isEmpty);
      },
    );
  });
}
