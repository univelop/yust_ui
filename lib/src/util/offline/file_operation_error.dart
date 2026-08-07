import 'dart:async';
import 'dart:io';

// FirebaseException, re-exported by cloud_firestore, covers Storage errors too.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart';

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
/// the operation's attempt budget instead of retrying forever.
///
/// Unrecognised errors are transient, deliberately: mistaking a transient error
/// for permanent parks a user's change, the reverse only wastes retries.
bool isPermanentOperationError(Object error) => switch (error) {
  // Bad input this code produced; retrying replays the same arguments.
  ArgumentError() => true,
  StateError() => true,
  // Listed explicitly so no subtype falls through to a permanent verdict.
  SocketException() ||
  TimeoutException() ||
  HttpException() ||
  ClientException() => false,
  FirebaseException(:final code) => _permanentFirebaseCodes.contains(code),
  _ => false,
};
