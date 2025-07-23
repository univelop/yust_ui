import 'yust_file_picker.dart';

/// A widget that allows the user to pick a single file.
///
/// This is a convenience widget that wraps [YustFilePicker] with single file defaults:
class YustSingleFilePicker extends YustFilePicker {
  const YustSingleFilePicker({
    super.key,
    super.label,
    required super.files,
    required super.storageFolderPath,
    super.linkedDocPath,
    super.linkedDocAttribute,
    super.onChanged,
    super.suffixIcon,
    super.prefixIcon,
    super.enableDropzone = false,
    super.readOnly = false,
    super.divider = true,
    super.wrapSuffixChild = false,
    super.showModifiedAt = false,
    super.allowedExtensions,
    super.maximumFileSizeInKiB,
    super.overwriteSingleFile = false,
  }) : super(
          numberOfFiles: 1,
        );
}
