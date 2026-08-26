import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation.dart';
import 'package:yust_ui/src/util/offline/yust_offline_storage.dart';
import 'package:yust_ui/src/util/yust_file_helpers.dart';

YustFile _plan() => YustFile(
  name: 'Plan.pdf',
  hash: '',
  path: 'ws1/rec1/brick1',
  storageFolderPath: 'ws1/rec1/brick1',
  // ignore: deprecated_member_use
  url: 'https://cdn.test/Plan.pdf',
  setCreatedAtToNow: false,
);

void main() {
  late Directory root;
  late YustOfflineStorage storage;
  late YustFileHelpers helpers;

  setUp(() {
    // getOriginalUrl reads Yust.fileAccessService, which is `late` — without
    // this the url fallback throws instead of returning a url.
    Yust.fileAccessService = YustFileAccessServiceMocked(
      originalCdnBaseUrl: null,
      thumbnailCdnBaseUrl: null,
    );
    root = Directory.systemTemp.createTempSync('file_source_test');
    storage = YustOfflineStorage(directoryProvider: () async => root);
    helpers = YustFileHelpers(offlineStorage: storage);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('getSourceUri', () {
    test('falls back to the network url when nothing is cached', () async {
      final uri = await helpers.getSourceUri(_plan());

      expect(uri?.scheme, 'https');
    });

    test('prefers the on-device copy once it is cached', () async {
      final plan = _plan();
      await storage.writeBytes(
        byteKey: plan.offlineKey,
        name: plan.name!,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      final uri = await helpers.getSourceUri(plan);

      expect(uri?.scheme, 'file');
      expect(File(uri!.toFilePath()).existsSync(), isTrue);
    });

    test('is null when the file is neither cached nor addressable', () async {
      final uri = await helpers.getSourceUri(
        YustFile(name: 'Gone.pdf', setCreatedAtToNow: false),
      );

      expect(uri, isNull);
    });
  });

  group('resolveToLocalFile', () {
    test('returns the on-device copy when the file is cached', () async {
      final plan = _plan();
      final devicePath = await storage.writeBytes(
        byteKey: plan.offlineKey,
        name: plan.name!,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      final file = await helpers.resolveToLocalFile(plan);

      expect(file.existsSync(), isTrue);
      expect(file.path, devicePath);
    });

    test(
      'returns the durable copy without a storage lookup when devicePath is set',
      () async {
        // A picked file not yet uploaded: its only copy is the durable
        // devicePath, which is not addressable through the byte store.
        final durable = File('${root.path}/durable.pdf')
          ..writeAsBytesSync([1, 2, 3]);
        final plan = _plan()..devicePath = durable.path;
        expect(plan.cached, isTrue);

        final file = await helpers.resolveToLocalFile(plan);

        expect(file.path, durable.path);
      },
    );

    test('throws when the file is neither cached nor addressable', () async {
      final gone = YustFile(name: 'Gone.pdf', setCreatedAtToNow: false);

      expect(
        () => helpers.resolveToLocalFile(gone),
        throwsA(isA<YustException>()),
      );
    });
  });
}
