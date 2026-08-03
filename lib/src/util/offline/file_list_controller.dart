import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:yust/yust.dart';

import 'file_operation.dart';
import 'file_operation_handler.dart';
import 'file_upload_decision.dart';
import 'offline_file_target.dart';
import 'offline_storage.dart';

/// Widget-facing model for a brick's file list.
///
/// Shows the record's persisted files overlaid with the pending ops still in the
/// shared [FileOperationHandler]'s queue: a pending add shows straight from its
/// on-device bytes, a pending delete is hidden, a pending rename shows the new
/// name. The list-model concern that used to be tangled inside `YustFileHandler`;
/// here every change is a stateless command (write local bytes → enqueue an op),
/// and the display is derived — the queue is the single source of "not yet
/// synced", replacing the old in-memory tombstone.
class FileListController<T extends YustFile> extends ChangeNotifier {
  FileListController({
    required this.handler,
    required this.target,
    OfflineStorage? storage,
    this.newestFirst = false,
    this.onOnlineFilesChanged,
  }) : _storage = storage ?? OfflineStorage() {
    handler.addListener(_onQueueChanged);
  }

  /// The one app-scoped handler every file change flows through.
  final FileOperationHandler handler;

  /// Where this brick's files live (stamps files, filters pending ops).
  final OfflineFileTarget target;

  final OfflineStorage _storage;

  /// Whether the newest file is shown first.
  bool newestFirst;

  /// Notified with the current online files whenever they change, letting a
  /// host observe the persisted set (e.g. to update a brick value).
  final void Function(List<T>)? onOnlineFilesChanged;

  /// Persisted files from the record snapshot (last [setOnlineFiles]).
  final List<T> _online = [];

  /// This target's pending ops, oldest-first (mirrors the queue).
  List<FileOperation<YustFile>> _pending = [];

  /// The files to display: the record snapshot overlaid with pending ops,
  /// honouring [newestFirst].
  List<T> get files {
    final overlaid = _overlay();
    return newestFirst ? overlaid.reversed.toList(growable: false) : overlaid;
  }

  /// Files already persisted online (carry a storage path or url).
  List<T> get onlineFiles => _overlay().where(_isOnline).toList();

  /// Files with an on-device copy (pending upload or downloaded for offline).
  List<T> get cachedFiles => _overlay().where((file) => file.cached).toList();

  bool _isOnline(T file) =>
      // ignore: deprecated_member_use
      file.path != null || file.url != null;

  String _key(YustFile file) =>
      file.hash.isNotEmpty ? file.hash : (file.name ?? '');

  /// Overlays the pending ops onto the record snapshot, keyed by content hash
  /// (or name for hashless legacy files). A pending add/replace shows its local
  /// bytes; a pending delete is hidden. A rename is already reflected on the
  /// online instance (mutated optimistically by [rename]), so it needs no entry.
  List<T> _overlay() {
    final byKey = <String, T>{for (final file in _online) _key(file): file};
    for (final op in _pending) {
      switch (op.type) {
        case FileOperationType.upload:
          byKey[op.fileKey] = op.file as T;
        case FileOperationType.delete:
          byKey.remove(op.fileKey);
        case FileOperationType.rename:
        case FileOperationType.download:
          break;
      }
    }
    return List<T>.unmodifiable(byKey.values);
  }

  /// Reconciles the list with the [incoming] online files from the record.
  /// Call on init and whenever the brick value changes.
  Future<void> setOnlineFiles(List<T> incoming) async {
    _online
      ..clear()
      ..addAll(incoming);
    for (final file in _online) {
      target.apply(file);
      final path = await _storage.pathForFile(file);
      if (path != null) file.devicePath = path;
    }
    await _refreshPending();
  }

  /// Adds [file]: writes its bytes to the device, then enqueues the upload
  /// (which persists via the shared handler's doc-writer). Shown immediately
  /// through the pending overlay.
  Future<void> add(T file) async {
    target.apply(file);
    await _computeHash(file);
    await _writeBytes(file);
    await handler.enqueue(_op(FileOperationType.upload, file));
  }

  /// Replaces [file]'s bytes (e.g. a re-drawn signature/image) and re-uploads.
  Future<void> replaceBytes(T file, Uint8List bytes) async {
    target.apply(file);
    file
      ..bytes = bytes
      ..hash = '';
    await _computeHash(file);
    await _writeBytes(file);
    await handler.enqueue(_op(FileOperationType.upload, file));
  }

  /// Deletes [file]: a file still queued for upload is dropped from the queue
  /// (and its bytes removed); an already-persisted file is removed via a delete
  /// op.
  Future<void> delete(T file) async {
    target.apply(file);
    final pendingUpload = _pendingUploadFor(file);
    if (pendingUpload != null) {
      await handler.cancel(pendingUpload);
      await _storage.removeFile(file);
      return;
    }
    if (_isOnline(file)) {
      await handler.enqueue(_op(FileOperationType.delete, file));
    }
  }

  /// Renames [file] to [newName]: the displayed instance is updated at once,
  /// while the op carries an old-name snapshot so the executor can still fetch
  /// the original bytes to re-upload under the new name.
  Future<void> rename(T file, String newName) async {
    final snapshot = file.copyWithUrl(null)
      ..linkedDocStoresFilesAsMap = file.linkedDocStoresFilesAsMap;
    file.name = newName;
    await handler.enqueue(
      FileOperation<YustFile>(
        type: FileOperationType.rename,
        file: snapshot,
        newName: newName,
      ),
    );
  }

  /// Resolves how uploading a file named [newFileName] applies to the current
  /// list, honouring [numberOfFiles] and single-file overwrite. Pure — the
  /// caller reacts (confirm dialog / block); see [resolveFileUpload].
  FileUploadDecision<T> resolveUpload({
    required String newFileName,
    required int numberOfFiles,
    required bool overwriteSingleFile,
  }) => resolveFileUpload<T>(
    currentFiles: _overlay(),
    newFileName: newFileName,
    numberOfFiles: numberOfFiles,
    overwriteSingleFile: overwriteSingleFile,
  );

  /// Retries any queued ops (e.g. on reconnect / app start).
  Future<void> flushUploads() => handler.processPendingOperations();

  @override
  void dispose() {
    handler.removeListener(_onQueueChanged);
    super.dispose();
  }

  void _onQueueChanged() => unawaited(_refreshPending());

  Future<void> _refreshPending() async {
    final all = await handler.pending();
    _pending = all.where((op) => target.owns(op.file)).toList();
    _emitOnlineFiles();
    notifyListeners();
  }

  FileOperation<YustFile>? _pendingUploadFor(T file) {
    for (final op in _pending) {
      if (op.type == FileOperationType.upload && op.fileKey == _key(file)) {
        return op;
      }
    }
    return null;
  }

  /// Writes [file]'s bytes (or source file) to [OfflineStorage] and sets its
  /// [YustFile.devicePath]. A no-op on web (no persistent filesystem).
  Future<void> _writeBytes(YustFile file) async {
    if (kIsWeb) return;
    final key = _key(file);
    if (key.isEmpty || file.name == null) return;
    file.devicePath = await _storage.write(
      hash: key,
      name: file.name!,
      bytes: file.bytes,
      file: file.file,
    );
  }

  /// Computes the md5 [YustFile.hash] from the file's bytes so the storage key
  /// and record-map key are stable before upload.
  Future<void> _computeHash(YustFile file) async {
    if (file.hash.isNotEmpty) return;
    if (file.bytes != null) {
      file.hash = md5.convert(file.bytes!).toString();
    } else if (file.file != null) {
      file.hash = (await file.file!.openRead().transform(md5).first).toString();
    }
  }

  FileOperation<YustFile> _op(FileOperationType type, YustFile file) =>
      FileOperation<YustFile>(type: type, file: file);

  void _emitOnlineFiles() => onOnlineFilesChanged?.call(onlineFiles);
}
