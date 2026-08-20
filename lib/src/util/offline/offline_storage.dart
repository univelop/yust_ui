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
/// [readText] and [writeText] keep a plain text file next to those entries, for
/// the state the offline handling persists besides bytes.
///
/// Native only, and it never pretends otherwise: every method here does real
/// IO. A device without durable storage has no instance at all — see
/// [forDevice] — so "there is nowhere to keep this" is the absence of the
/// object rather than a guard inside it.
class OfflineStorage {
  OfflineStorage({Future<Directory> Function()? directoryProvider})
    : _rootProvider = directoryProvider ?? getApplicationSupportDirectory;

  /// The device's store, or null where the device keeps nothing — web, which
  /// has no durable directory. The one place the platform is asked; everything
  /// downstream holds the nullable result and reads null as "nothing is kept".
  static OfflineStorage? forDevice() => kIsWeb ? null : OfflineStorage();

  /// The base directory. Defaults to the application support directory; tests
  /// inject a temporary directory so no real IO leaks.
  final Future<Directory> Function() _rootProvider;

  static const _folder = 'offline_files';

  /// Writes [bytes] (or copies [file]) for the entry [byteKey] under [name] and
  /// returns the path to them. Null on web, where nothing is cached, and null
  /// when there was nothing to write — a path to bytes that do not exist reads
  /// as [YustFile.cached] everywhere and sends readers to a missing file.
  Future<String?> write({
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
  Future<String?> pathForFile(String byteKey) async {
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

  /// The contents of the text file [name] held next to the byte entries.
  Future<String?> readText(String name) async {
    final file = File('${await _root()}/$_folder/$name');
    return file.existsSync() ? file.readAsString() : null;
  }

  /// Writes [text] to the text file [name] next to the byte entries.
  Future<void> writeText(String name, String text) async {
    await File('${(await _folderDirectory()).path}/$name').writeAsString(text);
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
