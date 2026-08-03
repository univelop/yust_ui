import 'package:test/test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/file_upload_decision.dart';

YustFile _file(String name, {String hash = ''}) =>
    YustFile(name: name, hash: hash, setCreatedAtToNow: false);

void main() {
  group('resolveFileUpload', () {
    test('empty current set: nothing to remove, no exceed, no replace', () {
      final decision = resolveFileUpload(
        currentFiles: <YustFile>[],
        newFileName: 'a.pdf',
        numberOfFiles: 5,
        overwriteSingleFile: false,
      );
      expect(decision.filesToRemove, isEmpty);
      expect(decision.exceedsLimit, isFalse);
      expect(decision.replacesByName, isFalse);
    });

    test('under limit, new name: no removals, no exceed', () {
      final decision = resolveFileUpload(
        currentFiles: [_file('a.pdf', hash: 'h1')],
        newFileName: 'b.pdf',
        numberOfFiles: 5,
        overwriteSingleFile: false,
      );
      expect(decision.filesToRemove, isEmpty);
      expect(decision.exceedsLimit, isFalse);
      expect(decision.replacesByName, isFalse);
    });

    test('same name: replaces by name, removes the same-name file, no exceed '
        'even at the limit', () {
      final decision = resolveFileUpload(
        currentFiles: [
          _file('a.pdf', hash: 'h1'),
          _file('b.pdf', hash: 'h2'),
        ],
        newFileName: 'a.pdf',
        numberOfFiles: 2, // already at the limit
        overwriteSingleFile: false,
      );
      expect(decision.replacesByName, isTrue);
      expect(decision.filesToRemove.map((f) => f.name), ['a.pdf']);
      expect(decision.exceedsLimit, isFalse);
    });

    test('at limit, new name, not single-overwrite: exceeds, no removals', () {
      final decision = resolveFileUpload(
        currentFiles: [
          _file('a.pdf', hash: 'h1'),
          _file('b.pdf', hash: 'h2'),
        ],
        newFileName: 'c.pdf',
        numberOfFiles: 2,
        overwriteSingleFile: false,
      );
      expect(decision.exceedsLimit, isTrue);
      expect(decision.filesToRemove, isEmpty);
      expect(decision.replacesByName, isFalse);
    });

    test('single-file overwrite: removes all current, never exceeds', () {
      final decision = resolveFileUpload(
        currentFiles: [_file('old.pdf', hash: 'h1')],
        newFileName: 'new.pdf',
        numberOfFiles: 1,
        overwriteSingleFile: true,
      );
      expect(decision.filesToRemove.map((f) => f.name), ['old.pdf']);
      expect(decision.exceedsLimit, isFalse);
      expect(decision.replacesByName, isFalse);
    });

    test('overwriteSingleFile ignored when numberOfFiles > 1', () {
      // Not a single-file target, so the flag does not enable overwrite: a new
      // name at the limit still blocks.
      final decision = resolveFileUpload(
        currentFiles: [
          _file('a.pdf', hash: 'h1'),
          _file('b.pdf', hash: 'h2'),
        ],
        newFileName: 'c.pdf',
        numberOfFiles: 2,
        overwriteSingleFile: true,
      );
      expect(decision.exceedsLimit, isTrue);
      expect(decision.filesToRemove, isEmpty);
    });

    test('hashless same-name file is still detected as a replace', () {
      // Legacy files created before hashing carry an empty hash; identity for
      // the replace check is the name, so it must still match.
      final decision = resolveFileUpload(
        currentFiles: [_file('a.pdf')],
        newFileName: 'a.pdf',
        numberOfFiles: 1,
        overwriteSingleFile: false,
      );
      expect(decision.replacesByName, isTrue);
      expect(decision.filesToRemove.map((f) => f.name), ['a.pdf']);
      expect(decision.exceedsLimit, isFalse);
    });
  });
}
