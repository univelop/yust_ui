import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:yust/yust.dart';

import 'file_operation.dart';

/// A durable list of [FileOperation]s — the single route for every file change,
/// online or offline, both outbound (upload/rename/delete) and inbound
/// (download).
///
/// It is just a persistent list: [enqueue] appends, [pending] reads oldest-first
/// (optionally filtered by type so each manager sees only its own ops), and
/// [remove] drops one applied op by id. Two managers share the one queue, so
/// removal is by identity — not a head-pop. The list is saved to a single file
/// under [getApplicationSupportDirectory] so pending ops survive an app restart.
class SyncQueue {
  SyncQueue({Future<Directory> Function()? directoryProvider})
    : _rootProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _rootProvider;

  static const _fileName = 'sync_queue.json';

  /// Serialises every queue access. The backing file is a single blob shared by
  /// all producers (pickers, the sync manager) and the draining consumer, each a
  /// separate async call chain on the one isolate; without this, two overlapping
  /// load→mutate→save cycles interleave at their `await`s and the later save
  /// clobbers the earlier op. Every public method runs its whole cycle inside
  /// this chain so the file is only ever touched by one op at a time.
  Future<void> _lock = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _lock.then((_) => action());
    // Keep the chain alive past a failure so one error can't wedge the queue.
    _lock = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Appends [op] to the end of the queue.
  Future<void> enqueue<T extends YustFile>(FileOperation<T> op) =>
      _serialized(() async {
        final ops = await _load();
        ops.add(op.toJson());
        await _save(ops);
      });

  /// The pending ops, oldest first, without removing them. When [types] is
  /// given, only ops of those kinds are returned — the queue's one entry point
  /// for both the upload and download managers.
  Future<List<FileOperation<YustFile>>> pending({
    Set<FileOperationType>? types,
  }) => _serialized(() async {
    final ops = (await _load()).map(_decode);
    return (types == null ? ops : ops.where((op) => types.contains(op.type)))
        .toList();
  });

  /// Removes the op with [op]'s id. No-op when it is already gone (a manager
  /// removes each op only after it has applied it).
  Future<void> remove(FileOperation<YustFile> op) => _serialized(() async {
    final ops = await _load();
    ops.removeWhere((json) => json['id'] == op.id);
    await _save(ops);
  });

  Future<List<Map<String, dynamic>>> _load() async {
    final file = await _file();
    if (!file.existsSync()) return [];
    return (jsonDecode(await file.readAsString()) as List)
        .cast<Map<String, dynamic>>();
  }

  Future<void> _save(List<Map<String, dynamic>> ops) async =>
      (await _file()).writeAsString(jsonEncode(ops));

  Future<File> _file() async =>
      File('${(await _rootProvider()).path}/$_fileName');

  /// Rebuilds an op, picking the concrete file subtype from the stored
  /// `fileType` so a [YustImage]'s extra fields survive.
  FileOperation<YustFile> _decode(Map<String, dynamic> json) {
    final YustFile Function(Map<String, dynamic>) fileFromJson =
        json['fileType'] == YustImage.type
        ? YustImage.fromJson
        : YustFile.fromJson;
    return FileOperation.fromJson<YustFile>(json, fileFromJson);
  }
}
