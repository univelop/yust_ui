import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

import '../../extensions/string_translate_extension.dart';
import '../../generated/locale_keys.g.dart';
import 'offline_file_cache.dart';
import 'offline_file_doc_writer.dart';
import 'offline_file_target.dart';

/// Pushes offline files up to Storage and writes their metadata back to
/// Firestore.
///
/// The queue is the source of truth for "not yet uploaded". An entry is cached
/// on the device on [enqueue] and only leaves the queue once BOTH the Storage
/// upload and the Firestore write are confirmed — never optimistically. A crash
/// mid-upload leaves the entry intact, so the next [flush] retries it cleanly.
///
/// The metadata write itself is delegated to an [OfflineFileDocWriter] supplied
/// by the app layer, so it runs through the app's sanctioned, conflict-free
/// write (a field-mask-scoped `record.save`) rather than a raw Firestore write.
class OfflineUploadQueue<T extends YustFile> {
  OfflineUploadQueue({required this.target, required this.docWriter})
    : _cache = OfflineFileCache(target: target);

  final OfflineFileTarget target;
  final OfflineFileDocWriter docWriter;
  final OfflineFileCache _cache;

  bool _flushing = false;

  /// Records intent to upload [file]. Non-cacheable files (or web) upload
  /// immediately; cacheable ones are written to the device cache, queued, and
  /// flushed.
  Future<void> enqueue(T file) async {
    target.apply(file);
    if (kIsWeb || !file.cacheable) {
      await _uploadAndWriteBack(file);
      return;
    }
    await _cache.writeToDevice(file);
    final pending = await _cache.loadForTarget()
      ..add(file);
    await _cache.saveForTarget(pending);
    await flush();
  }

  /// Attempts to upload every queued file for this target. Confirmed uploads
  /// are dequeued; failures stay queued (with their [YustFile.lastError]) for
  /// the next flush. Returns silently while offline.
  Future<void> flush() async {
    if (_flushing || await _isOffline()) return;
    _flushing = true;
    try {
      final stillQueued = <YustFile>[];
      for (final file in await _cache.loadForTarget()) {
        if (!await _cache.existsOnDevice(file)) continue; // bytes gone → drop
        try {
          file.file = File(file.devicePath!);
          await _uploadAndWriteBack(file);
          await _cache.removeFromDevice(file); // clears devicePath → dequeued
        } catch (error) {
          file.lastError = error.toString();
          stillQueued.add(file);
        }
      }
      await _cache.saveForTarget(stillQueued);
    } finally {
      _flushing = false;
    }
  }

  Future<void> _uploadAndWriteBack(YustFile file) async {
    if (file.storageFolderPath == null) {
      throw YustException(LocaleKeys.exceptionMissingStorageFolderPath.tr());
    }
    if (await _isOffline()) throw LocaleKeys.missingConnection.tr();

    // ignore: deprecated_member_use
    final url = await Yust.fileService.uploadFile(
      path: file.storageFolderPath!,
      name: file.name!,
      file: file.file,
      bytes: file.bytes,
      linkedDocPath: file.linkedDocPath,
      linkedDocAttribute: file.linkedDocAttribute,
      createThumbnail: file.createThumbnail,
    );
    file.path = file.storageFolderPath; // enables signed-url building
    // ignore: deprecated_member_use
    file.url = url; // legacy fallback for readers not yet on signed URLs
    await _cache.computeHash(file);

    if (target.isLinked) await docWriter.writeFile(file);
  }

  /// Drops a still-queued (not yet uploaded) [file] from the queue and deletes
  /// its cached bytes. Used when the user deletes a file before it uploads.
  Future<void> remove(T file) async {
    target.apply(file);
    await _cache.removeFromDevice(file);
    final remaining = (await _cache.loadForTarget())
        .where((queued) => queued.name != file.name)
        .toList();
    await _cache.saveForTarget(remaining);
  }

  Future<bool> _isOffline() async {
    final result = await Connectivity().checkConnectivity();
    return result.every((entry) => entry == ConnectivityResult.none);
  }
}
