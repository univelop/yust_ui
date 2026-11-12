import 'package:flutter_test/flutter_test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/yust_ui.dart';

/// The displayed order of [YustFileHandler.getFiles] must only depend on the
/// file dates and [YustFileHandler.newestFirst], not on the order in which
/// the files were handed over (#8078).
void main() {
  YustImage image(String name, DateTime? createdAt) {
    final file = YustImage(name: name);
    file.createdAt = createdAt;
    return file;
  }

  final oldest = image('oldest.jpg', DateTime.utc(2026, 1, 1));
  final middle = image('middle.jpg', DateTime.utc(2026, 2, 1));
  final newest = image('newest.jpg', DateTime.utc(2026, 3, 1));
  final uploaded = image('uploaded.jpg', DateTime.utc(2026, 4, 1));

  Future<List<String?>> displayedNames({
    required bool newestFirst,
    required List<YustFile> files,
    List<YustFile> laterFiles = const [],
  }) async {
    final handler = YustFileHandler(
      storageFolderPath: 'images',
      newestFirst: newestFirst,
    );
    await handler.updateFiles(files);
    if (laterFiles.isNotEmpty) {
      await handler.updateFiles([...files, ...laterFiles]);
    }
    return handler.getFiles().map((file) => file.name).toList();
  }

  test('shows files newest first when the setting is on', () async {
    expect(
      await displayedNames(newestFirst: true, files: [middle, newest, oldest]),
      equals(['newest.jpg', 'middle.jpg', 'oldest.jpg']),
    );
  });

  test('shows files oldest first when the setting is off', () async {
    expect(
      await displayedNames(newestFirst: false, files: [middle, newest, oldest]),
      equals(['oldest.jpg', 'middle.jpg', 'newest.jpg']),
    );
  });

  test(
    'ignores the incoming order when files are already newest first',
    () async {
      expect(
        await displayedNames(
          newestFirst: true,
          files: [newest, middle, oldest],
        ),
        equals(['newest.jpg', 'middle.jpg', 'oldest.jpg']),
      );
    },
  );

  test('shows a later upload first when the setting is on', () async {
    expect(
      await displayedNames(
        newestFirst: true,
        files: [middle, newest, oldest],
        laterFiles: [uploaded],
      ),
      equals(['uploaded.jpg', 'newest.jpg', 'middle.jpg', 'oldest.jpg']),
    );
  });

  test('shows a later upload last when the setting is off', () async {
    expect(
      await displayedNames(
        newestFirst: false,
        files: [middle, newest, oldest],
        laterFiles: [uploaded],
      ),
      equals(['oldest.jpg', 'middle.jpg', 'newest.jpg', 'uploaded.jpg']),
    );
  });

  test(
    'falls back to modifiedAt and keeps undated files in their order',
    () async {
      final modifiedOnly = image('modified.jpg', null)
        ..modifiedAt = DateTime.utc(2026, 2, 15);
      final undatedA = image('undated_a.jpg', null);
      final undatedB = image('undated_b.jpg', null);

      expect(
        await displayedNames(
          newestFirst: false,
          files: [newest, undatedA, modifiedOnly, undatedB, oldest],
        ),
        equals([
          'undated_a.jpg',
          'undated_b.jpg',
          'oldest.jpg',
          'modified.jpg',
          'newest.jpg',
        ]),
      );
    },
  );
}
