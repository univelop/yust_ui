import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yust/yust.dart';

import '../../extensions/string_translate_extension.dart';
import '../../generated/locale_keys.g.dart';
import 'offline_file_cache.dart';
import 'offline_file_target.dart';

/// Pulls chosen files down and keeps them on the device so they are available
/// offline — the "download" half of the offline file handling, split out of the
/// old `YustFileHandler` (which could only upload).
///
/// Each file carries its own storage `path`, so this manager is not bound to a
/// single brick/target: it derives the storage folder per file. Copies live in
/// the documents directory (durable across restarts, unlike the upload queue's
/// temp staging). A no-op on web, where there is no persistent filesystem.
class OfflineDownloadManager<T extends YustFile> {
  OfflineDownloadManager()
    : _cache = OfflineFileCache(
        target: const OfflineFileTarget(storageFolderPath: ''),
        directoryProvider: getApplicationDocumentsDirectory,
      );

  final OfflineFileCache _cache;

  /// A file's bytes live under its storage `path`; mirror it onto
  /// `storageFolderPath` so the device cache keys the local copy consistently.
  void _ensureStorageFolder(T file) => file.storageFolderPath ??= file.path;

  /// Downloads [file]'s bytes and keeps them on the device. Skips the download
  /// when a copy already exists unless [force] (used when the file changed).
  /// No-op on web or when the file has no storage location yet.
  Future<void> markOffline(T file, {bool force = false}) async {
    if (kIsWeb || file.name == null) return;
    _ensureStorageFolder(file);
    final storageFolder = file.storageFolderPath;
    if (storageFolder == null || storageFolder.isEmpty) return;
    if (!force && await _cache.locateOnDevice(file)) return;

    final bytes = await Yust.fileService.downloadFile(
      path: storageFolder,
      name: file.name!,
    );
    if (bytes == null) {
      throw YustException(LocaleKeys.exceptionFileNotFound.tr());
    }
    file.bytes = bytes;
    await _cache.writeToDevice(file); // sets devicePath, writes bytes
    file.bytes = null; // release memory once written
  }

  /// Removes [file]'s offline copy from the device.
  Future<void> removeOffline(T file) async {
    _ensureStorageFolder(file);
    if (await _cache.locateOnDevice(file)) await _cache.removeFromDevice(file);
  }

  /// Whether [file] currently has an on-device copy (sets its [devicePath] if
  /// found).
  Future<bool> isAvailableOffline(T file) async {
    _ensureStorageFolder(file);
    return _cache.locateOnDevice(file);
  }
}
