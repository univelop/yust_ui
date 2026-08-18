import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yust/yust.dart';

import 'file_operation.dart';
import 'file_operation_handler.dart';
import 'offline_storage.dart';

/// Where the pre-queue file handler kept its pending uploads.
const _preferenceKey = 'YustCachedFiles';

/// Moves uploads an install queued before the sync queue existed onto the queue.
///
/// The old handler cached pending uploads as [YustFile.toLocalJson] maps in
/// SharedPreferences under [_preferenceKey], with their bytes in the temporary
/// directory. Nothing writes that cache any more, so an install that went
/// offline on the old build and updated before reconnecting would lose those
/// files; this drains it once, on the launch after the update.
///
/// Bytes are copied into [OfflineStorage] rather than left where they are: the
/// queue does not serialise a file's [YustFile.file], so an operation that
/// relied on the temp copy would find nothing after a restart — and the
/// temporary directory is OS-purgeable besides.
///
/// Idempotent by way of clearing the preference last: a crash before that
/// re-runs the migration and enqueues the same uploads again, which write the
/// same bytes under the same name, storage path and hash-keyed record entry.
///
/// Delete this once every active install has launched a release containing it.
Future<void> migrateLegacyFileCache({
  required FileOperationHandler handler,
  OfflineStorage? storage,
}) async {
  // The old cache was mobile-only — it staged bytes in the temporary directory,
  // which has no web implementation.
  if (kIsWeb) return;

  final preferences = await SharedPreferences.getInstance();
  final entries = _decodeEntries(preferences.getString(_preferenceKey));
  if (entries.isEmpty) return;

  final offlineStorage = storage ?? OfflineStorage();
  final operations = <FileOperation<YustFile>>[];
  final stagedFiles = <File>[];

  for (final entry in entries) {
    try {
      final file = entry['type'] == YustImage.type
          ? YustImage.fromLocalJson(entry)
          : YustFile.fromLocalJson(entry);
      final stagedFile = File(file.devicePath ?? '');
      // Nothing to upload: the temporary directory was purged since the entry
      // was cached, and the bytes were its only copy.
      if (!stagedFile.existsSync()) continue;

      file.file = stagedFile;
      // The local JSON carried no hash, and the record entry is keyed by it.
      await file.ensureHash();
      await offlineStorage.write(
        key: file.byteKey,
        name: file.name!,
        file: stagedFile,
      );
      // The staged copy is about to be deleted, and a devicePath is taken as a
      // readable on-device copy wherever a file is presented.
      file.devicePath = null;

      operations.add(
        FileOperation<YustFile>(type: FileOperationType.upload, file: file),
      );
      stagedFiles.add(stagedFile);
    } catch (error) {
      debugPrint('[offline-sync] skipped an unreadable legacy entry: $error');
    }
  }

  await handler.enqueueAll(operations);
  await preferences.remove(_preferenceKey);
  for (final stagedFile in stagedFiles) {
    await stagedFile.delete();
  }
  debugPrint('[offline-sync] migrated ${operations.length} legacy uploads');
}

/// The cached entries, or none when the preference is absent or unreadable.
List<Map<String, dynamic>> _decodeEntries(String? json) {
  if (json == null || json.isEmpty) return [];
  try {
    return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
  } catch (error) {
    debugPrint('[offline-sync] legacy file cache is unreadable: $error');
    return [];
  }
}
