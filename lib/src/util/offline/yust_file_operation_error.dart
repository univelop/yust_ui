import 'dart:async';
import 'dart:io';

// FirebaseException, re-exported by cloud_firestore, covers Storage errors too.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart';
import 'package:yust/yust.dart';

/// The bytes an operation needs are not in Storage at all.
///
/// Raised where the file service reports a failed transfer as empty bytes
/// rather than throwing, so the queue can tell "the object is gone" — which no
/// retry fixes — apart from "the server was unreachable", which every retry
/// might.
class YustMissingStorageObjectException extends YustException {
  YustMissingStorageObjectException(super.message);
}

/// Firebase codes no retry gets past: not allowed, or the target is gone.
/// Everything else (`unavailable`, `retry-limit-exceeded`, …) is a connection
/// problem wearing a code.
const _permanentFirebaseCodes = {
  'permission-denied',
  'unauthenticated',
  'unauthorized',
  'not-found',
  'object-not-found',
  'invalid-argument',
  'storage/unauthorized',
  'storage/object-not-found',
  'storage/invalid-argument',
};

/// Whether [error] means the operation can never succeed, so it counts against
/// the operation's attempt budget instead of retrying forever. Unrecognised
/// errors count as transient.
bool isPermanentOperationError(Object error) => switch (error) {
  // Bad input this code produced; retrying replays the same arguments.
  ArgumentError() => true,
  StateError() => true,
  // The object is not in Storage; no number of retries puts it there.
  YustMissingStorageObjectException() => true,
  // Listed explicitly so no subtype falls through to a permanent verdict.
  SocketException() ||
  TimeoutException() ||
  HttpException() ||
  ClientException() => false,
  FirebaseException(:final code) => _permanentFirebaseCodes.contains(code),
  _ => false,
};
