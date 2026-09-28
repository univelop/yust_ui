import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation_error.dart';

FirebaseException _firebase(String code) =>
    FirebaseException(plugin: 'firebase_storage', code: code);

void main() {
  group('permanent', () {
    test('a revoked or missing permission', () {
      for (final code in [
        'permission-denied',
        'unauthenticated',
        'unauthorized',
        'storage/unauthorized',
      ]) {
        expect(
          YustFileOperationError.reasonFor(_firebase(code)),
          YustFileOperationFailureReason.noPermission,
          reason: code,
        );
      }
    });

    test('an object that is not in Storage at all', () {
      for (final code in [
        'not-found',
        'object-not-found',
        'storage/object-not-found',
      ]) {
        expect(
          YustFileOperationError.reasonFor(_firebase(code)),
          YustFileOperationFailureReason.fileMissing,
          reason: code,
        );
      }
      // A download that comes back empty because the object is gone can never
      // succeed; without this it retried forever and never gave up.
      expect(
        YustFileOperationError.reasonFor(
          YustMissingStorageObjectException('gone'),
        ),
        YustFileOperationFailureReason.fileMissing,
      );
    });

    test('a file the server rejects', () {
      for (final code in ['invalid-argument', 'storage/invalid-argument']) {
        expect(
          YustFileOperationError.reasonFor(_firebase(code)),
          YustFileOperationFailureReason.fileInvalid,
          reason: code,
        );
      }
    });

    test('bad arguments this code produced', () {
      expect(
        YustFileOperationError.reasonFor(ArgumentError('empty path')),
        YustFileOperationFailureReason.unknown,
      );
      expect(
        YustFileOperationError.reasonFor(StateError('no executor')),
        YustFileOperationFailureReason.unknown,
      );
    });
  });

  group('transient', () {
    test('connection failures', () {
      expect(
        YustFileOperationError.reasonFor(const SocketException('no route')),
        isNull,
      );
      expect(
        YustFileOperationError.reasonFor(TimeoutException('slow')),
        isNull,
      );
      expect(
        YustFileOperationError.reasonFor(const HttpException('bad gateway')),
        isNull,
      );
      expect(
        YustFileOperationError.reasonFor(ClientException('reset')),
        isNull,
      );
    });

    test('a Firebase code that is a connection problem wearing a code', () {
      for (final code in [
        'unavailable',
        'retry-limit-exceeded',
        'deadline-exceeded',
        'canceled',
      ]) {
        expect(
          YustFileOperationError.reasonFor(_firebase(code)),
          isNull,
          reason: code,
        );
      }
    });

    test(
      'an unrecognised error, so a long offline spell cannot end an upload',
      () {
        expect(
          YustFileOperationError.reasonFor(Exception('something new')),
          isNull,
        );
        expect(YustFileOperationError.reasonFor('a bare string'), isNull);
      },
    );
  });
}
