import 'package:yust/yust.dart';

/// The outcome of resolving how uploading one new file applies to an existing
/// file set.
///
/// Pure data — [resolveFileUpload] computes it and the caller decides how to
/// react (a confirm dialog for a replace/overwrite, an alert or thrown
/// exception when [exceedsLimit]).
class FileUploadDecision<T extends YustFile> {
  const FileUploadDecision({
    required this.filesToRemove,
    required this.exceedsLimit,
    required this.replacesByName,
  });

  /// Existing files to remove before adding the new one: all current files for
  /// a single-file overwrite, the files sharing the new name for a name
  /// replace, otherwise empty.
  final List<T> filesToRemove;

  /// Whether adding the file would exceed the limit and must be blocked.
  /// Already accounts for single-file overwrite, which never blocks.
  final bool exceedsLimit;

  /// Whether the new name replaces an existing same-named file. A name replace
  /// never counts against the limit.
  final bool replacesByName;
}

/// Resolves how uploading a file named [newFileName] applies to [currentFiles],
/// honouring the [numberOfFiles] limit and [overwriteSingleFile] setting.
///
/// Pure and dialog-free. Mirrors the single-file overwrite rule that previously
/// lived in `DrawingAnnotationsManager.plansToReplaceOnUpload`: a name replace
/// never counts against the limit; single-file overwrite replaces the current
/// file rather than exceeding.
FileUploadDecision<T> resolveFileUpload<T extends YustFile>({
  required List<T> currentFiles,
  required String newFileName,
  required int numberOfFiles,
  required bool overwriteSingleFile,
}) {
  final isSingleOverwrite = numberOfFiles == 1 && overwriteSingleFile;
  final replacesByName = currentFiles.any((file) => file.name == newFileName);
  final wouldExceedLimit =
      !replacesByName && currentFiles.length >= numberOfFiles;
  final exceedsLimit = wouldExceedLimit && !isSingleOverwrite;

  final filesToRemove = exceedsLimit
      ? <T>[]
      : isSingleOverwrite
      ? List<T>.of(currentFiles)
      : currentFiles.where((file) => file.name == newFileName).toList();

  return FileUploadDecision<T>(
    filesToRemove: filesToRemove,
    exceedsLimit: exceedsLimit,
    replacesByName: replacesByName,
  );
}
