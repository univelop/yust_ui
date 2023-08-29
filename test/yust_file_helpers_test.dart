import 'package:test/test.dart';
import 'package:yust_ui/src/util/yust_file_helpers.dart';

void main() {
  group('The remove extension', () {
    test('Remove extension easy', () {
      final helper = YustFileHelpers();
      var filename = helper.removeExtension('test.html');

      expect(filename, 'test');
    });

    test('Remove extension hard', () {
      final helper = YustFileHelpers();
      var filename = helper.removeExtension('test.west.spec.html');

      expect(filename, 'test.west.spec');
    });

    test('no extension', () {
      final helper = YustFileHelpers();
      var filename = helper.removeExtension('test');

      expect(filename, 'test');
    });
  });
}
