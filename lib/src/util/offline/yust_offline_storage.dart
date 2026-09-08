import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yust/yust.dart';

/// Durable on-device storage for everything the offline file handling keeps.
///
/// It owns the on-disk layout, so nothing else in the offline code builds a
/// path. A file's bytes live under [getApplicationSupportDirectory] (durable,
/// never OS-purged), in a directory named after its
/// `YustFileOfflineKey.byteKey`: `<app-support>/offline_files/<key>/<name>`.
///
/// Native only, and it never pretends otherwise: every method here does real
/// IO. A device without durable storage has no instance at all — see
/// [forDevice] — so "there is nowhere to keep this" is the absence of the
/// object rather than a guard inside it.
class YustOfflineStorage {
  YustOfflineStorage({Future<Directory> Function()? directoryProvider})
    : _rootProvider = directoryProvider ?? getApplicationSupportDirectory;

  /// The device's store, or null where the device keeps nothing — web, which
  /// has no durable directory. The one place the platform is asked; everything
  /// downstream holds the nullable result and reads null as "nothing is kept".
  static YustOfflineStorage? forDevice() =>
      kIsWeb ? null : YustOfflineStorage();

  /// The base directory. Defaults to the application support directory; tests
  /// inject a temporary directory so no real IO leaks.
  final Future<Directory> Function() _rootProvider;

  static const _folder = 'offline_files';

  /// Writes [bytes] (or copies [file]) for the entry [byteKey] under [name] and
  /// returns the path to them. Null on web, where nothing is cached, and null
  /// when there was nothing to write — a path to bytes that do not exist reads
  /// as [YustFile.cached] everywhere and sends readers to a missing file.
  Future<String?> writeBytes({
    required String byteKey,
    required String name,
    Uint8List? bytes,
    File? file,
  }) async {
    if (bytes == null && file == null) return null;
    final directory = await _entryDirectory(byteKey);
    final path = '${directory.path}/$name';
    if (bytes != null) {
      await File(path).writeAsBytes(bytes);
    } else {
      await file!.copy(path);
    }
    return path;
  }

  /// The path to the on-device copy of the file stored under [byteKey], or null
  /// when absent.
  ///
  /// An empty key addresses the store's own folder, whose first file could be
  /// the sync queue — so it is nothing, not everything.
  Future<String?> pathForFile(String byteKey) async {
    if (byteKey.isEmpty) return null;
    final directory = Directory('${await _root()}/$_folder/$byteKey');
    if (!directory.existsSync()) return null;
    final files = directory.listSync().whereType<File>();
    return files.isEmpty ? null : files.first.path;
  }

  /// Whether an on-device copy of the file stored under [byteKey] is present.
  Future<bool> hasFile(String byteKey) async =>
      (await pathForFile(byteKey)) != null;

  /// Removes the on-device copy of the file stored under [byteKey] and its whole entry directory.
  Future<void> removeFile(String byteKey) async {
    final directory = Directory('${await _root()}/$_folder/$byteKey');
    if (directory.existsSync()) await directory.delete(recursive: true);
  }

  /// The keys of every entry the store holds, empty when nothing is cached yet.
  Future<List<String>> cachedFileKeys() async {
    final folder = Directory('${await _root()}/$_folder');
    if (!folder.existsSync()) return [];
    return folder
        .listSync()
        .whereType<Directory>()
        // Each entry directory is named after its key, so the key is what is
        // left once the folder path is taken off. Removed by length rather
        // than by splitting on a separator, which differs per platform.
        .map((entry) => entry.path.substring(folder.path.length + 1))
        .toList();
  }

  Future<Directory> _entryDirectory(String key) async =>
      _ensureDirectoryIsCreated(
        Directory('${(await _folderDirectory()).path}/$key'),
      );

  Future<Directory> _folderDirectory() async =>
      _ensureDirectoryIsCreated(Directory('${await _root()}/$_folder'));

  Future<Directory> _ensureDirectoryIsCreated(Directory directory) async {
    if (!directory.existsSync()) await directory.create(recursive: true);
    return directory;
  }

  Future<String> _root() async => (await _rootProvider()).path;
}
