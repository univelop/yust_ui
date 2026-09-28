import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation.dart';

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
  setCreatedAtToNow: false,
);

void main() {
  group('YustFileOperation.fileKey', () {
    test('separates two entries holding the same bytes', () {
      // Uploading the same image twice gives both entries the same content
      // hash; they are still two files and must not collapse into one.
      expect(
        _file(name: 'first.jpeg', hash: 'same').offlineKey,
        isNot(_file(name: 'second.jpeg', hash: 'same').offlineKey),
      );
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

    test('is stable for the same file', () {
      expect(
        _file(name: 'plan.pdf', hash: 'h1').offlineKey,
        _file(name: 'plan.pdf', hash: 'h1').offlineKey,
      );
    });

    test('stays frozen when the file is renamed after enqueueing', () {
      final file = _file(name: 'old.pdf', hash: 'h1');
      final operation = YustFileOperation<YustFile>(
        type: YustFileOperationType.rename,
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
      final operation = YustFileOperation<YustFile>(
        type: YustFileOperationType.download,
        file: _file(hash: 'h1'),
        createdAt: _createdAt,
      );

      final restored = YustFileOperation.fromJson<YustFile>(operation.toJson());

      expect(restored.id, operation.id);
      expect(restored.type, YustFileOperationType.download);
    },
  );

  group('toJson / fromJson', () {
    test('round-trips an upload operation, addressing included', () {
      final operation = YustFileOperation<YustFile>(
        type: YustFileOperationType.upload,
        file: _file(name: 'plan.pdf', hash: 'h1'),
        createdAt: _createdAt,
      );

      final restored = YustFileOperation.fromJson<YustFile>(operation.toJson());

      expect(restored.type, YustFileOperationType.upload);
      expect(restored.file.name, 'plan.pdf');
      expect(restored.fileKey, _file(name: 'plan.pdf', hash: 'h1').offlineKey);
      expect(restored.file.devicePath, '/support/offline/h1/plan.pdf');
      expect(restored.createdAt, _createdAt);
      // The file's transient addressing survives so a queued operation can still
      // upload + write after an app restart.
      expect(restored.file.storageFolderPath, 'records/abc/files');
      expect(restored.file.linkedDocPath, 'records/abc');
      expect(restored.file.linkedDocAttribute, 'brickValues.xyz');
    });

    test(
      'rename operation keeps the current name on the file and the new name apart',
      () {
        final operation = YustFileOperation<YustFile>(
          type: YustFileOperationType.rename,
          file: _file(name: 'original.pdf', hash: 'h1'),
          newName: 'renamed.pdf',
          createdAt: _createdAt,
        );

        final restored = YustFileOperation.fromJson<YustFile>(
          operation.toJson(),
        );

        expect(restored.type, YustFileOperationType.rename);
        expect(restored.file.name, 'original.pdf');
        expect(restored.newName, 'renamed.pdf');
      },
    );

    test(
      'delete operation with no local bytes serialises without throwing',
      () {
        final operation = YustFileOperation<YustFile>(
          type: YustFileOperationType.delete,
          file: _file(hash: 'h1', devicePath: null),
          createdAt: _createdAt,
        );

        final restored = YustFileOperation.fromJson<YustFile>(
          operation.toJson(),
        );

        expect(restored.type, YustFileOperationType.delete);
        expect(restored.file.devicePath, isNull);
      },
    );

    test('round-trips createThumbnail, which the record write reads', () {
      // Regression: the old sidecar omitted this field.
      final file = _file(hash: 'h1')..createThumbnail = true;
      final operation = YustFileOperation<YustFile>(
        type: YustFileOperationType.upload,
        file: file,
        createdAt: _createdAt,
      );

      final restored = YustFileOperation.fromJson<YustFile>(operation.toJson());

      expect(restored.file.createThumbnail, isTrue);
    });

    test('round-trips the hash, which keys both the bytes and the entry', () {
      final operation = YustFileOperation<YustFile>(
        type: YustFileOperationType.upload,
        file: _file(hash: 'content-hash'),
        createdAt: _createdAt,
      );

      final restored = YustFileOperation.fromJson<YustFile>(operation.toJson());

      expect(restored.file.hash, 'content-hash');
      expect(restored.file.byteKey, 'content-hash');
    });

    test('round-trips a download for a file addressed only by path', () {
      // The shape SyncManager queues for a file uploaded elsewhere.
      final operation = YustFileOperation<YustFile>(
        type: YustFileOperationType.download,
        file: YustFile(
          name: 'plan.pdf',
          hash: 'h1',
          path: 'records/abc/files',
          setCreatedAtToNow: false,
        ),
        createdAt: _createdAt,
      );

      final restored = YustFileOperation.fromJson<YustFile>(operation.toJson());

      expect(restored.file.path, 'records/abc/files');
      expect(restored.file.storageFolderPath, isNull);
      expect(restored.file.devicePath, isNull);
      expect(restored.file.hasStorageLocation, isTrue);
    });

    test('round-trips an unlinked file, which has no document behind it', () {
      final operation = YustFileOperation<YustFile>(
        type: YustFileOperationType.upload,
        file: YustFile(
          name: 'logo.png',
          hash: 'h1',
          storageFolderPath: 'workspaces/w1/settings',
          setCreatedAtToNow: false,
        ),
        createdAt: _createdAt,
      );

      final restored = YustFileOperation.fromJson<YustFile>(operation.toJson());

      expect(restored.file.storageFolderPath, 'workspaces/w1/settings');
      expect(restored.file.linkedDocPath, isNull);
      expect(restored.file.linkedDocAttribute, isNull);
    });

    test(
      'round-trips an image operation preserving its subtype and location',
      () {
        final image = YustImage.fromYustFile(_file(hash: 'img1'))
          ..location = YustGeoLocation(latitude: 48.1, longitude: 11.5);
        final operation = YustFileOperation<YustImage>(
          type: YustFileOperationType.upload,
          file: image,
          createdAt: _createdAt,
        );

        final json = operation.toJson();
        // The subtype rides the file's own `type`, not a second key.
        expect(json['fileType'], isNull);
        expect((json['file'] as Map)['type'], YustImage.type);

        final restored = YustFileOperation.fromJson<YustImage>(json);

        expect(restored.file, isA<YustImage>());
        expect(restored.file.location?.latitude, 48.1);
      },
    );
  });
}
