import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/yust_file_helpers.dart';

YustFile _file({
  String? name = 'plan.pdf',
  String? path,
  String? url,
  String? devicePath,
  Uint8List? bytes,
}) => YustFile(
  name: name,
  path: path,
  // ignore: deprecated_member_use
  url: url,
  devicePath: devicePath,
  bytes: bytes,
  setCreatedAtToNow: false,
);

void main() {
  group('isFileBroken', () {
    test('a file with a storage path and no url is not broken', () {
      // The reported false positive: `url` is deprecated and no longer written,
      // so keying brokenness on it flagged every path-addressed file on web.
      expect(
        YustFileHelpers.isFileBroken(_file(path: 'records/rec1')),
        isFalse,
      );
    });

    test('a legacy file with only a url is not broken', () {
      expect(
        YustFileHelpers.isFileBroken(_file(url: 'https://cdn.test/plan.pdf')),
        isFalse,
      );
    });

    test('a nameless file is broken', () {
      expect(
        YustFileHelpers.isFileBroken(_file(name: null, path: 'records/rec1')),
        isTrue,
      );
    });

    test('an empty-named file is broken', () {
      expect(
        YustFileHelpers.isFileBroken(_file(name: '', path: 'records/rec1')),
        isTrue,
      );
    });

    test('a picked file readable from memory is not broken', () {
      // Queued for upload: no storage location yet, but its bytes are right
      // here.
      expect(
        YustFileHelpers.isFileBroken(
          _file(bytes: Uint8List.fromList([1, 2, 3])),
        ),
        isFalse,
      );
    });

    test('a file readable from the device copy is not broken', () {
      expect(
        YustFileHelpers.isFileBroken(
          _file(devicePath: '/tmp/offline/h1/plan.pdf'),
        ),
        isFalse,
      );
    });

    test('a file with no location and nothing local is broken', () {
      expect(YustFileHelpers.isFileBroken(_file()), isTrue);
    });

    test('an empty path or url does not count as a location', () {
      expect(YustFileHelpers.isFileBroken(_file(path: '', url: '')), isTrue);
    });
  });
}
