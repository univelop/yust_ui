import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation_manager.dart';
import 'package:yust_ui/src/util/offline/yust_offline_storage.dart';
import 'package:yust_ui/src/util/offline/yust_sync_queue.dart';

import 'fake_file_service.dart';

YustFileOperation<YustFile> _metadataOp() => YustFileOperation<YustFile>(
  type: YustFileOperationType.updateMetadata,
  file: YustFile(
    name: 'logo.png',
    hash: 'h1',
    storageFolderPath: 'records/rec1',
    setCreatedAtToNow: false,
  ),
);

YustFileOperation<YustFile> _deleteOp() => YustFileOperation<YustFile>(
  type: YustFileOperationType.delete,
  file: YustFile(
    name: 'plan.pdf',
    hash: 'h1',
    storageFolderPath: 'records/rec1',
    setCreatedAtToNow: false,
  ),
);

YustFileOperation<YustFile> _replacingUploadOp() => YustFileOperation<YustFile>(
  type: YustFileOperationType.upload,
  file: YustFile(
    name: 'drawing.png',
    hash: 'h-redrawn',
    bytes: Uint8List.fromList('redrawn'.codeUnits),
    storageFolderPath: 'records/rec1',
    setCreatedAtToNow: false,
  ),
  supersededHash: 'h1',
);

YustFileOperation<YustFile> _renameOp() => YustFileOperation<YustFile>(
  type: YustFileOperationType.rename,
  file: YustFile(
    name: 'old.pdf',
    hash: 'h1',
    storageFolderPath: 'records/rec-rename',
    setCreatedAtToNow: false,
  ),
  newName: 'new.pdf',
);

YustFileOperation<YustFile> _downloadOp() => YustFileOperation<YustFile>(
  type: YustFileOperationType.download,
  file: YustFile(
    name: 'plan.pdf',
    hash: 'h-download',
    storageFolderPath: 'records/rec1',
    setCreatedAtToNow: false,
  ),
);

const _offline = SocketException('no route to host');

/// Records the name each document write was asked for, failing the first
/// [writeFailures] of them so a rename can be interrupted mid-way.
class _RenameRecordingWriter implements YustOfflineFileDocumentWriter {
  _RenameRecordingWriter({this.writeFailures = 0});

  final List<String> writes = [];
  final List<String> removals = [];
  final List<String> removedHashes = [];
  int writeFailures;

  @override
  Future<void> writeFile(YustFile file) async {
    writes.add(file.name!);
    if (writeFailures > 0) {
      writeFailures--;
      throw YustException('Record write rejected');
    }
  }

  @override
  Future<void> removeFile(YustFile file) async {
    removals.add(file.name!);
    removedHashes.add(file.hash);
  }
}

/// Records the order of the steps a delete runs, and holds the record write
/// open until the test releases it.
class _RecordingWriter implements YustOfflineFileDocumentWriter {
  _RecordingWriter(this.steps, this.entryRemoved);

  final List<String> steps;
  final Completer<void> entryRemoved;

  @override
  Future<void> writeFile(YustFile file) async => steps.add('write');

  @override
  Future<void> removeFile(YustFile file) async {
    steps.add('removal started');
    await entryRemoved.future;
    steps.add('removal done');
  }
}

/// Lets an unawaited drain reach its next suspension point.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late YustSyncQueue queue;
  late FakeFileService fileService;

  setUp(() {
    queue = YustSyncQueue.inMemory();
    fileService = FakeFileService();
    Yust.fileService = fileService;
  });

  /// A manager whose retry never fires, so a failed operation stays queued for
  /// the rest of the test.
  YustFileOperationManager buildManager({
    required YustOfflineFileDocumentWriter? Function(
      YustFileOperation<YustFile>,
    )
    documentWriterFor,
    YustOfflineStorage? storage,
  }) {
    final manager = YustFileOperationManager(
      queue: queue,
      documentWriterFor: documentWriterFor,
      storage: storage,
      connectivityStream: const Stream<bool>.empty(),
      delay: (_) => Completer<void>().future,
    );
    addTearDown(manager.dispose);
    return manager;
  }

  group('a rename interrupted after its document write', () {
    late Directory root;
    late YustOfflineStorage storage;

    const folder = 'records/rec-rename';

    setUp(() async {
      root = Directory.systemTemp.createTempSync('rename_retry_test');
      storage = YustOfflineStorage(directoryProvider: () async => root);
      final bytes = Uint8List.fromList('pdf-bytes'.codeUnits);
      await fileService.uploadFile(path: folder, name: 'old.pdf', bytes: bytes);
      // The cached copy is what the rename re-uploads from, so no copy runs.
      await storage.writeBytes(byteKey: 'h1', name: 'old.pdf', bytes: bytes);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('the retry deletes the old object, never the renamed one', () async {
      // A manager that renamed `operation.file` in place would read the new
      // name as the old one on the retry, deleting the object it just wrote.
      final writer = _RenameRecordingWriter(writeFailures: 1);
      final manager = buildManager(
        documentWriterFor: (_) => writer,
        storage: storage,
      );

      await queue.enqueueOperation(_renameOp());
      await manager.processPendingOperations();
      expect(writer.writes, ['new.pdf'], reason: 'the new entry is attempted');
      expect(await queue.getPendingOperations(), hasLength(1));

      await manager.processPendingOperations();

      expect(writer.writes, ['new.pdf', 'new.pdf']);
      expect(
        writer.removals,
        isEmpty,
        reason: 'the entry keeps its hash key, so it replaces itself',
      );
      expect(
        fileService.objectNames,
        {'new.pdf'},
        reason:
            'the renamed object survives the retry, the old one is cleaned up',
      );
    });

    test('the queued operation keeps its original name', () async {
      final manager = buildManager(
        documentWriterFor: (_) => _RenameRecordingWriter(writeFailures: 1),
        storage: storage,
      );

      await queue.enqueueOperation(_renameOp());
      await manager.processPendingOperations();

      final queued = (await queue.getPendingOperations()).single;
      expect(queued.file.name, 'old.pdf');
      expect(queued.newName, 'new.pdf');
    });

    test('uploads the device copy instead of copying in Storage', () async {
      final manager = buildManager(
        documentWriterFor: (_) => null,
        storage: storage,
      );

      await queue.enqueueOperation(_renameOp());
      await manager.processPendingOperations();

      expect(
        fileService.steps.map((step) => step.kind),
        isNot(contains(FakeFileStepKind.copy)),
      );
      expect(fileService.objectNames, {'new.pdf'});
    });
  });

  test('a rename without a device copy copies in Storage', () async {
    final root = Directory.systemTemp.createTempSync('rename_copy_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final manager = buildManager(
      documentWriterFor: (_) => null,
      storage: YustOfflineStorage(directoryProvider: () async => root),
    );
    await fileService.uploadFile(
      path: 'records/rec-rename',
      name: 'old.pdf',
      bytes: Uint8List.fromList('pdf-bytes'.codeUnits),
    );

    await queue.enqueueOperation(_renameOp());
    await manager.processPendingOperations();

    expect(
      fileService.steps.map((step) => step.kind),
      contains(FakeFileStepKind.copy),
    );
    expect(fileService.objectNames, {'new.pdf'});
    expect(await queue.getPendingOperations(), isEmpty);
  });

  group('unaddressable files', () {
    test(
      'a metadata operation with no document writer applies instead of throwing',
      () async {
        // A picker bound to a brick's settings rather than to a record has no
        // document to write back to. Before the document writer could be null
        // the app built one from an empty path, which threw on every attempt
        // and kept the operation queued forever.
        final manager = buildManager(documentWriterFor: (operation) => null);

        await queue.enqueueOperation(_metadataOp());
        await manager.processPendingOperations();

        expect(await queue.getPendingOperations(), isEmpty);
      },
    );
  });

  group('an upload that supersedes an entry', () {
    late Directory root;
    late _RenameRecordingWriter writer;
    late YustFileOperationManager manager;

    setUp(() {
      root = Directory.systemTemp.createTempSync('superseded_entry_test');
      writer = _RenameRecordingWriter();
      manager = buildManager(
        documentWriterFor: (_) => writer,
        storage: YustOfflineStorage(directoryProvider: () async => root),
      );
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('writes the new entry, then drops the superseded one', () async {
      // One operation, so no snapshot falls between the two writes and shows
      // the file under both keys — which is what a follow-up operation exposed.
      await queue.enqueueOperation(_replacingUploadOp());
      await manager.processPendingOperations();

      expect(writer.writes, ['drawing.png']);
      expect(writer.removedHashes, ['h1']);
    });

    test('leaves the Storage object, which now holds the new bytes', () async {
      // The object under this name holds the replacing file's bytes now, so
      // deleting it — as a delete would — would lose the file just uploaded.
      await queue.enqueueOperation(_replacingUploadOp());
      await manager.processPendingOperations();

      expect(fileService.objectNames, contains('drawing.png'));
    });

    test('drops nothing when the bytes landed on the same key', () async {
      // Re-saving unchanged bytes supersedes the entry with itself; removing
      // it would drop the entry the upload just wrote.
      final operation = YustFileOperation<YustFile>(
        type: YustFileOperationType.upload,
        file: YustFile(
          name: 'drawing.png',
          hash: 'h1',
          bytes: Uint8List.fromList('unchanged'.codeUnits),
          storageFolderPath: 'records/rec1',
          setCreatedAtToNow: false,
        ),
        supersededHash: 'h1',
      );

      await queue.enqueueOperation(operation);
      await manager.processPendingOperations();

      expect(writer.removals, isEmpty);
    });
  });

  test('a delete waits for the record entry to be removed', () async {
    // The array layout rewrites the whole attribute from a read of the record,
    // so an operation running while the removal is still in flight reads the
    // deleted file back in — and it then points at bytes that are gone.
    final steps = <String>[];
    final entryRemoved = Completer<void>();
    final manager = buildManager(
      documentWriterFor: (_) => _RecordingWriter(steps, entryRemoved),
    );
    fileService.onStep = (step) async {
      if (step.kind == FakeFileStepKind.delete) steps.add('object deleted');
    };

    await queue.enqueueOperation(_deleteOp());
    var settled = false;
    unawaited(
      manager.processPendingOperations().then<void>((_) => settled = true),
    );

    await _settle();
    expect(steps, ['removal started']);
    expect(settled, isFalse, reason: 'the delete must wait for the removal');

    entryRemoved.complete();
    await _settle();
    expect(steps, ['removal started', 'removal done', 'object deleted']);
    expect(settled, isTrue);
  });

  group('a download', () {
    late Directory root;
    late YustFileOperationManager manager;

    setUp(() {
      root = Directory.systemTemp.createTempSync('download_test');
      manager = buildManager(
        documentWriterFor: (_) => null,
        storage: YustOfflineStorage(directoryProvider: () async => root),
      );
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('of a missing object is dropped as permanent', () async {
      fileService.onStep = (_) async =>
          throw YustNotFoundException('The file does not exist.');

      await queue.enqueueOperation(_downloadOp());
      await manager.processPendingOperations();

      expect(await queue.getPendingOperations(), isEmpty);
    });

    test('while Storage is unreachable stays queued', () async {
      fileService.onStep = (_) async => throw _offline;

      await queue.enqueueOperation(_downloadOp());
      await manager.processPendingOperations();

      final queued = (await queue.getPendingOperations()).single;
      expect(queued.failure, isNull);
    });
  });
}
