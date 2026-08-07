import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

import '../../extensions/string_translate_extension.dart';
import '../../generated/locale_keys.g.dart';
import 'file_operation.dart';
import 'file_operation_handler.dart';
import 'offline_storage.dart';

/// Fetches a file's bytes and keeps them on the device — the inbound executor.
///
/// The [FileOperationHandler] hands it a [FileOperationType.download] operation; it
/// downloads the bytes and stores them in [OfflineStorage] (keyed by content
/// hash). It knows nothing about queueing, retries or connectivity, so the same
/// fetch runs whether triggered by a pin or a remote change.
class DownloadManager implements FileOperationExecutor {
  DownloadManager({OfflineStorage? storage})
    : _storage = storage ?? OfflineStorage();

  final OfflineStorage _storage;

  @override
  Set<FileOperationType> get handledTypes => {FileOperationType.download};

  /// Downloads [operation]'s file and keeps its bytes on the device, setting the
  /// [YustFile.devicePath]. Skips the fetch when a copy already exists; a no-op
  /// when the file has no location.
  @override
  Future<void> execute(FileOperation<YustFile> operation) async {
    final file = operation.file;
    final storageFolder = file.storageFolderPath ?? file.path;
    if (file.name == null || storageFolder == null || storageFolder.isEmpty) {
      debugPrint(
        '[offline-sync] skipped download of "${file.name}": no storage '
        'location (storageFolderPath and path are both empty)',
      );
      return;
    }
    if (await _storage.exists(operation.fileKey)) {
      file.devicePath = await _storage.resolvePath(operation.fileKey);
      return;
    }
    final bytes = await Yust.fileService.downloadFile(
      path: storageFolder,
      name: file.name!,
    );
    // The Flutter file service swallows every download error and returns empty
    // bytes rather than throwing, so an empty result means the fetch failed.
    // Throw so the operation stays queued and self-heals on the next drain, instead of
    // caching a 0-byte file that would then read as "available offline".
    if (bytes == null || bytes.isEmpty) {
      throw YustException(LocaleKeys.exceptionFileNotFound.tr());
    }
    file.devicePath = await _storage.write(
      hash: operation.fileKey,
      name: file.name!,
      bytes: bytes,
    );
    debugPrint(
      '[offline-sync] cached "${file.name}" (${bytes.length} bytes) '
      'from $storageFolder under ${operation.fileKey}',
    );
  }
}
