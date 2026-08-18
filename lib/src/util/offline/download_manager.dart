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
    if (await _storage.exists(file.byteKey)) {
      file.devicePath = await _storage.resolvePath(file.byteKey);
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
    //
    // Ask Storage which failure it was: an object that is not there can never
    // be fetched, and retrying it forever buries the queue in noise. A lookup
    // that cannot reach the server throws, and that is the transient case.
    if (bytes == null || bytes.isEmpty) {
      throw await missingOrUnreachable(storageFolder, file.name!);
    }
    file.devicePath = await _storage.write(
      key: file.byteKey,
      name: file.name!,
      bytes: bytes,
    );
    debugPrint(
      '[offline-sync] cached "${file.name}" (${bytes.length} bytes) '
      'from $storageFolder under ${file.byteKey}',
    );
  }
}

/// The error a failed transfer of [name] under [path] should be reported as:
/// permanent when Storage holds no such object, transient otherwise.
///
/// Shared by every executor that has to interpret the file service's empty
/// result, so "gone" and "unreachable" are told apart the same way everywhere.
Future<Exception> missingOrUnreachable(String path, String name) async {
  if (await Yust.fileService.fileExist(path: path, name: name)) {
    return YustException(LocaleKeys.exceptionFileNotFound.tr());
  }
  return MissingStorageObjectException(
    LocaleKeys.exceptionFileNotFound.tr(),
  );
}
