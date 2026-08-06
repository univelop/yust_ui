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
/// Native only: it touches the real filesystem and has no web guard. Offline is
/// a native-only feature, so callers gate web at their boundary.
class OfflineStorage {
  OfflineStorage({Future<Directory> Function()? directoryProvider})
    : _rootProvider = directoryProvider ?? getApplicationSupportDirectory;

  /// The base directory. Defaults to the application support directory; tests
  /// inject a temporary directory so no real IO leaks.
  final Future<Directory> Function() _rootProvider;

  static const _folder = 'offline_files';

  /// Writes [bytes] (or copies [file]) for the entry [hash] under [name] and
  /// returns the path to them.
  Future<String> write({
    required String hash,
    required String name,
    Uint8List? bytes,
    File? file,
  }) async {
    final directory = await _entryDirectory(hash);
    final path = '${directory.path}/$name';
    if (bytes != null) {
      await File(path).writeAsBytes(bytes);
    } else if (file != null) {
      await file.copy(path);
    }
    return path;
  }

  /// The path to the entry's bytes, or null when absent.
  Future<String?> resolvePath(String hash) async {
    final directory = Directory('${await _root()}/$_folder/$hash');
    if (!directory.existsSync()) return null;
    final files = directory.listSync().whereType<File>();
    return files.isEmpty ? null : files.first.path;
  }

  /// Whether the entry's bytes are present.
  Future<bool> exists(String hash) async => (await resolvePath(hash)) != null;

  /// The path to [file]'s on-device copy, or null when absent.
  Future<String?> pathForFile(YustFile file) => resolvePath(file.offlineKey);

  /// Whether an on-device copy of [file] is present.
  Future<bool> hasFile(YustFile file) => exists(file.offlineKey);

  /// Removes [file]'s on-device copy.
  Future<void> removeFile(YustFile file) => remove(file.offlineKey);

  /// Resolves the best URI to read [file] from, hiding the web/offline decision
  /// from callers (views, renderers) so they never branch on `kIsWeb` or check
  /// availability themselves: the on-device copy when present (native only),
  /// else the signed network URL, else null.
  Future<Uri?> resolveUri(YustFile file) async {
    if (!kIsWeb) {
      final path = await resolvePath(file.offlineKey);
      if (path != null) {
        file.devicePath = path;
        return Uri.file(path);
      }
    }
    final url = file.getOriginalUrl();
    return url == null ? null : Uri.parse(url);
  }

  /// Removes the entry's bytes. Safe if already gone.
  Future<void> remove(String hash) async {
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
