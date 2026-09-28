import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:yust/yust.dart';

import 'yust_file_operation.dart';

/// A durable list of [YustFileOperation]s — the single route for every file change,
/// online or offline, both outbound (upload/rename/delete) and inbound
/// (download).
///
/// It is just a persistent list: [enqueueOperation] appends,
/// [getPendingOperations] reads oldest-first and [removeOperation] drops one
/// applied operation by id. Two managers share the one queue, so removal is by
/// identity — not a head-pop. The list is saved as one JSON blob in
/// [SharedPreferencesAsync] under [_preferenceKey], the same place the app keeps
/// its record offline marks, so pending operations survive an app restart.
///
/// Without persistence — web, where a round-trip drops [YustFile.bytes] and
/// those are the file's only copy, so the upload would find nothing to send —
/// the operations are held in memory instead, as objects rather than as their
/// JSON.
class YustSyncQueue {
  /// Persists the queue in shared preferences.
  YustSyncQueue() : _preferences = SharedPreferencesAsync();

  /// A queue that is never written out, for a device that keeps no bytes — the
  /// caller decides which of the two it wants from whether the device has a
  /// byte store at all.
  YustSyncQueue.inMemory() : _preferences = null;

  /// Where the queue is persisted, or null when it is held in memory. Null is
  /// the whole of the in-memory mode — with nowhere to write there is nothing
  /// to read or write, so the fallback cannot be reached by mistake.
  final SharedPreferencesAsync? _preferences;

  /// The preference holding the queue as one JSON array.
  static const _preferenceKey = 'yustSyncQueue';

  /// The working copy: read from the preference once, then mutated in place.
  /// The preference, when present, is written through on each change; without
  /// it this is the operations' only copy.
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
    await _saveToDisk(operations);
  });

  /// The pending operations, oldest first, without removing them. The entries
  /// are the live objects: mutating one (its [YustFileOperation.failure])
  /// and calling [saveToDisk] writes the change back.
  Future<List<YustFileOperation<YustFile>>> getPendingOperations() =>
      _serialized(() async => List.of(await _load()));

  /// Removes the operation with [operation]'s id. No-operation when it is already gone (a manager
  /// removes each operation only after it has applied it).
  Future<void> removeOperation(YustFileOperation<YustFile> operation) =>
      _serialized(() async {
        final operations = await _load();
        operations.removeWhere((entry) => entry.id == operation.id);
        await _saveToDisk(operations);
      });

  /// Writes the whole queue to the preference, after an operation was mutated
  /// in place.
  /// A no-op in memory, where the working copy is already the only one.
  Future<void> saveToDisk() =>
      _serialized(() async => _saveToDisk(await _load()));

  Future<List<YustFileOperation<YustFile>>> _load() async =>
      _operations ??= await _readInitial();

  Future<List<YustFileOperation<YustFile>>> _readInitial() async {
    final json = await _preferences?.getString(_preferenceKey);
    if (json == null) return [];
    return (jsonDecode(json) as List)
        .cast<Map<String, dynamic>>()
        .map(_tryParseOperation)
        .whereType<YustFileOperation<YustFile>>()
        .toList();
  }

  /// Parses one stored entry, or drops it when it cannot be read
  YustFileOperation<YustFile>? _tryParseOperation(Map<String, dynamic> json) {
    try {
      return YustFileOperation.fromJson<YustFile>(json);
    } catch (_) {
      // TODO: a dropped entry is currently invisible: find a solution
      return null;
    }
  }

  Future<void> _saveToDisk(List<YustFileOperation<YustFile>> operations) async {
    if (_preferences == null) return;
    await _preferences.setString(
      _preferenceKey,
      jsonEncode(operations.map((operation) => operation.toJson()).toList()),
    );
  }
}
