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
    test('is the identifier when present', () {
      final op = FileOperation<YustFile>(
        type: FileOperationType.upload,
        file: _file(hash: 'abc123'),
      );
      expect(op.fileKey, 'abc123');
    });

    test('falls back to the name for hashless (array-layout) files', () {
      final op = FileOperation<YustFile>(
        type: FileOperationType.delete,
        file: _file(hash: '', name: 'legacy.pdf'),
      );
      expect(op.fileKey, 'legacy.pdf');
    });
  });

  test('databaseIdentifier defaults to the file hash', () {
    final op = FileOperation<YustFile>(
      type: FileOperationType.upload,
      file: _file(hash: 'h9'),
    );
    expect(op.databaseIdentifier, 'h9');
  });

  test('id round-trips so a queue can remove the op after a restart', () {
    final op = FileOperation<YustFile>(
      type: FileOperationType.download,
      file: _file(hash: 'h1'),
      createdAt: _createdAt,
    );

    final restored = FileOperation.fromJson<YustFile>(
      op.toJson(),
      YustFile.fromJson,
    );

    expect(restored.id, op.id);
    expect(restored.type, FileOperationType.download);
  });

  group('toJson / fromJson', () {
    test('round-trips an upload op, addressing included', () {
      final op = FileOperation<YustFile>(
        type: FileOperationType.upload,
        file: _file(name: 'plan.pdf', hash: 'h1'),
        createdAt: _createdAt,
      );

      final restored = FileOperation.fromJson<YustFile>(
        op.toJson(),
        YustFile.fromJson,
      );

      expect(restored.type, FileOperationType.upload);
      expect(restored.file.name, 'plan.pdf');
      expect(restored.databaseIdentifier, 'h1');
      expect(restored.file.devicePath, '/support/offline/h1/plan.pdf');
      expect(restored.createdAt, _createdAt);
      // The file's transient addressing survives so a queued op can still
      // upload + write after an app restart.
      expect(restored.file.storageFolderPath, 'records/abc/files');
      expect(restored.file.linkedDocPath, 'records/abc');
      expect(restored.file.linkedDocAttribute, 'brickValues.xyz');
      expect(restored.file.linkedDocStoresFilesAsMap, isTrue);
    });

    test(
      'rename op keeps the current name on the file and the new name apart',
      () {
        final op = FileOperation<YustFile>(
          type: FileOperationType.rename,
          file: _file(name: 'original.pdf', hash: 'h1'),
          newName: 'renamed.pdf',
          createdAt: _createdAt,
        );

        final restored = FileOperation.fromJson<YustFile>(
          op.toJson(),
          YustFile.fromJson,
        );

        expect(restored.type, FileOperationType.rename);
        expect(restored.file.name, 'original.pdf');
        expect(restored.newName, 'renamed.pdf');
      },
    );

    test('delete op with no local bytes serialises without throwing', () {
      final op = FileOperation<YustFile>(
        type: FileOperationType.delete,
        file: _file(hash: 'h1', devicePath: null),
        createdAt: _createdAt,
      );

      final restored = FileOperation.fromJson<YustFile>(
        op.toJson(),
        YustFile.fromJson,
      );

      expect(restored.type, FileOperationType.delete);
      expect(restored.file.devicePath, isNull);
    });

    test('round-trips an image op preserving its subtype and location', () {
      final image = YustImage.fromYustFile(_file(hash: 'img1'))
        ..location = YustGeoLocation(latitude: 48.1, longitude: 11.5);
      final op = FileOperation<YustImage>(
        type: FileOperationType.upload,
        file: image,
        createdAt: _createdAt,
      );

      final json = op.toJson();
      expect(json['fileType'], YustImage.type);

      final restored = FileOperation.fromJson<YustImage>(
        json,
        YustImage.fromJson,
      );

      expect(restored.file, isA<YustImage>());
      expect(restored.file.location?.latitude, 48.1);
    });
  });
}
