import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation.dart';
import 'package:yust_ui/src/util/offline/yust_offline_storage.dart';
import 'package:yust_ui/src/util/offline/yust_sync_queue.dart';

final _t1 = DateTime.utc(2026, 1, 1, 10, 0);
final _t2 = DateTime.utc(2026, 1, 1, 10, 1);

YustFileOperation<YustFile> _operation(
  YustFileOperationType type, {
  String hash = 'h1',
  String? name,
  String? newName,
  DateTime? createdAt,
}) => YustFileOperation<YustFile>(
  type: type,
  file: YustFile(
    name: name ?? '$hash.pdf',
    hash: hash,
    storageFolderPath: 'records/rec1',
    setCreatedAtToNow: false,
  ),
  newName: newName,
  createdAt: createdAt,
);

void main() {
  late Directory root;
  late YustSyncQueue queue;

  setUp(() {
    root = Directory.systemTemp.createTempSync('sync_queue_test');
    queue = YustSyncQueue(
      storage: YustOfflineStorage(directoryProvider: () async => root),
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('enqueue then pending lists the operations, oldest first', () async {
    await queue.enqueueOperation(
      _operation(YustFileOperationType.upload, hash: 'h1', createdAt: _t1),
    );
    await queue.enqueueOperation(
      _operation(YustFileOperationType.delete, hash: 'h2', createdAt: _t2),
    );

    final operations = await queue.getPendingOperations();
    expect(operations.map((operation) => operation.type), [
      YustFileOperationType.upload,
      YustFileOperationType.delete,
    ]);
  });

  test('remove drops the operation by id, leaving the rest', () async {
    await queue.enqueueOperation(
      _operation(YustFileOperationType.upload, hash: 'h1'),
    );
    await queue.enqueueOperation(
      _operation(YustFileOperationType.upload, hash: 'h2'),
    );

    final operations = await queue.getPendingOperations();
    await queue.removeOperation(operations.first);
    expect(
      (await queue.getPendingOperations()).map(
        (operation) => operation.file.name,
      ),
      [
        'h2.pdf',
      ],
    );
  });

  group('dedupes work already queued', () {
    test('an exact duplicate is enqueued only once', () async {
      await queue.enqueueOperation(
        _operation(YustFileOperationType.upload, name: 'a.pdf', hash: 'v1'),
      );
      await queue.enqueueOperation(
        _operation(YustFileOperationType.upload, name: 'a.pdf', hash: 'v1'),
      );

      expect((await queue.getPendingOperations()).length, 1);
    });

    test('a re-upload with new bytes of the same file is kept', () async {
      await queue.enqueueOperation(
        _operation(YustFileOperationType.upload, name: 'a.pdf', hash: 'v1'),
      );
      await queue.enqueueOperation(
        _operation(YustFileOperationType.upload, name: 'a.pdf', hash: 'v2'),
      );

      expect((await queue.getPendingOperations()).length, 2);
    });

    test('a different operation kind on the same file is kept', () async {
      await queue.enqueueOperation(
        _operation(YustFileOperationType.upload, name: 'a.pdf', hash: 'v1'),
      );
      await queue.enqueueOperation(
        _operation(YustFileOperationType.delete, name: 'a.pdf', hash: 'v1'),
      );

      expect((await queue.getPendingOperations()).map((op) => op.type), [
        YustFileOperationType.upload,
        YustFileOperationType.delete,
      ]);
    });

    test('a rename to a different name is kept', () async {
      await queue.enqueueOperation(
        _operation(
          YustFileOperationType.rename,
          name: 'a.pdf',
          newName: 'b.pdf',
        ),
      );
      await queue.enqueueOperation(
        _operation(
          YustFileOperationType.rename,
          name: 'a.pdf',
          newName: 'c.pdf',
        ),
      );

      expect((await queue.getPendingOperations()).length, 2);
    });
  });

  test('remove is a no-op when the operation is already gone', () async {
    await queue.enqueueOperation(
      _operation(YustFileOperationType.upload, hash: 'h1'),
    );
    final operations = await queue.getPendingOperations();
    await queue.removeOperation(operations.first);
    await queue.removeOperation(operations.first);
    expect(await queue.getPendingOperations(), isEmpty);
  });

  test('the queue survives a restart (new instance, same directory)', () async {
    await queue.enqueueOperation(
      _operation(
        YustFileOperationType.rename,
        name: 'a.pdf',
        newName: 'b.pdf',
        createdAt: _t1,
      ),
    );

    final reopened = YustSyncQueue(
      storage: YustOfflineStorage(directoryProvider: () async => root),
    );
    final operations = await reopened.getPendingOperations();
    expect(operations.single.type, YustFileOperationType.rename);
    expect(operations.single.newName, 'b.pdf');
  });

  test('concurrent enqueues do not clobber each other (serialised)', () async {
    // Fire many enqueues without awaiting between them, so their load→save
    // cycles overlap. Without the mutex, later saves drop earlier operations.
    final futures = [
      for (var i = 0; i < 20; i++)
        queue.enqueueOperation(
          _operation(YustFileOperationType.upload, hash: 'h$i', name: '$i.pdf'),
        ),
    ];
    await Future.wait(futures);

    final names = (await queue.getPendingOperations())
        .map((operation) => operation.file.name)
        .toSet();
    expect(names, {for (var i = 0; i < 20; i++) '$i.pdf'});
  });

  test('interleaved enqueue and remove keep the surviving operation', () async {
    await queue.enqueueOperation(
      _operation(YustFileOperationType.upload, hash: 'h1', name: '1.pdf'),
    );
    final existing = (await queue.getPendingOperations()).single;

    // Overlap a remove of the existing operation with an enqueue of a new one.
    await Future.wait([
      queue.removeOperation(existing),
      queue.enqueueOperation(
        _operation(YustFileOperationType.upload, hash: 'h2', name: '2.pdf'),
      ),
    ]);

    expect(
      (await queue.getPendingOperations()).map(
        (operation) => operation.file.name,
      ),
      [
        '2.pdf',
      ],
    );
  });

  test('a queued image operation keeps its YustImage subtype', () async {
    await queue.enqueueOperation(
      YustFileOperation<YustImage>(
        type: YustFileOperationType.upload,
        file: YustImage(name: 'photo.jpg', hash: 'img1')
          ..location = YustGeoLocation(latitude: 48.1, longitude: 11.5),
        createdAt: _t1,
      ),
    );

    final operations = await queue.getPendingOperations();
    expect(operations.single.file, isA<YustImage>());
    expect((operations.single.file as YustImage).location?.latitude, 48.1);
  });

  group('persist', () {
    test(
      'writes an in-place failedAttempts change, surviving a restart',
      () async {
        await queue.enqueueOperation(
          _operation(YustFileOperationType.upload, hash: 'h1', createdAt: _t1),
        );
        await queue.enqueueOperation(
          _operation(YustFileOperationType.upload, hash: 'h2', createdAt: _t2),
        );

        (await queue.getPendingOperations()).first.failedAttempts++;
        await queue.persist();

        final reloaded = YustSyncQueue(
          storage: YustOfflineStorage(directoryProvider: () async => root),
        );
        final operations = await reloaded.getPendingOperations();
        expect(operations.map((operation) => operation.file.name), [
          'h1.pdf',
          'h2.pdf',
        ]);
        expect(operations.first.failedAttempts, 1);
      },
    );
  });

  group('in memory (web)', () {
    late YustSyncQueue memoryQueue;

    setUp(() => memoryQueue = YustSyncQueue.inMemory());

    test('keeps the bytes, the only copy when nothing is cached', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      await memoryQueue.enqueueOperation(
        YustFileOperation<YustFile>(
          type: YustFileOperationType.upload,
          file: YustFile(
            name: 'a.pdf',
            hash: 'h1',
            bytes: bytes,
            storageFolderPath: 'records/rec1',
          )..storageFolderPath = 'folder',
        ),
      );

      expect(
        (await memoryQueue.getPendingOperations()).single.file.bytes,
        bytes,
      );
    });

    test('an in-place change and remove address the same entries', () async {
      await memoryQueue.enqueueOperation(
        _operation(YustFileOperationType.upload, hash: 'h1', createdAt: _t1),
      );
      await memoryQueue.enqueueOperation(
        _operation(YustFileOperationType.upload, hash: 'h2', createdAt: _t2),
      );

      (await memoryQueue.getPendingOperations()).first.failedAttempts++;
      await memoryQueue.removeOperation(
        (await memoryQueue.getPendingOperations()).last,
      );

      final operations = await memoryQueue.getPendingOperations();
      expect(operations.map((operation) => operation.file.name), ['h1.pdf']);
      expect(operations.single.failedAttempts, 1);
    });
  });
}
