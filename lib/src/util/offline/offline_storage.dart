import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yust/yust.dart';

import 'file_operation.dart';

/// Durable on-device storage for offline file bytes.
///
/// Each file's bytes live under [getApplicationSupportDirectory] (durable, never
/// OS-purged), in a directory named after its
/// [YustFileOfflineKey.byteKey]: `<app-support>/offline_files/<key>/<name>`.
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
    if (kIsWeb || (bytes == null && file == null)) return null;
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
    if (kIsWeb) return null;
    final directory = Directory('${await _root()}/$_folder/$byteKey');
    if (!directory.existsSync()) return null;
    final files = directory.listSync().whereType<File>();
    return files.isEmpty ? null : files.first.path;
  }

  /// Whether an on-device copy of the file stored under [byteKey] is present.
  Future<bool> hasFile(String byteKey) async =>
      (await pathForFile(byteKey)) != null;

  /// Removes the on-device copy of the file stored under [byteKey] — its whole
  /// entry directory. Safe if already gone.
  Future<void> removeFile(String byteKey) async {
    if (kIsWeb) return;
    final directory = Directory('${await _root()}/$_folder/$byteKey');
    if (directory.existsSync()) await directory.delete(recursive: true);
  }

  Future<Directory> _entryDirectory(String key) async {
    final directory = Directory('${await _root()}/$_folder/$key');
    if (!directory.existsSync()) await directory.create(recursive: true);
    return directory;
  }

  Future<String> _root() async => (await _rootProvider()).path;
}
