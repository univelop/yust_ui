import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/file_operation.dart';
import 'package:yust_ui/src/util/offline/offline_storage.dart';

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
  late OfflineStorage storage;

  setUp(() {
    // getOriginalUrl reads Yust.fileAccessService, which is `late` — without
    // this the url fallback throws instead of returning a url.
    Yust.fileAccessService = YustFileAccessServiceMocked(
      originalCdnBaseUrl: null,
      thumbnailCdnBaseUrl: null,
    );
    root = Directory.systemTemp.createTempSync('resolve_uri_test');
    storage = OfflineStorage(directoryProvider: () async => root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('falls back to the network url when nothing is cached', () async {
    final uri = await storage.resolveUri(_plan());

    expect(uri?.scheme, 'https');
  });

  test('prefers the on-device copy once it is cached', () async {
    final plan = _plan();
    await storage.write(
      hash: plan.offlineKey,
      name: plan.name!,
      bytes: Uint8List.fromList([1, 2, 3]),
    );

    final uri = await storage.resolveUri(plan);

    expect(uri?.scheme, 'file');
    expect(File(uri!.toFilePath()).existsSync(), isTrue);
  });

  group('bytes cached under the pre-migration key', () {
    /// Writes [plan]'s bytes the way an earlier build did: keyed by bare name.
    Future<void> cacheUnderLegacyKey(YustFile plan) => storage.write(
      hash: plan.legacyOfflineKey,
      name: plan.name!,
      bytes: Uint8List.fromList([9]),
    );

    test('still resolve to the on-device copy', () async {
      // The regression this guards: hashless files (every drawing-annotation
      // plan) were cached under the bare name. A lookup that only tried the new
      // key missed them, silently falling back to the network.
      final plan = _plan();
      await cacheUnderLegacyKey(plan);

      final uri = await storage.resolveUri(plan);

      expect(uri?.scheme, 'file');
      expect(File(uri!.toFilePath()).existsSync(), isTrue);
    });

    test('are reported as present', () async {
      final plan = _plan();
      await cacheUnderLegacyKey(plan);

      expect(await storage.hasFile(plan), isTrue);
    });

    test('are removed along with the current key', () async {
      final plan = _plan();
      await cacheUnderLegacyKey(plan);

      await storage.removeFile(plan);

      expect(await storage.hasFile(plan), isFalse);
    });

    test('lose to the current key when both exist', () async {
      final plan = _plan();
      await cacheUnderLegacyKey(plan);
      final current = await storage.write(
        hash: plan.offlineKey,
        name: plan.name!,
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(await storage.pathForFile(plan), current);
    });
  });
}
