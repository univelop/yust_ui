import 'dart:io';

import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/file_operation.dart';
import 'package:yust_ui/src/util/offline/sync_queue.dart';

final _t1 = DateTime.utc(2026, 1, 1, 10, 0);
final _t2 = DateTime.utc(2026, 1, 1, 10, 1);

FileOperation<YustFile> _operation(
  FileOperationType type, {
  String hash = 'h1',
  String name = 'a.pdf',
  String? newName,
  DateTime? createdAt,
}) => FileOperation<YustFile>(
  type: type,
  file: YustFile(name: name, hash: hash, setCreatedAtToNow: false),
  newName: newName,
  createdAt: createdAt,
);

void main() {
  late Directory root;
  late SyncQueue queue;

  setUp(() {
    root = Directory.systemTemp.createTempSync('sync_queue_test');
    queue = SyncQueue(directoryProvider: () async => root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('enqueue then pending lists the operations, oldest first', () async {
    await queue.enqueue(
      _operation(FileOperationType.upload, hash: 'h1', createdAt: _t1),
    );
    await queue.enqueue(
      _operation(FileOperationType.delete, hash: 'h2', createdAt: _t2),
    );

    final operations = await queue.pending();
    expect(operations.map((operation) => operation.type), [
      FileOperationType.upload,
      FileOperationType.delete,
    ]);
  });

  test(
    'pending filters by type — each manager sees only its own operations',
    () async {
      await queue.enqueue(_operation(FileOperationType.upload, hash: 'h1'));
      await queue.enqueue(_operation(FileOperationType.download, hash: 'h2'));
      await queue.enqueue(_operation(FileOperationType.delete, hash: 'h3'));

      final outbound = await queue.pending(
        types: {
          FileOperationType.upload,
          FileOperationType.rename,
          FileOperationType.delete,
        },
      );
      expect(outbound.map((operation) => operation.fileKey), ['h1', 'h3']);

      final inbound = await queue.pending(types: {FileOperationType.download});
      expect(inbound.map((operation) => operation.fileKey), ['h2']);
    },
  );

  test('remove drops the operation by id, leaving the rest', () async {
    await queue.enqueue(_operation(FileOperationType.upload, hash: 'h1'));
    await queue.enqueue(_operation(FileOperationType.upload, hash: 'h2'));

    final operations = await queue.pending();
    await queue.remove(operations.first);
    expect((await queue.pending()).map((operation) => operation.fileKey), [
      'h2',
    ]);
  });

  test('remove is a no-op when the operation is already gone', () async {
    await queue.enqueue(_operation(FileOperationType.upload, hash: 'h1'));
    final operations = await queue.pending();
    await queue.remove(operations.first);
    await queue.remove(operations.first);
    expect(await queue.pending(), isEmpty);
  });

  test('the queue survives a restart (new instance, same directory)', () async {
    await queue.enqueue(
      _operation(
        FileOperationType.rename,
        name: 'a.pdf',
        newName: 'b.pdf',
        createdAt: _t1,
      ),
    );

    final reopened = SyncQueue(directoryProvider: () async => root);
    final operations = await reopened.pending();
    expect(operations.single.type, FileOperationType.rename);
    expect(operations.single.newName, 'b.pdf');
  });

  test('concurrent enqueues do not clobber each other (serialised)', () async {
    // Fire many enqueues without awaiting between them, so their load→save
    // cycles overlap. Without the mutex, later saves drop earlier operations.
    final futures = [
      for (var i = 0; i < 20; i++)
        queue.enqueue(
          _operation(FileOperationType.upload, hash: 'h$i', name: '$i.pdf'),
        ),
    ];
    await Future.wait(futures);

    final keys = (await queue.pending())
        .map((operation) => operation.fileKey)
        .toSet();
    expect(keys, {for (var i = 0; i < 20; i++) 'h$i'});
  });

  test('interleaved enqueue and remove keep the surviving operation', () async {
    await queue.enqueue(
      _operation(FileOperationType.upload, hash: 'h1', name: '1.pdf'),
    );
    final existing = (await queue.pending()).single;

    // Overlap a remove of the existing operation with an enqueue of a new one.
    await Future.wait([
      queue.remove(existing),
      queue.enqueue(
        _operation(FileOperationType.upload, hash: 'h2', name: '2.pdf'),
      ),
    ]);

    expect((await queue.pending()).map((operation) => operation.fileKey), [
      'h2',
    ]);
  });

  test('a queued image operation keeps its YustImage subtype', () async {
    await queue.enqueue(
      FileOperation<YustImage>(
        type: FileOperationType.upload,
        file: YustImage(name: 'photo.jpg', hash: 'img1')
          ..location = YustGeoLocation(latitude: 48.1, longitude: 11.5),
        createdAt: _t1,
      ),
    );

    final operations = await queue.pending();
    expect(operations.single.file, isA<YustImage>());
    expect((operations.single.file as YustImage).location?.latitude, 48.1);
  });

  group('replace', () {
    test('rewrites the operation in place, keeping its position', () async {
      await queue.enqueue(
        _operation(FileOperationType.upload, hash: 'h1', createdAt: _t1),
      );
      await queue.enqueue(
        _operation(FileOperationType.upload, hash: 'h2', createdAt: _t2),
      );
      final first = (await queue.pending()).first;

      await queue.replace(first.withFailedAttempt());

      final operations = await queue.pending();
      expect(operations.map((operation) => operation.fileKey), ['h1', 'h2']);
      expect(operations.first.failedAttempts, 1);
      expect(operations.first.id, first.id);
    });

    test('is a no-op when the operation is already gone', () async {
      await queue.enqueue(
        _operation(FileOperationType.upload, hash: 'h1', createdAt: _t1),
      );
      final only = (await queue.pending()).single;
      await queue.remove(only);

      await queue.replace(only.withFailedAttempt());

      expect(await queue.pending(), isEmpty);
    });
  });
}
