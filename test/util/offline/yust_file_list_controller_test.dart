import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/yust_file_list_controller.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation_error.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation_handler.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation_manager.dart';
import 'package:yust_ui/src/util/offline/yust_firebase_file_location.dart';
import 'package:yust_ui/src/util/offline/yust_offline_storage.dart';
import 'package:yust_ui/src/util/offline/yust_sync_queue.dart';

/// What being offline throws, as opposed to a failure that counts as permanent.
const _offline = SocketException('no route to host');

/// A failure no retry can fix, so it ends the operation.
final _permanent = FirebaseException(
  plugin: 'firebase_storage',
  code: 'permission-denied',
);

const _target = YustFirebaseFileLocation(
  storageFolderPath: 'records/rec1',
  linkedDocPath: 'records/rec1',
  linkedDocAttribute: 'brickValues.brick1',
  storesFilesAsMap: true,
);

/// A target with no document behind it — a picker bound to a brick's settings,
/// an email attachment list. Nothing else persists these files, so the host is
/// the one that has to hear about them.
const _unlinkedTarget = YustFirebaseFileLocation(
  storageFolderPath: 'settings/brick1',
);

/// A second unlinked target, as a FileBrick and an ImageBrick on one record
/// spec produce.
const _otherUnlinkedTarget = YustFirebaseFileLocation(
  storageFolderPath: 'settings/brick2',
);

/// A picked file for [target], which may carry no document.
YustFile _pickedFileFor(YustFirebaseFileLocation target, String name) =>
    YustFile(
      name: name,
      bytes: Uint8List.fromList(name.codeUnits),
      storageFolderPath: target.storageFolderPath,
      linkedDocPath: target.linkedDocPath,
      linkedDocAttribute: target.linkedDocAttribute,
      path: target.storageFolderPath,
      setCreatedAtToNow: false,
    );

/// Stands in for the real `YustFileOperationManager`: when [succeed] it mutates
/// the operation's file the way an upload does — stamping `path` and `url` —
/// before reporting success, so the controller sees the same post-upload state
/// it would in production.
class _FakeManager implements YustFileOperationManager {
  _FakeManager({this.succeed = true});

  bool succeed;

  /// What a failing execute throws — transient by default, so a test only ends
  /// an operation for good when it means to.
  Object failure = _offline;
  final List<String> executed = [];

  @override
  Future<void> execute(YustFileOperation<YustFile> operation) async {
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
  late YustSyncQueue queue;
  late YustOfflineStorage storage;
  late _FakeManager executor;
  late YustFileOperationHandler handler;

  /// A handler whose retry never fires, so a failed operation stays pending for the
  /// duration of a test instead of churning in the background.
  YustFileOperationHandler buildHandler([YustFileOperationManager? which]) {
    final built = YustFileOperationHandler(
      manager: which ?? executor,
      queue: queue,
      connectivityStream: const Stream<bool>.empty(),
      delay: (_) => Completer<void>().future,
    );
    addTearDown(built.dispose);
    return built;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('file_list_controller_test');
    storage = YustOfflineStorage(directoryProvider: () async => root);
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    queue = YustSyncQueue();
    executor = _FakeManager();
    handler = buildHandler();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  YustFileListController<YustFile> buildController({
    YustFileOperationHandler? on,
    YustFirebaseFileLocation target = _target,
    void Function(List<YustFile>)? onOnlineFilesChanged,
  }) {
    final controller = YustFileListController<YustFile>(
      handler: on ?? handler,
      firebaseLocation: target,
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
        expect(await queue.getPendingOperations(), isEmpty);
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
      // storage, so the operation is read back from the preferences.
      final restartedQueue = YustSyncQueue();
      final restartedHandler = YustFileOperationHandler(
        manager: _FakeManager(succeed: false),
        queue: restartedQueue,
        connectivityStream: const Stream<bool>.empty(),
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

    test('two persisted entries holding the same bytes both show', () async {
      // The same image uploaded twice: one content hash, two record entries.
      final controller = buildController();

      await controller.setOnlineFiles([
        _persistedFile('first.jpeg', 'same-hash'),
        _persistedFile('second.jpeg', 'same-hash'),
      ]);
      await controller.settled;

      expect(controller.files.map((file) => file.name), [
        'first.jpeg',
        'second.jpeg',
      ]);
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
      expect(await queue.getPendingOperations(), isEmpty);
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
      expect(await queue.getPendingOperations(), hasLength(1));
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
        target: _unlinkedTarget,
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

  group('a document-backed target reports nothing to its host', () {
    test('an add is not reported back', () async {
      var reports = 0;
      final controller = buildController(
        onOnlineFilesChanged: (_) => reports++,
      );
      await controller.setOnlineFiles([_persistedFile('a.pdf', 'h-a')]);

      await controller.add(_pickedFile('plan.pdf', 'pdf-bytes'));
      await handler.processPendingOperations();
      await controller.settled;

      // The queue's own document writer persists the file, and the host reads
      // the result from the document's stream. Reporting it here as well would
      // have the host write the same list a second time, which rebuilds the
      // picker, which reconciles, which reports again — the loop that rebuilt
      // the whole screen on every keystroke.
      expect(reports, 0);
    });

    test('a delete is not reported back', () async {
      var reports = 0;
      final controller = buildController(
        onOnlineFilesChanged: (_) => reports++,
      );
      await controller.setOnlineFiles([_persistedFile('a.pdf', 'h-a')]);

      await controller.delete(controller.files.single);

      expect(reports, 0);
    });
  });

  group('rename', () {
    test('reports the updated list to the host', () async {
      executor.succeed = false;
      final emitted = <List<String>>[];
      final controller = buildController(
        target: _unlinkedTarget,
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
        target: _unlinkedTarget,
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

  group('failed uploads', () {
    test('one permanent failure ends the upload and keeps it listed', () async {
      executor
        ..succeed = false
        ..failure = _permanent;
      final controller = buildController();
      await controller.setOnlineFiles([]);
      final file = _pickedFile('plan.pdf', 'pdf-bytes');

      await controller.add(file);
      await handler.processPendingOperations();
      await controller.settled;

      expect(
        controller.failedUploadFor(file)?.failure,
        YustFileOperationFailureReason.noPermission,
      );
      // Still listed and still pending — a failed upload is not lost.
      expect(controller.isPendingUpload(file), isTrue);
      expect(controller.files.map((f) => f.name), ['plan.pdf']);
      expect(controller.onlineFiles, isEmpty);
    });

    test('a file failing on the connection never counts as failed', () async {
      executor.succeed = false;
      final controller = buildController();
      await controller.setOnlineFiles([]);
      final file = _pickedFile('plan.pdf', 'pdf-bytes');

      await controller.add(file);
      await handler.processPendingOperations();
      await handler.processPendingOperations();
      await controller.settled;

      expect(controller.failedUploadFor(file), isNull);
    });

    test('discarding drops the operation and the file with it', () async {
      executor
        ..succeed = false
        ..failure = _permanent;
      final controller = buildController();
      await controller.setOnlineFiles([]);
      final file = _pickedFile('plan.pdf', 'pdf-bytes');

      await controller.add(file);
      await handler.processPendingOperations();
      await controller.settled;
      expect(controller.failedUploadFor(file), isNotNull);

      await controller.discardFailedUploadFor(file);
      await controller.settled;

      // The queue is empty, so the display is the document snapshot again.
      expect(await handler.pending(), isEmpty);
      expect(controller.failedUploadFor(file), isNull);
      expect(controller.files, isEmpty);
    });
  });

  group('two unlinked targets do not claim each other\'s operations', () {
    test('a pending upload shows only in the picker that made it', () async {
      executor.succeed = false;
      final owner = buildController(target: _unlinkedTarget);
      final other = buildController(target: _otherUnlinkedTarget);
      await owner.setOnlineFiles([]);
      await other.setOnlineFiles([]);

      await owner.add(_pickedFileFor(_unlinkedTarget, 'own.pdf'));
      await handler.processPendingOperations();
      await owner.settled;
      await other.settled;

      expect(owner.files.map((file) => file.name), ['own.pdf']);
      expect(other.files, isEmpty);
    });

    test('an applied upload is promoted only into its own target', () async {
      final owner = buildController(target: _unlinkedTarget);
      final other = buildController(target: _otherUnlinkedTarget);
      await owner.setOnlineFiles([]);
      await other.setOnlineFiles([]);

      await owner.add(_pickedFileFor(_unlinkedTarget, 'own.pdf'));
      await handler.processPendingOperations();
      await owner.settled;
      await other.settled;

      expect(owner.onlineFiles.map((file) => file.name), ['own.pdf']);
      expect(other.onlineFiles, isEmpty);
    });

    test('the other host is never asked to persist a foreign file', () async {
      final ownerEmissions = <List<String>>[];
      final otherEmissions = <List<String>>[];
      final owner = buildController(
        target: _unlinkedTarget,
        onOnlineFilesChanged: (files) =>
            ownerEmissions.add(files.map((file) => file.name!).toList()),
      );
      final other = buildController(
        target: _otherUnlinkedTarget,
        onOnlineFilesChanged: (files) =>
            otherEmissions.add(files.map((file) => file.name!).toList()),
      );
      await owner.setOnlineFiles([]);
      await other.setOnlineFiles([]);

      await owner.add(_pickedFileFor(_unlinkedTarget, 'own.pdf'));
      await handler.processPendingOperations();
      await owner.settled;
      await other.settled;

      // Otherwise the foreign file is written into the other brick's value.
      expect(ownerEmissions.last, ['own.pdf']);
      expect(otherEmissions.every((emission) => emission.isEmpty), isTrue);
    });

    test('two controllers on the same target still share', () async {
      executor.succeed = false;
      final first = buildController(target: _unlinkedTarget);
      final second = buildController(target: _unlinkedTarget);
      await first.setOnlineFiles([]);
      await second.setOnlineFiles([]);

      await first.add(_pickedFileFor(_unlinkedTarget, 'shared.pdf'));
      await handler.processPendingOperations();
      await first.settled;
      await second.settled;

      expect(second.files.map((file) => file.name), ['shared.pdf']);
    });
  });
}
