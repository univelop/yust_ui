import 'dart:convert';

import 'package:yust/yust.dart';

import 'yust_file_operation.dart';
import 'yust_offline_storage.dart';

/// A durable list of [YustFileOperation]s — the single route for every file change,
/// online or offline, both outbound (upload/rename/delete) and inbound
/// (download).
///
/// It is just a persistent list: [enqueueOperation] appends,
/// [getPendingOperations] reads oldest-first and [removeOperation] drops one
/// applied operation by id. Two managers share the one queue, so removal is by
/// identity — not a head-pop. The list is saved as one JSON blob through
/// [YustOfflineStorage], next to the bytes it queues work for, so pending
/// operations survive an app restart.
///
/// Without a store — web, where the device keeps nothing — the operations are
/// held in memory instead, as objects rather than as their JSON: a round-trip
/// drops [YustFile.bytes], and on web those are the file's only copy, so the
/// upload would find nothing to send.
class YustSyncQueue {
  /// Persists the queue through [storage].
  YustSyncQueue({required YustOfflineStorage storage}) : _storage = storage;

  /// A queue that never reaches a store, for a device that has none. The
  /// caller decides which of the two it wants from whether
  /// [YustOfflineStorage.forDevice] returned an instance.
  YustSyncQueue.inMemory() : _storage = null;

  /// Where the queue is persisted, or null when it is held in memory. Null is
  /// the whole of the in-memory mode — with no store there is nothing to read
  /// or write, so the fallback cannot be reached by mistake.
  final YustOfflineStorage? _storage;

  static const _fileName = 'sync_queue.json';

  /// The working copy: loaded from storage once, then mutated in place. Storage,
  /// when present, is written through on each change; without it this is the
  /// operations' only copy.
  List<YustFileOperation<YustFile>>? _operations;

  /// Ensures each operation is fully written before the next one starts
  Future<void> _lock = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final run = _lock.then((_) => action());
    // Keep the chain alive past a failure so one error can't wedge the queue.
    _lock = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Appends [operation] to the end of the queue, unless one already pending
  /// has the same [YustFileOperation.identity].
  Future<void> enqueueOperation<T extends YustFile>(
    YustFileOperation<T> operation,
  ) => _serialized(() async {
    final operations = await _load();
    if (operations.any((existing) => existing.identity == operation.identity)) {
      return;
    }
    operations.add(operation);
    await _persist(operations);
  });

  /// The pending operations, oldest first, without removing them. The entries
  /// are the live objects: mutating one (its [YustFileOperation.failedAttempts])
  /// and calling [persist] writes the change back.
  Future<List<YustFileOperation<YustFile>>> getPendingOperations() =>
      _serialized(() async => List.of(await _load()));

  /// Removes the operation with [operation]'s id. No-operation when it is already gone (a manager
  /// removes each operation only after it has applied it).
  Future<void> removeOperation(YustFileOperation<YustFile> operation) =>
      _serialized(() async {
        final operations = await _load();
        operations.removeWhere((entry) => entry.id == operation.id);
        await _persist(operations);
      });

  /// Writes the current operations to storage, after one was mutated in place.
  /// A no-op without a store, where the working copy is already the only one.
  Future<void> persist() => _serialized(() async => _persist(await _load()));

  Future<List<YustFileOperation<YustFile>>> _load() async =>
      _operations ??= await _readInitial();

  Future<List<YustFileOperation<YustFile>>> _readInitial() async {
    final json = await _storage?.readText(_fileName);
    if (json == null) return [];
    return (jsonDecode(json) as List)
        .cast<Map<String, dynamic>>()
        .map(YustFileOperation.fromJson<YustFile>)
        .toList();
  }

  Future<void> _persist(List<YustFileOperation<YustFile>> operations) async {
    if (_storage == null) return;
    await _storage.writeText(
      _fileName,
      jsonEncode(operations.map((operation) => operation.toJson()).toList()),
    );
  }
}
