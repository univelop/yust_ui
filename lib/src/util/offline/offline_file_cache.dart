import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yust/yust.dart';

import 'offline_file_target.dart';

/// Device-side cache for offline files.
///
/// Writes file bytes to a temporary directory and persists the pending-cache
/// metadata in [SharedPreferences]. Pure IO — it does not touch Firestore or
/// the UI. A no-op on web, where there is no persistent filesystem.
///
/// Split out of the old `YustFileHandler` so the upload queue and download
/// manager can share one device-cache implementation instead of duplicating it.
class OfflineFileCache {
  OfflineFileCache({
    required this.target,
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getTemporaryDirectory;

  final OfflineFileTarget target;

  /// Base directory for on-device bytes. Defaults to the temporary directory
  /// (upload staging); the download manager passes the documents directory so
  /// offline copies survive OS temp purges and restarts.
  final Future<Directory> Function() _directoryProvider;

  static const _prefsKey = 'YustCachedFiles';

  /// Non-legacy prefs handle — hits the platform directly (no stale in-memory
  /// cache across isolates), the recommended replacement for `getInstance()`.
  static final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  /// Loads every cached file across all targets from local storage.
  static Future<List<YustFile>> loadAll() async {
    final rawJson = await _prefs.getString(_prefsKey) ?? '[]';

    return (jsonDecode(rawJson) as List)
        .cast<Map<String, dynamic>>()
        .map(
          (fileJson) => fileJson['type'] == YustImage.type
              ? YustImage.fromLocalJson(fileJson)
              : YustFile.fromLocalJson(fileJson),
        )
        .toList();
  }

  /// The cached files that belong to this cache's [target].
  Future<List<YustFile>> loadForTarget() async =>
      (await loadAll()).where(target.owns).toList();

  /// Replaces this target's entries in the shared cache blob with [cachedFiles],
  /// leaving other targets' entries untouched.
  Future<void> saveForTarget(List<YustFile> cachedFiles) async {
    final all = await loadAll()
      ..removeWhere(target.owns)
      ..addAll(cachedFiles);

    await _prefs.setString(
      _prefsKey,
      jsonEncode(all.map((file) => file.toLocalJson()).toList()),
    );
  }

  /// Writes [file]'s bytes (or source file) to the device and sets its
  /// [YustFile.devicePath]. No-op on web.
  Future<void> writeToDevice(YustFile file) async {
    if (kIsWeb) return;
    final directory = await _directoryFor(file);
    file.devicePath = '$directory${file.name}';

    if (file.bytes != null) {
      file.file = await File(file.devicePath!).writeAsBytes(file.bytes!);
    } else if (file.file != null) {
      await file.file!.copy(file.devicePath!);
    }
  }

  /// Deletes [file]'s on-device copy and clears its cache-bound fields.
  Future<void> removeFromDevice(YustFile file) async {
    final devicePath = file.devicePath;
    if (devicePath != null && File(devicePath).existsSync()) {
      await File(devicePath).delete();
    }
    file.devicePath = null;
    file.file = null;
    file.bytes = null;
  }

  /// Whether [file]'s bytes are present on the device.
  Future<bool> existsOnDevice(YustFile file) async =>
      file.devicePath != null && await File(file.devicePath!).exists();

  /// Resolves [file]'s deterministic on-device location. If the bytes are
  /// present there, sets [YustFile.devicePath] and returns true. Lets a file
  /// loaded from Firestore (no [devicePath]) discover its cached copy.
  Future<bool> locateOnDevice(YustFile file) async {
    if (kIsWeb || file.name == null) return false;
    final path = '${await _directoryFor(file)}${file.name}';
    if (!await File(path).exists()) return false;
    file.devicePath = path;
    return true;
  }

  /// Computes and stores the md5 [YustFile.hash] from the file's bytes.
  Future<void> computeHash(YustFile file) async {
    if (file.file != null) {
      file.hash = (await file.file!.openRead().transform(md5).first).toString();
    } else if (file.bytes != null) {
      file.hash = md5.convert(file.bytes!).toString();
    }
  }

  Future<String> _directoryFor(YustFile file) async {
    final baseDir = await _directoryProvider();
    final path =
        '${baseDir.path}/${file.storageFolderPath ?? target.storageFolderPath}/';
    final directory = Directory(path);
    if (!directory.existsSync()) await directory.create(recursive: true);
    return path;
  }
}
