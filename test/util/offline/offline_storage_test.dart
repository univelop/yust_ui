import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
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
      hash: 'h1',
      name: 'plan.pdf',
      bytes: bytes('pdf-bytes'),
    );

    expect(path, endsWith('/h1/plan.pdf'));
    expect(await storage.resolvePath('h1'), path);
    expect(await storage.exists('h1'), isTrue);
    expect(File(path).readAsBytesSync(), bytes('pdf-bytes'));
  });

  test('resolvePath / exists are null / false for an unknown entry', () async {
    expect(await storage.resolvePath('missing'), isNull);
    expect(await storage.exists('missing'), isFalse);
  });

  test('remove deletes the entry and is safe when already gone', () async {
    await storage.write(hash: 'h1', name: 'plan.pdf', bytes: bytes('x'));
    await storage.remove('h1');

    expect(await storage.exists('h1'), isFalse);
    await storage.remove('h1'); // no throw on a second remove
  });

  test('entries are independent — writing one never drops another', () async {
    await storage.write(hash: 'h1', name: 'a.pdf', bytes: bytes('a'));
    await storage.write(hash: 'h2', name: 'b.pdf', bytes: bytes('b'));

    expect(await storage.exists('h1'), isTrue);
    expect(await storage.exists('h2'), isTrue);

    await storage.remove('h1');
    expect(await storage.exists('h1'), isFalse);
    expect(await storage.exists('h2'), isTrue);
  });
}
