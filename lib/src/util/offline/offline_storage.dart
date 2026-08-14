import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yust/yust.dart';

import 'file_operation.dart';

/// Durable on-device storage for offline file bytes.
///
/// Each file's bytes live under [getApplicationSupportDirectory] (durable, never
/// OS-purged), in a directory named after its content hash:
/// `<app-support>/offline_files/<hash>/<name>`.
///
/// Native only, but safe to call from anywhere: on web every method answers as
/// though nothing were stored, so callers never branch on `kIsWeb` themselves.
class OfflineStorage {
  OfflineStorage({Future<Directory> Function()? directoryProvider})
    : _rootProvider = directoryProvider ?? getApplicationSupportDirectory;

  /// The base directory. Defaults to the application support directory; tests
  /// inject a temporary directory so no real IO leaks.
  final Future<Directory> Function() _rootProvider;

  static const _folder = 'offline_files';

  /// Writes [bytes] (or copies [file]) for the entry [hash] under [name] and
  /// returns the path to them. Null on web, where nothing is cached, and null
  /// when there was nothing to write — a path to bytes that do not exist reads
  /// as [YustFile.cached] everywhere and sends readers to a missing file.
  Future<String?> write({
    required String hash,
    required String name,
    Uint8List? bytes,
    File? file,
  }) async {
    if (kIsWeb || (bytes == null && file == null)) return null;
    final directory = await _entryDirectory(hash);
    final path = '${directory.path}/$name';
    if (bytes != null) {
      await File(path).writeAsBytes(bytes);
    } else {
      await file!.copy(path);
    }
    return path;
  }

  /// The path to the entry's bytes, or null when absent.
  Future<String?> resolvePath(String hash) async {
    if (kIsWeb) return null;
    final directory = Directory('${await _root()}/$_folder/$hash');
    if (!directory.existsSync()) return null;
    final files = directory.listSync().whereType<File>();
    return files.isEmpty ? null : files.first.path;
  }

  /// Whether the entry's bytes are present.
  Future<bool> exists(String hash) async => (await resolvePath(hash)) != null;

  /// The path to [file]'s on-device copy, or null when absent.
  ///
  /// Falls back to [YustFileOfflineKey.legacyOfflineKey] so bytes cached before
  /// hashless files got a location-scoped key still resolve. Drop the fallback
  /// once no install can still hold such an entry.
  Future<String?> pathForFile(YustFile file) async =>
      await resolvePath(file.offlineKey) ??
      await resolvePath(file.legacyOfflineKey);

  /// Whether an on-device copy of [file] is present.
  Future<bool> hasFile(YustFile file) async =>
      (await pathForFile(file)) != null;

  /// Removes [file]'s on-device copy, under either key.
  Future<void> removeFile(YustFile file) async {
    await remove(file.offlineKey);
    await remove(file.legacyOfflineKey);
  }

  /// Resolves the best URI to read [file] from, hiding the web/offline decision
  /// from callers (views, renderers) so they never branch on `kIsWeb` or check
  /// availability themselves: the on-device copy when present (native only),
  /// else the signed network URL, else null.
  Future<Uri?> resolveUri(YustFile file) async {
    final path = await pathForFile(file);
    if (path != null) {
      file.devicePath = path;
      return Uri.file(path);
    }
    final url = file.getOriginalUrl();
    return url == null ? null : Uri.parse(url);
  }

  /// Removes the entry's bytes. Safe if already gone.
  Future<void> remove(String hash) async {
    if (kIsWeb) return;
    final directory = Directory('${await _root()}/$_folder/$hash');
    if (directory.existsSync()) await directory.delete(recursive: true);
  }

  Future<Directory> _entryDirectory(String hash) async {
    final directory = Directory('${await _root()}/$_folder/$hash');
    if (!directory.existsSync()) await directory.create(recursive: true);
    return directory;
  }

  Future<String> _root() async => (await _rootProvider()).path;
}
