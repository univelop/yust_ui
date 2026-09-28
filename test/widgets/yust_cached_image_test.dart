import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/widgets/yust_cached_image.dart';

/// A 1x1 transparent PNG, so the widget has something decodable to render.
final _pngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('cached_image'));
  tearDown(() => root.deleteSync(recursive: true));

  testWidgets('renders the on-device copy when the file has no url', (
    tester,
  ) async {
    final path = '${root.path}/signature.png';
    File(path).writeAsBytesSync(_pngBytes);
    final file = YustFile(name: 'signature.png', setCreatedAtToNow: false)
      ..devicePath = path;

    await tester.pumpWidget(
      MaterialApp(home: YustCachedImage(file: file)),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(
      file.bytes,
      isNotNull,
      reason: 'the on-device copy has to be the source, not the missing url',
    );
  });

  testWidgets('falls back to the placeholder when the copy is gone', (
    tester,
  ) async {
    final file = YustFile(name: 'signature.png', setCreatedAtToNow: false)
      ..devicePath = '${root.path}/evicted.png';

    await tester.pumpWidget(
      MaterialApp(home: YustCachedImage(file: file)),
    );

    expect(find.byIcon(Icons.question_mark), findsOneWidget);
    expect(file.bytes, isNull);
  });
}
