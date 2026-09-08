import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation_handler.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation_manager.dart';
import 'package:yust_ui/src/util/offline/yust_legacy_cache_migration.dart';
import 'package:yust_ui/src/util/offline/yust_offline_storage.dart';
import 'package:yust_ui/src/util/offline/yust_sync_queue.dart';

/// Never finishes an operation, so what the migration enqueued stays in the
/// queue to be inspected instead of being drained away by the handler's own
/// pass, which [YustFileOperationHandler.enqueueAll] starts.
class _ParkingManager implements YustFileOperationManager {
  @override
  Future<void> execute(YustFileOperation<YustFile> operation) =>
      Completer<void>().future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory storageRoot;
  late Directory stagingRoot;
  late YustSyncQueue queue;
  late YustOfflineStorage storage;
  late YustFileOperationHandler handler;

  setUp(() {
    storageRoot = Directory.systemTemp.createTempSync(
      'legacy_migration_storage',
    );
    stagingRoot = Directory.systemTemp.createTempSync(
      'legacy_migration_staging',
    );
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    queue = YustSyncQueue();
    storage = YustOfflineStorage(directoryProvider: () async => storageRoot);
    handler = YustFileOperationHandler(
      manager: _ParkingManager(),
      queue: queue,
      connectivityStream: const Stream<bool>.empty(),
    );
  });

  tearDown(() {
    handler.dispose();
    for (final root in [storageRoot, stagingRoot]) {
      if (root.existsSync()) root.deleteSync(recursive: true);
    }
  });

  Uint8List bytes(String content) => Uint8List.fromList(content.codeUnits);

  YustFile legacyFile(String name) => YustFile(
    name: name,
    storageFolderPath: 'workspaces/w1/records/rec1',
    linkedDocPath: 'workspaces/w1/records/rec1',
    linkedDocAttribute: 'brickValues.brick1',
    linkedDocStoresFilesAsMap: true,
    setCreatedAtToNow: false,
  );

  /// Writes [content] where the old handler staged its bytes and returns the
  /// entry as it sat in the preference.
  Map<String, String?> stage(YustFile file, String content) {
    final staged = File('${stagingRoot.path}/${file.name}');
    staged.writeAsBytesSync(bytes(content));
    file.devicePath = staged.path;
    return file.toLocalJson();
  }

  void seedPreference(List<Map<String, dynamic>> entries) =>
      SharedPreferences.setMockInitialValues({
        'YustCachedFiles': jsonEncode(entries),
      });

  Future<String?> readPreference() async =>
      (await SharedPreferences.getInstance()).getString('YustCachedFiles');

  test(
    'moves a cached upload onto the queue, bytes and address intact',
    () async {
      final file = legacyFile('plan.pdf');
      seedPreference([stage(file, 'pdf-bytes')]);

      await migrateLegacyFileCache(handler: handler, storage: storage);

      final pending = await queue.getPendingOperations();
      expect(pending, hasLength(1));
      final migrated = pending.single;
      expect(migrated.type, YustFileOperationType.upload);
      expect(migrated.file.name, 'plan.pdf');
      expect(migrated.file.linkedDocPath, 'workspaces/w1/records/rec1');
      expect(migrated.file.linkedDocAttribute, 'brickValues.brick1');
      expect(migrated.file.linkedDocStoresFilesAsMap, isTrue);
      expect(migrated.file.storageFolderPath, 'workspaces/w1/records/rec1');
      // Hashed on migration: the local JSON carried none, and the map layout keys
      // the record entry by it.
      expect(migrated.file.hash, isNotEmpty);

      final cachedPath = await storage.pathForFile(migrated.file.byteKey);
      expect(cachedPath, isNotNull);
      expect(File(cachedPath!).readAsBytesSync(), bytes('pdf-bytes'));
    },
  );

  test(
    'drops the staged copy and its devicePath once the bytes are cached',
    () async {
      final file = legacyFile('plan.pdf');
      final entry = stage(file, 'pdf-bytes');
      final stagedPath = entry['devicePath']!;
      seedPreference([entry]);

      await migrateLegacyFileCache(handler: handler, storage: storage);

      // A devicePath is taken as a readable on-device copy wherever a file is
      // presented, so it must not outlive the staged file.
      expect(
        (await queue.getPendingOperations()).single.file.devicePath,
        isNull,
      );
      expect(File(stagedPath).existsSync(), isFalse);
      expect(await readPreference(), isNull);
    },
  );

  test('keeps an image entry an image through the queue', () async {
    final image = YustImage(
      name: 'photo.jpg',
      storageFolderPath: 'workspaces/w1/records/rec1',
      linkedDocPath: 'workspaces/w1/records/rec1',
      linkedDocAttribute: 'brickValues.brick1',
    );
    seedPreference([stage(image, 'jpg-bytes')]);

    await migrateLegacyFileCache(handler: handler, storage: storage);

    expect((await queue.getPendingOperations()).single.file, isA<YustImage>());
  });

  test(
    'skips an entry whose staged bytes are gone, migrating the rest',
    () async {
      final purged = legacyFile('purged.pdf');
      final entry = stage(purged, 'gone');
      File(entry['devicePath']!).deleteSync();
      final kept = legacyFile('kept.pdf');
      seedPreference([entry, stage(kept, 'kept-bytes')]);

      await migrateLegacyFileCache(handler: handler, storage: storage);

      final pending = await queue.getPendingOperations();
      expect(pending.map((operation) => operation.file.name), ['kept.pdf']);
    },
  );

  test('skips an unreadable entry, migrating the rest', () async {
    final kept = legacyFile('kept.pdf');
    seedPreference([
      {'name': 'broken.pdf'},
      stage(kept, 'kept-bytes'),
    ]);

    await migrateLegacyFileCache(handler: handler, storage: storage);

    final pending = await queue.getPendingOperations();
    expect(pending.map((operation) => operation.file.name), ['kept.pdf']);
  });

  test('is a no-op without a legacy cache', () async {
    SharedPreferences.setMockInitialValues({});

    await migrateLegacyFileCache(handler: handler, storage: storage);

    expect(await queue.getPendingOperations(), isEmpty);
  });

  test('enqueues nothing on a second run', () async {
    seedPreference([stage(legacyFile('plan.pdf'), 'pdf-bytes')]);

    await migrateLegacyFileCache(handler: handler, storage: storage);
    await migrateLegacyFileCache(handler: handler, storage: storage);

    expect(await queue.getPendingOperations(), hasLength(1));
  });
}
