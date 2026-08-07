import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/file_list_controller.dart';
import 'package:yust_ui/src/util/offline/file_operation.dart';
import 'package:yust_ui/src/util/offline/file_operation_handler.dart';
import 'package:yust_ui/src/util/offline/offline_file_target.dart';
import 'package:yust_ui/src/util/offline/offline_storage.dart';
import 'package:yust_ui/src/util/offline/sync_queue.dart';

/// What being offline throws, as opposed to a failure that counts as permanent.
const _offline = SocketException('no route to host');

/// A failure no retry can fix, so it spends the operation's failedAttempts.
final _permanent = FirebaseException(
  plugin: 'firebase_storage',
  code: 'permission-denied',
);

const _target = OfflineFileTarget(
  storageFolderPath: 'records/rec1',
  linkedDocPath: 'records/rec1',
  linkedDocAttribute: 'brickValues.brick1',
  storesFilesAsMap: true,
);

/// Stands in for the real `UploadManager`: when [succeed] it mutates the operation's
/// file the way an upload does — stamping `path` and `url` — before reporting
/// success, so the controller sees the same post-upload state it would in
/// production.
class _FakeExecutor implements FileOperationExecutor {
  _FakeExecutor({this.succeed = true});

  bool succeed;

  /// What a failing execute throws — transient by default, so a test only
  /// spends the operation's failedAttempts when it means to.
  Object failure = _offline;
  final List<String> executed = [];

  @override
  Set<FileOperationType> get handledTypes => {
    FileOperationType.upload,
    FileOperationType.rename,
    FileOperationType.delete,
    FileOperationType.download,
  };

  @override
  Future<void> execute(FileOperation<YustFile> operation) async {
    if (!succeed) throw failure;
    operation.file
      ..path = operation.file.storageFolderPath
      // ignore: deprecated_member_use
      ..url = 'https://cdn.test/${operation.file.name}';
    executed.add(operation.fileKey);
  }
}

/// A file as the pickers actually construct one: `path` is stamped at pick
/// time, before any upload has happened (yust_file_picker.dart `processFile`
/// and yust_image_helpers.dart `processImage` both do this).
YustFile _pickedFile(String name, String content) => YustFile(
  name: name,
  bytes: Uint8List.fromList(content.codeUnits),
  storageFolderPath: _target.storageFolderPath,
  linkedDocPath: _target.linkedDocPath,
  linkedDocAttribute: _target.linkedDocAttribute,
  path: _target.storageFolderPath,
  setCreatedAtToNow: false,
);

/// An already-persisted file as it comes back from the record snapshot.
YustFile _persistedFile(String name, String hash) => YustFile(
  name: name,
  hash: hash,
  path: _target.storageFolderPath,
  // ignore: deprecated_member_use
  url: 'https://cdn.test/$name',
  setCreatedAtToNow: false,
);

void main() {
  late Directory root;
  late SyncQueue queue;
  late OfflineStorage storage;
  late _FakeExecutor executor;
  late FileOperationHandler handler;

  /// A handler whose retry never fires, so a failed operation stays pending for the
  /// duration of a test instead of churning in the background.
  FileOperationHandler buildHandler([FileOperationExecutor? which]) {
    final built = FileOperationHandler(
      executors: [which ?? executor],
      queue: queue,
      onlineStream: const Stream<bool>.empty(),
      delay: (_) => Completer<void>().future,
    );
    addTearDown(built.dispose);
    return built;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('file_list_controller_test');
    queue = SyncQueue(directoryProvider: () async => root);
    storage = OfflineStorage(directoryProvider: () async => root);
    executor = _FakeExecutor();
    handler = buildHandler();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  FileListController<YustFile> buildController({
    FileOperationHandler? on,
    void Function(List<YustFile>)? onOnlineFilesChanged,
  }) {
    final controller = FileListController<YustFile>(
      handler: on ?? handler,
      target: _target,
      storage: storage,
      onOnlineFilesChanged: onOnlineFilesChanged,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  group('classification of pending vs. uploaded files', () {
    test('a picked file whose upload is still queued is not online', () async {
      executor.succeed = false;
      final controller = buildController();
      await controller.setOnlineFiles([]);

      await controller.add(_pickedFile('plan.pdf', 'pdf-bytes'));
      await handler.processPendingOperations();
      await controller.settled;

      // `path` is set at pick time, so it alone cannot mean "persisted".
      expect(controller.onlineFiles, isEmpty);
    });

    test('a picked file whose upload is still queued is displayed', () async {
      executor.succeed = false;
      final controller = buildController();
      await controller.setOnlineFiles([]);

      await controller.add(_pickedFile('plan.pdf', 'pdf-bytes'));
      await handler.processPendingOperations();
      await controller.settled;

      expect(controller.files.map((file) => file.name), ['plan.pdf']);
    });

    test(
      'a file becomes online once its upload operation is applied',
      () async {
        final controller = buildController();
        await controller.setOnlineFiles([]);

        await controller.add(_pickedFile('plan.pdf', 'pdf-bytes'));
        await handler.processPendingOperations();
        await controller.settled;

        expect(controller.onlineFiles.map((file) => file.name), ['plan.pdf']);
        expect(await queue.pending(), isEmpty);
      },
    );

    test('a file restored from the persisted queue is still pending', () async {
      executor.succeed = false;
      final first = buildController();
      await first.setOnlineFiles([]);
      await first.add(_pickedFile('plan.pdf', 'pdf-bytes'));
      await handler.processPendingOperations();
      await first.settled;

      // Simulate a restart: a fresh queue, handler and controller over the same
      // directory, so the operation is read back from disk.
      final restartedQueue = SyncQueue(directoryProvider: () async => root);
      final restartedHandler = FileOperationHandler(
        executors: [_FakeExecutor(succeed: false)],
        queue: restartedQueue,
        onlineStream: const Stream<bool>.empty(),
        delay: (_) => Completer<void>().future,
      );
      addTearDown(restartedHandler.dispose);
      final restored = buildController(on: restartedHandler);
      await restored.setOnlineFiles([]);
      await restored.settled;

      expect(restored.files.map((file) => file.name), ['plan.pdf']);
      expect(restored.onlineFiles, isEmpty);
    });

    test('a persisted file with no queued operation is online', () async {
      final controller = buildController();

      await controller.setOnlineFiles([_persistedFile('old.pdf', 'h-old')]);
      await controller.settled;

      expect(controller.onlineFiles.map((file) => file.name), ['old.pdf']);
    });
  });

  group('promotion of an applied upload', () {
    test('an applied upload stays visible without a re-feed', () async {
      final controller = buildController();
      await controller.setOnlineFiles([]);

      await controller.add(_pickedFile('plan.pdf', 'pdf-bytes'));
      await handler.processPendingOperations();
      await controller.settled;

      // The operation has left the queue, so the pending overlay no longer carries it;
      // it must have been promoted into the online set instead of vanishing.
      expect(await queue.pending(), isEmpty);
      expect(controller.files.map((file) => file.name), ['plan.pdf']);
    });

    test('a promoted file carries the executor path and url', () async {
      final controller = buildController();
      await controller.setOnlineFiles([]);

      await controller.add(_pickedFile('plan.pdf', 'pdf-bytes'));
      await handler.processPendingOperations();
      await controller.settled;

      final promoted = controller.onlineFiles.single;
      expect(promoted.path, _target.storageFolderPath);
      // ignore: deprecated_member_use
      expect(promoted.url, 'https://cdn.test/plan.pdf');
    });

    test('a later setOnlineFiles does not duplicate a promoted file', () async {
      final controller = buildController();
      await controller.setOnlineFiles([]);
      await controller.add(_pickedFile('plan.pdf', 'pdf-bytes'));
      await handler.processPendingOperations();
      await controller.settled;

      final uploaded = controller.onlineFiles.single;
      await controller.setOnlineFiles([uploaded]);
      await controller.settled;

      expect(controller.files, hasLength(1));
    });

    test('a failed upload is not promoted', () async {
      executor.succeed = false;
      final controller = buildController();
      await controller.setOnlineFiles([]);

      await controller.add(_pickedFile('plan.pdf', 'pdf-bytes'));
      await handler.processPendingOperations();
      await controller.settled;

      expect(controller.onlineFiles, isEmpty);
      expect(await queue.pending(), hasLength(1));
    });

    test('a cancelled upload is not promoted', () async {
      executor.succeed = false;
      final controller = buildController();
      await controller.setOnlineFiles([]);
      final file = _pickedFile('plan.pdf', 'pdf-bytes');
      await controller.add(file);
      await handler.processPendingOperations();
      await controller.settled;

      // Deleting a file that is still queued drops its operation rather than applying
      // it, so it must not be treated as uploaded.
      await controller.delete(file);
      await controller.settled;

      expect(controller.onlineFiles, isEmpty);
      expect(controller.files, isEmpty);
    });
  });

  group('a mutation returns with the overlay already current', () {
    test('add: the new file is not reported online on return', () async {
      executor.succeed = false;
      final controller = buildController();
      await controller.setOnlineFiles([]);

      await controller.add(_pickedFile('plan.pdf', 'pdf-bytes'));

      // No drain, no settle. The picker reads onlineFiles the instant `add`
      // returns and writes it straight to the record, so a queue read still in
      // flight here is what stored an entry with no bytes behind it in Storage.
      expect(controller.onlineFiles, isEmpty);
      expect(controller.files.map((file) => file.name), ['plan.pdf']);
    });

    test('delete: the file is gone from the overlay on return', () async {
      executor.succeed = false;
      final controller = buildController();
      await controller.setOnlineFiles([]);
      final file = _pickedFile('plan.pdf', 'pdf-bytes');
      await controller.add(file);

      await controller.delete(file);

      expect(controller.files, isEmpty);
    });
  });

  group('the online set is reported after an upload is applied', () {
    test('the host is told about the file once it is persisted', () async {
      final emitted = <List<String>>[];
      final controller = buildController(
        onOnlineFilesChanged: (files) =>
            emitted.add(files.map((file) => file.name ?? '').toList()),
      );
      await controller.setOnlineFiles([_persistedFile('a.pdf', 'h-a')]);

      await controller.add(_pickedFile('plan.pdf', 'pdf-bytes'));
      await handler.processPendingOperations();
      await controller.settled;

      // The host uses this to refresh its in-memory value; it must eventually
      // see the uploaded file so a later save of the record does not drop it.
      expect(emitted.last, containsAll(<String>['a.pdf', 'plan.pdf']));
    });
  });

  group('rename', () {
    test('reports the updated list to the host', () async {
      executor.succeed = false;
      final emitted = <List<String>>[];
      final controller = buildController(
        onOnlineFilesChanged: (files) =>
            emitted.add(files.map((file) => file.name ?? '').toList()),
      );
      await controller.setOnlineFiles([_persistedFile('old.pdf', 'h-a')]);

      await controller.rename(controller.files.single, 'new.pdf');

      // Like the other mutations, rename must leave the host's in-memory value
      // current when it returns — not only once the operation is applied.
      expect(emitted.last, ['new.pdf']);
    });
  });

  group('a snapshot that predates the upload does not drop the file', () {
    test('an upload made here survives a stale reconciliation', () async {
      final controller = buildController();
      await controller.setOnlineFiles([_persistedFile('a.pdf', 'h-a')]);
      await controller.add(_pickedFile('plan.pdf', 'pdf-bytes'));
      await handler.processPendingOperations();
      await controller.settled;

      // The record stream emits a snapshot taken before the doc write landed.
      await controller.setOnlineFiles([_persistedFile('a.pdf', 'h-a')]);
      await controller.settled;

      expect(
        controller.files.map((file) => file.name),
        containsAll(<String>['a.pdf', 'plan.pdf']),
      );
    });

    test('it is carried once only, so a remote delete still wins', () async {
      final controller = buildController();
      await controller.setOnlineFiles([]);
      await controller.add(_pickedFile('plan.pdf', 'pdf-bytes'));
      await handler.processPendingOperations();
      await controller.settled;

      // First stale snapshot: carried. Second: the file is genuinely gone —
      // holding it indefinitely would resurrect a file deleted elsewhere.
      await controller.setOnlineFiles([]);
      await controller.settled;
      await controller.setOnlineFiles([]);
      await controller.settled;

      expect(controller.files, isEmpty);
    });

    test('a file deleted here is not carried over', () async {
      final controller = buildController();
      await controller.setOnlineFiles([]);
      final file = _pickedFile('plan.pdf', 'pdf-bytes');
      await controller.add(file);
      await handler.processPendingOperations();
      await controller.settled;

      await controller.delete(file);
      await handler.processPendingOperations();
      await controller.settled;
      await controller.setOnlineFiles([]);
      await controller.settled;

      expect(controller.files, isEmpty);
    });
  });

  group('regression: the #7710 record clobber', () {
    test('the emitted online set never gains a queued file', () async {
      executor.succeed = false;
      final emitted = <List<String>>[];
      final controller = buildController(
        onOnlineFilesChanged: (files) =>
            emitted.add(files.map((file) => file.name ?? '').toList()),
      );
      await controller.setOnlineFiles([_persistedFile('a.pdf', 'h-a')]);
      await controller.settled;

      await controller.add(_pickedFile('offline.pdf', 'pdf-bytes'));
      await handler.processPendingOperations();
      await controller.settled;

      // Every emission is what would be written to `brickValues.<brickId>`.
      // A queued file appearing here is what persisted a url-less entry and
      // overwrote the file another device had added.
      expect(emitted, isNotEmpty);
      for (final files in emitted) {
        expect(files, isNot(contains('offline.pdf')));
      }
    });
  });

  group('timed out files', () {
    test(
      'a file is timed out once its upload runs out of failedAttempts',
      () async {
        executor
          ..succeed = false
          ..failure = _permanent;
        final controller = buildController();
        await controller.setOnlineFiles([]);
        final file = _pickedFile('plan.pdf', 'pdf-bytes');

        await controller.add(file);
        expect(controller.isTimedOut(file), isFalse);

        for (var i = 0; i < FileOperationHandler.maxFailedAttempts; i++) {
          await handler.processPendingOperations();
        }
        await controller.settled;

        expect(controller.isTimedOut(file), isTrue);
        // Still listed and still pending — timed out is not lost.
        expect(controller.isPendingUpload(file), isTrue);
        expect(controller.files.map((f) => f.name), ['plan.pdf']);
        expect(controller.onlineFiles, isEmpty);
      },
    );

    test('a file failing on the connection is never timed out', () async {
      executor.succeed = false;
      final controller = buildController();
      await controller.setOnlineFiles([]);
      final file = _pickedFile('plan.pdf', 'pdf-bytes');

      await controller.add(file);
      for (var i = 0; i < FileOperationHandler.maxFailedAttempts + 2; i++) {
        await handler.processPendingOperations();
      }
      await controller.settled;

      expect(controller.isTimedOut(file), isFalse);
    });

    test(
      'retryTimedOutOperations clears the marker once the operation succeeds',
      () async {
        executor
          ..succeed = false
          ..failure = _permanent;
        final controller = buildController();
        await controller.setOnlineFiles([]);
        final file = _pickedFile('plan.pdf', 'pdf-bytes');

        await controller.add(file);
        for (var i = 0; i < FileOperationHandler.maxFailedAttempts; i++) {
          await handler.processPendingOperations();
        }
        await controller.settled;
        expect(controller.isTimedOut(file), isTrue);

        executor.succeed = true;
        await handler.retryTimedOutOperations();
        await controller.settled;

        expect(controller.isTimedOut(file), isFalse);
        expect(controller.onlineFiles.map((f) => f.name), ['plan.pdf']);
      },
    );
  });
}
