import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart';
import 'package:test/test.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation_handler.dart';

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
          isPermanentOperationError(_firebase(code)),
          isTrue,
          reason: code,
        );
      }
    });

    test('an object that is not in Storage at all', () {
      // A download that comes back empty because the object is gone can never
      // succeed; without this it retried forever and never timed out.
      expect(
        isPermanentOperationError(YustMissingStorageObjectException('gone')),
        isTrue,
      );
    });

    test('bad arguments this code produced', () {
      expect(isPermanentOperationError(ArgumentError('empty path')), isTrue);
      expect(isPermanentOperationError(StateError('no executor')), isTrue);
    });
  });

  group('transient', () {
    test('connection failures', () {
      expect(
        isPermanentOperationError(const SocketException('no route')),
        isFalse,
      );
      expect(isPermanentOperationError(TimeoutException('slow')), isFalse);
      expect(
        isPermanentOperationError(const HttpException('bad gateway')),
        isFalse,
      );
      expect(isPermanentOperationError(ClientException('reset')), isFalse);
    });

    test('a Firebase code that is a connection problem wearing a code', () {
      for (final code in [
        'unavailable',
        'retry-limit-exceeded',
        'deadline-exceeded',
        'canceled',
      ]) {
        expect(
          isPermanentOperationError(_firebase(code)),
          isFalse,
          reason: code,
        );
      }
    });

    test(
      'an unrecognised error, so a long offline spell cannot park a file',
      () {
        expect(isPermanentOperationError(Exception('something new')), isFalse);
        expect(isPermanentOperationError('a bare string'), isFalse);
      },
    );
  });
}
