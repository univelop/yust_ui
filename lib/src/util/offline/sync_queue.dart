import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yust/yust.dart';

import 'file_operation.dart';

/// A durable list of [FileOperation]s — the single route for every file change,
/// online or offline, both outbound (upload/rename/delete) and inbound
/// (download).
///
/// It is just a persistent list: [enqueue] appends, [pending] reads oldest-first
/// (optionally filtered by type so each manager sees only its own operations), and
/// [remove] drops one applied operation by id. Two managers share the one queue, so
/// removal is by identity — not a head-pop. The list is saved to a single file
/// under [getApplicationSupportDirectory] so pending operations survive an app restart.
///
/// On web the list is held in memory instead — [getApplicationSupportDirectory]
/// has no web implementation. Web is online-only and needs the queue's ordering
/// and routing, not its durability.
class SyncQueue {
  SyncQueue({Future<Directory> Function()? directoryProvider})
    : _rootProvider = directoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _rootProvider;

  static const _fileName = 'sync_queue.json';

  /// Backs the queue on web, where there is no filesystem.
  final List<Map<String, dynamic>> _memory = [];

  /// Serialises every queue access. The backing file is a single blob shared by
  /// all producers (pickers, the sync manager) and the draining consumer, each a
  /// separate async call chain on the one isolate; without this, two overlapping
  /// load→mutate→save cycles interleave at their `await`s and the later save
  /// clobbers the earlier operation. Every public method runs its whole cycle inside
  /// this chain so the file is only ever touched by one operation at a time.
  Future<void> _lock = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _lock.then((_) => action());
    // Keep the chain alive past a failure so one error can't wedge the queue.
    _lock = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Appends [operation] to the end of the queue.
  Future<void> enqueue<T extends YustFile>(FileOperation<T> operation) =>
      _serialized(() async {
        final operations = await _load();
        operations.add(operation.toJson());
        await _save(operations);
      });

  /// The pending operations, oldest first, without removing them. When [types] is
  /// given, only operations of those kinds are returned — the queue's one entry point
  /// for both the upload and download managers.
  Future<List<FileOperation<YustFile>>> pending({
    Set<FileOperationType>? types,
  }) => _serialized(() async {
    final operations = (await _load()).map(_decode);
    return (types == null
            ? operations
            : operations.where((operation) => types.contains(operation.type)))
        .toList();
  });

  /// Removes the operation with [operation]'s id. No-operation when it is already gone (a manager
  /// removes each operation only after it has applied it).
  Future<void> remove(FileOperation<YustFile> operation) =>
      _serialized(() async {
        final operations = await _load();
        operations.removeWhere((json) => json['id'] == operation.id);
        await _save(operations);
      });

  /// Overwrites the entry with [operation]'s id, keeping its position — the order is
  /// what holds a file's own operations in sequence. No-operation when the entry is gone.
  Future<void> replace(FileOperation<YustFile> operation) => _serialized(
    () async {
      final operations = await _load();
      final index = operations.indexWhere((json) => json['id'] == operation.id);
      if (index == -1) return;
      operations[index] = operation.toJson();
      await _save(operations);
    },
  );

  Future<List<Map<String, dynamic>>> _load() async {
    if (kIsWeb) return List<Map<String, dynamic>>.of(_memory);
    final file = await _file();
    if (!file.existsSync()) return [];
    return (jsonDecode(await file.readAsString()) as List)
        .cast<Map<String, dynamic>>();
  }

  Future<void> _save(List<Map<String, dynamic>> operations) async {
    if (kIsWeb) {
      _memory
        ..clear()
        ..addAll(operations);
      return;
    }
    await (await _file()).writeAsString(jsonEncode(operations));
  }

  Future<File> _file() async =>
      File('${(await _rootProvider()).path}/$_fileName');

  /// Rebuilds an operation, picking the concrete file subtype from the stored
  /// `fileType` so a [YustImage]'s extra fields survive.
  FileOperation<YustFile> _decode(Map<String, dynamic> json) {
    final YustFile Function(Map<String, dynamic>) fileFromJson =
        json['fileType'] == YustImage.type
        ? YustImage.fromJson
        : YustFile.fromJson;
    return FileOperation.fromJson<YustFile>(json, fileFromJson);
  }
}
