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
    test('a Firebase code that no retry can get past', () {
      for (final code in [
        'permission-denied',
        'unauthenticated',
        'not-found',
        'object-not-found',
        'invalid-argument',
      ]) {
        expect(
          YustFileOperationError.isPermanent(_firebase(code)),
          isTrue,
          reason: code,
        );
      }
    });

    test('an object that is not in Storage at all', () {
      // A download that comes back empty because the object is gone can never
      // succeed; without this it retried forever and never timed out.
      expect(
        YustFileOperationError.isPermanent(
          YustMissingStorageObjectException('gone'),
        ),
        isTrue,
      );
    });

    test('bad arguments this code produced', () {
      expect(
        YustFileOperationError.isPermanent(ArgumentError('empty path')),
        isTrue,
      );
      expect(
        YustFileOperationError.isPermanent(StateError('no executor')),
        isTrue,
      );
    });
  });

  group('transient', () {
    test('connection failures', () {
      expect(
        YustFileOperationError.isPermanent(const SocketException('no route')),
        isFalse,
      );
      expect(
        YustFileOperationError.isPermanent(TimeoutException('slow')),
        isFalse,
      );
      expect(
        YustFileOperationError.isPermanent(const HttpException('bad gateway')),
        isFalse,
      );
      expect(
        YustFileOperationError.isPermanent(ClientException('reset')),
        isFalse,
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
          YustFileOperationError.isPermanent(_firebase(code)),
          isFalse,
          reason: code,
        );
      }
    });

    test(
      'an unrecognised error, so a long offline spell cannot park a file',
      () {
        expect(
          YustFileOperationError.isPermanent(Exception('something new')),
          isFalse,
        );
        expect(YustFileOperationError.isPermanent('a bare string'), isFalse);
      },
    );
  });
}
