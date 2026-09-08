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
  Future<void> removeFile(YustFile file) async => removals.add(file.name!);
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
  _RecordingWriter(this.steps, this.detached);

  final List<String> steps;
  final Completer<void> detached;

  @override
  Future<void> writeFile(YustFile file) async => steps.add('write');

  @override
  Future<void> removeFile(YustFile file) async {
    steps.add('detach started');
    await detached.future;
    steps.add('detach done');
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
        reason: 'the entry keeps its hash key, so there is nothing to detach',
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

  test('a delete waits for the record entry to be detached', () async {
    // The array layout rewrites the whole attribute from a read of the record,
    // so an operation running while the detach is still in flight reads the
    // deleted file back in — and it then points at bytes that are gone.
    final steps = <String>[];
    final detached = Completer<void>();
    final manager = YustFileOperationManager(
      documentWriterFor: (_) => _RecordingWriter(steps, detached),
    );

    // No file service is configured here, so the byte delete that follows the
    // detach fails at once — which is what makes "the operation got past the
    // detach" observable.
    var settled = false;
    unawaited(
      manager
          .execute(_deleteOp())
          .then<void>((_) => settled = true)
          .catchError((Object _) => settled = true),
    );

    await _settle();
    expect(steps, ['detach started']);
    expect(settled, isFalse, reason: 'the delete must wait for the detach');

    detached.complete();
    await _settle();
    expect(steps, ['detach started', 'detach done']);
    expect(settled, isTrue);
  });
}
