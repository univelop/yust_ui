import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/file_operation.dart';
import 'package:yust_ui/src/util/offline/offline_storage.dart';

void main() {
  late Directory root;
  late OfflineStorage storage;

  setUp(() {
    root = Directory.systemTemp.createTempSync('offline_storage_test');
    storage = OfflineStorage(directoryProvider: () async => root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Uint8List bytes(String content) => Uint8List.fromList(content.codeUnits);

  test('write stores bytes and resolvePath finds them', () async {
    final path = await storage.write(
      key: 'h1',
      name: 'plan.pdf',
      bytes: bytes('pdf-bytes'),
    );

    expect(path, endsWith('/h1/plan.pdf'));
    expect(await storage.resolvePath('h1'), path);
    expect(await storage.exists('h1'), isTrue);
    expect(File(path!).readAsBytesSync(), bytes('pdf-bytes'));
  });

  test('resolvePath / exists are null / false for an unknown entry', () async {
    expect(await storage.resolvePath('missing'), isNull);
    expect(await storage.exists('missing'), isFalse);
  });

  test('remove deletes the entry and is safe when already gone', () async {
    await storage.write(key: 'h1', name: 'plan.pdf', bytes: bytes('x'));
    await storage.remove('h1');

    expect(await storage.exists('h1'), isFalse);
    await storage.remove('h1'); // no throw on a second remove
  });

  test('a copy cached for other content is not served', () async {
    // A signature is `signature.png` before and after it is re-drawn, so the
    // copy of the old one must not answer for the new one.
    YustFile signature(String hash) => YustFile(
      name: 'signature.png',
      hash: hash,
      storageFolderPath: 'records/rec1',
      setCreatedAtToNow: false,
    );
    await storage.write(
      key: signature('old').byteKey,
      name: 'signature.png',
      bytes: bytes('old-drawing'),
    );

    expect(await storage.pathForFile(signature('new')), isNull);
    expect(await storage.hasFile(signature('old')), isTrue);
  });

  test('entries are independent — writing one never drops another', () async {
    await storage.write(key: 'h1', name: 'a.pdf', bytes: bytes('a'));
    await storage.write(key: 'h2', name: 'b.pdf', bytes: bytes('b'));

    expect(await storage.exists('h1'), isTrue);
    expect(await storage.exists('h2'), isTrue);

    await storage.remove('h1');
    expect(await storage.exists('h1'), isFalse);
    expect(await storage.exists('h2'), isTrue);
  });
}
