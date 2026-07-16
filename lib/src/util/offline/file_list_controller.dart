import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

import 'offline_file_cache.dart';
import 'offline_file_doc_writer.dart';
import 'offline_file_target.dart';
import 'offline_upload_queue.dart';

/// Widget-facing model for a brick's file list.
///
/// Owns the merged view of "online files (already persisted on the record) +
/// pending uploads still in the queue", reconciles local/remote deletions, and
/// resolves each file's on-device state. This is the list-model concern that
/// used to be tangled inside `YustFileHandler`; here it delegates all IO to the
/// [OfflineUploadQueue] (uploads), [OfflineFileCache] (device state) and the
/// [OfflineFileDocWriter] (deletes), and notifies listeners so pickers rebuild
/// — replacing the old `onFileUploaded` + manual `setState`.
class FileListController<T extends YustFile> extends ChangeNotifier {
  FileListController({
    required this.target,
    required this.docWriter,
    this.newestFirst = false,
    this.onOnlineFilesChanged,
  }) : _queue = OfflineUploadQueue<T>(target: target, docWriter: docWriter),
       _cache = OfflineFileCache(target: target);

  final OfflineFileTarget target;
  final OfflineFileDocWriter docWriter;

  /// Whether the newest file is shown first.
  bool newestFirst;

  /// Notified with the current online files whenever they change, letting a
  /// host observe the persisted set (e.g. to update a brick value).
  final void Function(List<T>)? onOnlineFilesChanged;

  final OfflineUploadQueue<T> _queue;
  final OfflineFileCache _cache;

  /// The merged list, insertion-ordered (oldest first) internally.
  final List<T> _files = [];

  /// Keys of files the user just deleted, so a lagging server snapshot does not
  /// resurrect them before the delete propagates.
  final Set<String> _recentlyDeleted = {};

  /// The files to display, honouring [newestFirst].
  List<T> get files => newestFirst
      ? _files.reversed.toList(growable: false)
      : List.unmodifiable(_files);

  /// Files already uploaded/persisted (carry a storage path or url).
  List<T> get onlineFiles => _files.where(_isOnline).toList();

  /// Files with an on-device copy (pending upload or downloaded for offline).
  List<T> get cachedFiles => _files.where((file) => file.cached).toList();

  bool _isOnline(T file) => file.path != null || file.url != null;

  String _keyOf(YustFile file) =>
      file.hash.isNotEmpty ? file.hash : (file.name ?? '');

  /// Reconciles the list with the [incoming] online files from the record,
  /// keeping pending (still-uploading) files and honouring recent deletes.
  /// Call on init and whenever the brick value changes.
  Future<void> setOnlineFiles(List<T> incoming) async {
    final merged = <String, T>{};

    // Pending cached files first so an in-flight upload survives a refresh.
    for (final file in (await _cache.loadForTarget()).whereType<T>()) {
      await _cache.locateOnDevice(file);
      merged[_keyOf(file)] = file;
    }

    for (final file in incoming) {
      target.apply(file);
      if (_recentlyDeleted.contains(_keyOf(file))) continue;
      await _cache.locateOnDevice(file); // sets devicePath if downloaded
      merged.putIfAbsent(_keyOf(file), () => file); // keep pending over online
    }

    _files
      ..clear()
      ..addAll(merged.values);
    notifyListeners();
  }

  /// Adds [file]: shows it immediately, then uploads (and persists via the
  /// injected doc writer) through the queue.
  Future<void> add(T file) async {
    target.apply(file);
    _files.add(file);
    notifyListeners();
    await _queue.enqueue(file);
    _emitOnlineFiles();
    notifyListeners();
  }

  /// Replaces [file]'s bytes (e.g. re-drawn signature/image) and re-uploads it.
  Future<void> replaceBytes(T file, Uint8List bytes) async {
    file.bytes = bytes;
    await _queue.enqueue(file);
    _emitOnlineFiles();
    notifyListeners();
  }

  /// Deletes [file] everywhere: the display list, the device cache/queue, and —
  /// if already uploaded — Storage and the linked document.
  Future<void> delete(T file) async {
    target.apply(file);
    _files.removeWhere((existing) => _keyOf(existing) == _keyOf(file));
    _recentlyDeleted.add(_keyOf(file));
    notifyListeners();

    if (_isOnline(file)) {
      await Yust.fileService.deleteFile(
        path: file.storageFolderPath ?? target.storageFolderPath,
        name: file.name!,
      );
      if (target.isLinked) await docWriter.removeFile(file);
    } else {
      await _queue.remove(file); // still queued → drop from cache + queue
    }
    _emitOnlineFiles();
  }

  /// Retries any queued uploads (e.g. on reconnect / app start).
  Future<void> flushUploads() => _queue.flush();

  void _emitOnlineFiles() => onOnlineFilesChanged?.call(onlineFiles);
}
