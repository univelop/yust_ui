import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

import 'file_operation.dart';
import 'file_operation_handler.dart';
import 'offline_storage.dart';

/// The byte-store and queue steps of a file change, without a list model.
///
/// For hosts that manage one file outside a picker (a drawing, an annotation
/// plan). [FileListController] delegates to it too.
class OfflineFileCommands {
  OfflineFileCommands({required this.handler, OfflineStorage? storage})
    : _storage = storage ?? OfflineStorage();

  /// The app-scoped handler every file change flows through.
  final FileOperationHandler handler;

  final OfflineStorage _storage;

  /// Writes [file]'s bytes to the device and enqueues its upload. Hashes first,
  /// so the bytes are cached under their content and the record entry the
  /// upload writes back is keyed by content, not by a dotted file name.
  Future<void> add(YustFile file) async {
    await file.ensureHash();
    await writeBytes(file);
    await handler.enqueue(
      FileOperation<YustFile>(type: FileOperationType.upload, file: file),
    );
  }

  /// Replaces [file]'s content with [bytes] and re-uploads it. The hash is
  /// cleared so [add] recomputes it for the new content.
  Future<void> replaceBytes(YustFile file, Uint8List bytes) {
    file
      ..bytes = bytes
      ..hash = '';
    return add(file);
  }

  /// Enqueues [file]'s deletion (Storage bytes and its record entry) and drops
  /// the on-device copy at once, so it stops opening from disk.
  Future<void> delete(YustFile file) async {
    await _storage.removeFile(file);
    await handler.enqueue(
      FileOperation<YustFile>(type: FileOperationType.delete, file: file),
    );
  }

  /// Writes [file]'s bytes (or source file) to the byte store and sets its
  /// [YustFile.devicePath]. Stays null on web.
  Future<void> writeBytes(YustFile file) async {
    final key = file.byteKey;
    if (key.isEmpty || file.name == null) return;
    file.devicePath = await _storage.write(
      key: key,
      name: file.name!,
      bytes: file.bytes,
      file: file.file,
    );
  }
}
