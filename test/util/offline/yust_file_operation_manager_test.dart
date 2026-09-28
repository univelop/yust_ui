import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yust/src/services/yust_file_service.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation_manager.dart';
import 'package:yust_ui/src/util/offline/yust_offline_storage.dart';

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

/// The Storage objects a test cares about, as names under one folder.
///
/// Hand-rolled because `YustFileServiceMocked`'s constructor throws in a
/// Flutter environment. Only the members a rename reaches are implemented.
class _FakeFileService implements YustFileService {
  final Set<String> objectNames = {};

  @override
  Future<String> uploadFile({
    required String path,
    required String name,
    File? file,
    Uint8List? bytes,
    Map<String, String>? metadata,
    String? contentDisposition,
    String? bucketName,
    bool? createThumbnail,
    String? linkedDocPath,
    String? linkedDocAttribute,
  }) async {
    objectNames.add(name);
    return 'https://storage.test/$path/$name';
  }

  @override
  Future<void> deleteFile({
    required String path,
    String? name,
    String? bucketName,
  }) async {
    objectNames.remove(name);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

/// Lets an unawaited execute reach its next suspension point.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('a rename interrupted after its document write', () {
    late Directory root;
    late YustOfflineStorage storage;
    late _FakeFileService fileService;

    const folder = 'records/rec-rename';

    setUp(() async {
      root = Directory.systemTemp.createTempSync('rename_retry_test');
      storage = YustOfflineStorage(directoryProvider: () async => root);
      fileService = _FakeFileService();
      Yust.fileService = fileService;
      final bytes = Uint8List.fromList('pdf-bytes'.codeUnits);
      await fileService.uploadFile(path: folder, name: 'old.pdf', bytes: bytes);
      // The cached copy is what the rename re-uploads from, so no download runs.
      await storage.writeBytes(byteKey: 'h1', name: 'old.pdf', bytes: bytes);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('the retry deletes the old object, never the renamed one', () async {
      // An executor that renamed `operation.file` in place would read the new
      // name as the old one on the retry, deleting the object it just wrote.
      final writer = _RenameRecordingWriter(writeFailures: 1);
      final manager = YustFileOperationManager(
        documentWriterFor: (_) => writer,
        storage: storage,
      );
      final operation = _renameOp();

      await expectLater(manager.execute(operation), throwsA(isA<Exception>()));
      expect(writer.writes, ['new.pdf'], reason: 'the new entry is attempted');

      await manager.execute(operation);

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
      final manager = YustFileOperationManager(
        documentWriterFor: (_) => _RenameRecordingWriter(writeFailures: 1),
        storage: storage,
      );
      final operation = _renameOp();

      await expectLater(manager.execute(operation), throwsA(isA<Exception>()));

      expect(operation.file.name, 'old.pdf');
      expect(operation.newName, 'new.pdf');
    });
  });

  group('unaddressable files', () {
    test(
      'a metadata operation with no document writer applies instead of throwing',
      () {
        // A picker bound to a brick's settings rather than to a record has no
        // document to write back to. Before the document writer could be null the app
        // built one from an empty path, which threw on every attempt and kept the
        // operation queued forever.
        final manager = YustFileOperationManager(
          documentWriterFor: (operation) => null,
        );

        expect(manager.execute(_metadataOp()), completes);
      },
    );
  });

  group('an upload that supersedes an entry', () {
    late Directory root;
    late YustOfflineStorage storage;
    late _FakeFileService fileService;
    late _RenameRecordingWriter writer;
    late YustFileOperationManager manager;

    setUp(() {
      root = Directory.systemTemp.createTempSync('superseded_entry_test');
      storage = YustOfflineStorage(directoryProvider: () async => root);
      fileService = _FakeFileService();
      Yust.fileService = fileService;
      writer = _RenameRecordingWriter();
      manager = YustFileOperationManager(
        documentWriterFor: (_) => writer,
        storage: storage,
      );
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('writes the new entry, then drops the superseded one', () async {
      // One operation, so no snapshot falls between the two writes and shows
      // the file under both keys — which is what a follow-up operation exposed.
      await manager.execute(_replacingUploadOp());

      expect(writer.writes, ['drawing.png']);
      expect(writer.removedHashes, ['h1']);
    });

    test('leaves the Storage object, which now holds the new bytes', () async {
      // The object under this name holds the replacing file's bytes now, so
      // deleting it — as a delete would — would lose the file just uploaded.
      await manager.execute(_replacingUploadOp());

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

      await manager.execute(operation);

      expect(writer.removals, isEmpty);
    });
  });

  test('a delete waits for the record entry to be removed', () async {
    // The array layout rewrites the whole attribute from a read of the record,
    // so an operation running while the removal is still in flight reads the
    // deleted file back in — and it then points at bytes that are gone.
    final steps = <String>[];
    final entryRemoved = Completer<void>();
    final manager = YustFileOperationManager(
      documentWriterFor: (_) => _RecordingWriter(steps, entryRemoved),
    );

    // No file service is configured here, so the byte delete that follows the
    // removal fails at once — which is what makes "the operation got past the
    // removal" observable.
    var settled = false;
    unawaited(
      manager
          .execute(_deleteOp())
          .then<void>((_) => settled = true)
          .catchError((Object _) => settled = true),
    );

    await _settle();
    expect(steps, ['removal started']);
    expect(settled, isFalse, reason: 'the delete must wait for the removal');

    entryRemoved.complete();
    await _settle();
    expect(steps, ['removal started', 'removal done']);
    expect(settled, isTrue);
  });
}
