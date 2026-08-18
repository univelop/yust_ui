import 'dart:async';

import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/file_operation.dart';
import 'package:yust_ui/src/util/offline/upload_manager.dart';

FileOperation<YustFile> _metadataOp() => FileOperation<YustFile>(
  type: FileOperationType.updateMetadata,
  file: YustFile(name: 'logo.png', hash: 'h1', setCreatedAtToNow: false),
);

FileOperation<YustFile> _deleteOp() => FileOperation<YustFile>(
  type: FileOperationType.delete,
  file: YustFile(
    name: 'plan.pdf',
    hash: 'h1',
    storageFolderPath: 'records/rec1',
    setCreatedAtToNow: false,
  ),
);

/// Records the order of the steps a delete runs, and holds the record write
/// open until the test releases it.
class _RecordingWriter implements OfflineFileDocumentWriter {
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
  group('unaddressable files', () {
    test(
      'a metadata operation with no document writer applies instead of throwing',
      () {
        // A picker bound to a brick's settings rather than to a record has no
        // document to write back to. Before the document writer could be null the app
        // built one from an empty path, which threw on every attempt and kept the
        // operation queued forever.
        final manager = UploadManager(documentWriterFor: (operation) => null);

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
    final manager = UploadManager(
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
