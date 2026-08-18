import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/file_operation.dart';

final _createdAt = DateTime.utc(2026, 7, 29, 10, 30);

YustFile _file({
  String name = 'plan.pdf',
  String hash = 'h1',
  String? devicePath = '/support/offline/h1/plan.pdf',
}) => YustFile(
  name: name,
  hash: hash,
  devicePath: devicePath,
  path: 'records/abc/files',
  storageFolderPath: 'records/abc/files',
  linkedDocPath: 'records/abc',
  linkedDocAttribute: 'brickValues.xyz',
  linkedDocStoresFilesAsMap: true,
  setCreatedAtToNow: false,
);

void main() {
  group('FileOperation.fileKey', () {
    test('separates two entries holding the same bytes', () {
      // Uploading the same image twice gives both entries the same content
      // hash; they are still two files and must not collapse into one.
      expect(
        _file(name: 'first.jpeg', hash: 'same').offlineKey,
        isNot(_file(name: 'second.jpeg', hash: 'same').offlineKey),
      );
    });

    test('is not the bare name for hashless (array-layout) files', () {
      // The bare name is not unique across records, so two pinned records each
      // holding a `Plan.pdf` would share one cache directory.
      final operation = FileOperation<YustFile>(
        type: FileOperationType.delete,
        file: _file(hash: '', name: 'legacy.pdf'),
      );
      expect(operation.fileKey, isNot('legacy.pdf'));
      expect(operation.fileKey, isNotEmpty);
    });

    test('separates same-named files in different folders', () {
      YustFile inFolder(String folder) => YustFile(
        name: 'Plan.pdf',
        hash: 'h1',
        storageFolderPath: folder,
        setCreatedAtToNow: false,
      );

      expect(
        inFolder('ws1/recordA/brick').offlineKey,
        isNot(inFolder('ws1/recordB/brick').offlineKey),
      );
    });

    test('byteKey follows the content, not the location', () {
      // Re-drawing a signature keeps its name and folder, so only the content
      // tells the new bytes from the cached old ones.
      final before = _file(name: 'signature.png', hash: 'old');
      final after = _file(name: 'signature.png', hash: 'new');

      expect(before.offlineKey, after.offlineKey);
      expect(before.byteKey, isNot(after.byteKey));
    });

    test('byteKey is shared by entries holding the same bytes', () {
      expect(
        _file(name: 'first.jpeg', hash: 'same').byteKey,
        _file(name: 'second.jpeg', hash: 'same').byteKey,
      );
    });

    test('byteKey falls back to the location for a hashless file', () {
      final hashless = _file(name: 'legacy.pdf', hash: '');
      expect(hashless.byteKey, hashless.offlineKey);
    });

    test('is stable for the same file', () {
      expect(
        _file(hash: '', name: 'legacy.pdf').offlineKey,
        _file(hash: '', name: 'legacy.pdf').offlineKey,
      );
    });

    test('stays frozen when the file is renamed after enqueueing', () {
      final file = _file(hash: '', name: 'old.pdf');
      final operation = FileOperation<YustFile>(
        type: FileOperationType.rename,
        file: file,
        newName: 'new.pdf',
      );
      final keyAtEnqueue = operation.fileKey;

      file.name = 'new.pdf';

      // The bytes were written under the original key; the operation must keep
      // finding them.
      expect(operation.fileKey, keyAtEnqueue);
      expect(operation.fileKey, isNot(file.offlineKey));
    });
  });

  test(
    'id round-trips so a queue can remove the operation after a restart',
    () {
      final operation = FileOperation<YustFile>(
        type: FileOperationType.download,
        file: _file(hash: 'h1'),
        createdAt: _createdAt,
      );

      final restored = FileOperation.fromJson<YustFile>(
        operation.toJson(),
        YustFile.fromJson,
      );

      expect(restored.id, operation.id);
      expect(restored.type, FileOperationType.download);
    },
  );

  group('toJson / fromJson', () {
    test('round-trips an upload operation, addressing included', () {
      final operation = FileOperation<YustFile>(
        type: FileOperationType.upload,
        file: _file(name: 'plan.pdf', hash: 'h1'),
        createdAt: _createdAt,
      );

      final restored = FileOperation.fromJson<YustFile>(
        operation.toJson(),
        YustFile.fromJson,
      );

      expect(restored.type, FileOperationType.upload);
      expect(restored.file.name, 'plan.pdf');
      expect(restored.fileKey, _file(name: 'plan.pdf', hash: 'h1').offlineKey);
      expect(restored.file.devicePath, '/support/offline/h1/plan.pdf');
      expect(restored.createdAt, _createdAt);
      // The file's transient addressing survives so a queued operation can still
      // upload + write after an app restart.
      expect(restored.file.storageFolderPath, 'records/abc/files');
      expect(restored.file.linkedDocPath, 'records/abc');
      expect(restored.file.linkedDocAttribute, 'brickValues.xyz');
      expect(restored.file.linkedDocStoresFilesAsMap, isTrue);
    });

    test(
      'rename operation keeps the current name on the file and the new name apart',
      () {
        final operation = FileOperation<YustFile>(
          type: FileOperationType.rename,
          file: _file(name: 'original.pdf', hash: 'h1'),
          newName: 'renamed.pdf',
          createdAt: _createdAt,
        );

        final restored = FileOperation.fromJson<YustFile>(
          operation.toJson(),
          YustFile.fromJson,
        );

        expect(restored.type, FileOperationType.rename);
        expect(restored.file.name, 'original.pdf');
        expect(restored.newName, 'renamed.pdf');
      },
    );

    test(
      'delete operation with no local bytes serialises without throwing',
      () {
        final operation = FileOperation<YustFile>(
          type: FileOperationType.delete,
          file: _file(hash: 'h1', devicePath: null),
          createdAt: _createdAt,
        );

        final restored = FileOperation.fromJson<YustFile>(
          operation.toJson(),
          YustFile.fromJson,
        );

        expect(restored.type, FileOperationType.delete);
        expect(restored.file.devicePath, isNull);
      },
    );

    test(
      'round-trips an image operation preserving its subtype and location',
      () {
        final image = YustImage.fromYustFile(_file(hash: 'img1'))
          ..location = YustGeoLocation(latitude: 48.1, longitude: 11.5);
        final operation = FileOperation<YustImage>(
          type: FileOperationType.upload,
          file: image,
          createdAt: _createdAt,
        );

        final json = operation.toJson();
        expect(json['fileType'], YustImage.type);

        final restored = FileOperation.fromJson<YustImage>(
          json,
          YustImage.fromJson,
        );

        expect(restored.file, isA<YustImage>());
        expect(restored.file.location?.latitude, 48.1);
      },
    );
  });
}
