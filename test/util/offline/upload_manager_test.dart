import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/file_operation.dart';
import 'package:yust_ui/src/util/offline/upload_manager.dart';

FileOperation<YustFile> _metadataOp() => FileOperation<YustFile>(
  type: FileOperationType.updateMetadata,
  file: YustFile(name: 'logo.png', hash: 'h1', setCreatedAtToNow: false),
);

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
}
