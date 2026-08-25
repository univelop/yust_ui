import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation.dart';
import 'package:yust_ui/src/util/offline/yust_offline_storage.dart';

void main() {
  late Directory root;
  late YustOfflineStorage storage;

  setUp(() {
    root = Directory.systemTemp.createTempSync('offline_storage_test');
    storage = YustOfflineStorage(directoryProvider: () async => root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Uint8List bytes(String content) => Uint8List.fromList(content.codeUnits);

  test('write stores bytes and pathForFile finds them', () async {
    final path = await storage.write(
      byteKey: 'h1',
      name: 'plan.pdf',
      bytes: bytes('pdf-bytes'),
    );

    expect(path, endsWith('/h1/plan.pdf'));
    expect(await storage.pathForFile('h1'), path);
    expect(await storage.hasFile('h1'), isTrue);
    expect(File(path!).readAsBytesSync(), bytes('pdf-bytes'));
  });

  test('pathForFile / hasFile are null / false for an unknown entry', () async {
    expect(await storage.pathForFile('missing'), isNull);
    expect(await storage.hasFile('missing'), isFalse);
  });

  test('remove deletes the entry and is safe when already gone', () async {
    await storage.write(byteKey: 'h1', name: 'plan.pdf', bytes: bytes('x'));
    await storage.removeFile('h1');

    expect(await storage.hasFile('h1'), isFalse);
    await storage.removeFile('h1'); // no throw on a second remove
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
      byteKey: signature('old').byteKey,
      name: 'signature.png',
      bytes: bytes('old-drawing'),
    );

    expect(await storage.pathForFile(signature('new').byteKey), isNull);
    expect(await storage.hasFile(signature('old').byteKey), isTrue);
  });

  test('entries are independent — writing one never drops another', () async {
    await storage.write(byteKey: 'h1', name: 'a.pdf', bytes: bytes('a'));
    await storage.write(byteKey: 'h2', name: 'b.pdf', bytes: bytes('b'));

    expect(await storage.hasFile('h1'), isTrue);
    expect(await storage.hasFile('h2'), isTrue);

    await storage.removeFile('h1');
    expect(await storage.hasFile('h1'), isFalse);
    expect(await storage.hasFile('h2'), isTrue);
  });
}
