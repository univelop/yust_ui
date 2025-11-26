import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../yust_ui.dart';
import 'yust_file_picker_base.dart';
import 'yust_file_list_view.dart';

/// A widget that allows the user to pick files from their device.
class YustFilePicker extends YustFilePickerBase<YustFile> {
  /// Whether to show the modified date of the file.
  final bool showModifiedAt;

  /// Allowed file extensions.
  final List<String>? allowedExtensions;

  /// Maximum file size in KiB.
  final num? maximumFileSizeInKiB;

  const YustFilePicker({
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
    super.numberOfFiles = YustFilePickerBase.defaultNumberOfFiles,
    super.divider = true,
    super.overwriteSingleFile = false,
    super.allowMultiSelectDownload = false,
    super.allowMultiSelectDeletion = false,
    super.onMultiSelectDownload,
    super.wrapSuffixChild = false,
    super.generateDownloadUrl,
    super.signedUrlQueryParameters,
    super.previewCount = YustFilePickerBase.defaultPreviewCount,
    this.showModifiedAt = false,
    this.allowedExtensions,
    this.maximumFileSizeInKiB,
  });

  /// A convenience constructor for a single file picker.
  const YustFilePicker.single({
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
    super.overwriteSingleFile = false,
    super.generateDownloadUrl,
    super.signedUrlQueryParameters,
    this.showModifiedAt = false,
    this.allowedExtensions,
    this.maximumFileSizeInKiB,
  }) : super(numberOfFiles: 1);

  @override
  YustFilePickerState createState() => YustFilePickerState();
}

class YustFilePickerState
    extends YustFilePickerBaseState<YustFile, YustFilePicker> {
  @override
  List<YustFile> convertFiles(List<YustFile> files) => files;

  @override
  Widget build(BuildContext context) {
    // Use build function from parent class so that shared logic can be reused.
    return super.build(context);
  }

  @override
  Widget buildFileDisplay(BuildContext context) {
    return YustFileListView<YustFile>(
      files: getVisibleFiles(),
      itemBuilder: (context, file) => _buildFile(context, file),
      loadMoreButton: buildLoadMoreButton(context),
      totalFileCount: widget.files.length,
    );
  }

  @override
  Future<void> pickFiles() async {
    YustUi.helpers.unfocusCurrent();
    final type = (widget.allowedExtensions != null)
        ? FileType.custom
        : FileType.any;
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: widget.allowedExtensions,
      allowMultiple: widget.numberOfFiles > 1,
    );
    if (result == null) return;

    await checkAndUploadFiles(
      result.files,
      (file) async =>
          (_getFileName(file), _platformFileToFile(file), file.bytes),
    );
  }

  @override
  List<Widget> buildActionButtons(BuildContext context) {
    return [_buildAddButton(context)];
  }

  @override
  Future<YustFile> processFile(
    String name,
    File? file,
    Uint8List? bytes,
  ) async {
    return YustFile(
      name: name,
      modifiedAt: Yust.helpers.utcNow(),
      file: file,
      bytes: bytes,
      storageFolderPath: widget.storageFolderPath,
      linkedDocPath: widget.linkedDocPath,
      linkedDocAttribute: widget.linkedDocAttribute,
    );
  }

  @override
  List<YustFile> sortFiles(List<YustFile> files) {
    final sortedFiles = List<YustFile>.from(files);
    sortedFiles.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
    return sortedFiles;
  }

  Widget _buildAddButton(BuildContext context) {
    final canAddMore =
        widget.files.length < widget.numberOfFiles ||
        (widget.numberOfFiles == 1 && widget.overwriteSingleFile);

    if (enabled && canAddMore) {
      return IconButton(
        tooltip: _getTooltipMessage(),
        color: Theme.of(context).colorScheme.primary,
        icon: const Icon(Icons.add_circle),
        onPressed: enabled && (widget.allowedExtensions?.isNotEmpty ?? true)
            ? pickFiles
            : null,
      );
    }

    return const SizedBox.shrink();
  }

  String? _getTooltipMessage() {
    final messages = <String>[];

    if (widget.allowedExtensions != null) {
      if (widget.allowedExtensions!.isEmpty) {
        messages.add(LocaleKeys.tooltipNoAllowedExtensions.tr());
      } else {
        messages.add(
          LocaleKeys.tooltipAllowedExtensions.tr(
            namedArgs: {
              'allowedExtensions': widget.allowedExtensions!.join(', '),
            },
          ),
        );
      }
    }

    if (widget.maximumFileSizeInKiB != null) {
      messages.add(
        LocaleKeys.tooltipMaxFileSize.tr(
          namedArgs: {
            'maxFileSize': YustUi.fileHelpers.formatFileSize(
              widget.maximumFileSizeInKiB ?? 0,
            ),
          },
        ),
      );
    }

    return messages.isEmpty ? null : messages.join('\n');
  }

  Widget _buildFile(BuildContext context, YustFile file) {
    final isBroken =
        file.name == null ||
        (file.cached &&
            file.bytes == null &&
            file.file == null &&
            file.devicePath == null) ||
        (kIsWeb && file.url == null && file.bytes == null && file.file == null);
    final shouldShowDate =
        !isBroken && widget.showModifiedAt && file.modifiedAt != null;

    return ListTile(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selecting)
            Checkbox(
              value: selectedFiles.contains(file),
              onChanged: (_) => toggleFileSelection(file),
            ),
          Icon(!isBroken ? Icons.insert_drive_file : Icons.dangerous),
          const SizedBox(width: 8),
          Expanded(
            child: shouldShowDate
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // file.name is not null because shouldShowDate == true
                      Text(file.name ?? '', overflow: TextOverflow.ellipsis),
                      Text(
                        YustHelpers().formatDate(
                          file.modifiedAt,
                          format: 'dd.MM.yyyy HH:mm',
                        ),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  )
                : Text(
                    isBroken ? LocaleKeys.brokenFile.tr() : file.name ?? '',
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          buildCachedIndicator(file),
        ],
      ),
      trailing: selecting ? null : _buildTrailing(file),
      onTap: () {
        YustUi.helpers.unfocusCurrent();

        if (selecting) {
          toggleFileSelection(file);
          return;
        }

        if (!isBroken) {
          fileHandler.showFile(context, file);
        }
      },
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: 8.0,
      ),
    );
  }

  Widget _buildTrailing(YustFile file) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _buildDownloadButton(file),
      _buildFileRenameButton(file),
      _buildDeleteButton(file),
    ],
  );

  Widget _buildDownloadButton(YustFile file) => Builder(
    builder: (buttonContext) {
      return IconButton(
        icon: (kIsWeb) ? const Icon(Icons.download) : const Icon(Icons.share),
        color: Theme.of(buttonContext).primaryColor,
        onPressed: () =>
            unawaited(_onDownloadButtonPressed(buttonContext, file)),
      );
    },
  );

  Future<void> _onDownloadButtonPressed(
    BuildContext context,
    YustFile file,
  ) async {
    if (!file.isValid()) return;

    String? url = file.url ?? '';

    if (widget.generateDownloadUrl != null) {
      url = await widget.generateDownloadUrl!(file);
    }

    if (url == null || !context.mounted) return;

    await YustUi.fileHelpers.downloadAndLaunchFile(
      context: context,
      url: url,
      name: file.name!,
    );
  }

  Widget _buildFileRenameButton(YustFile file) {
    if (!enabled) {
      return const SizedBox.shrink();
    }
    if (isFileProcessing(file)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      icon: const Icon(Icons.edit),
      color: Theme.of(context).colorScheme.primary,
      onPressed: enabled && !file.cached ? () => _renameFile(file) : null,
    );
  }

  Widget _buildDeleteButton(YustFile file) {
    if (!enabled) {
      return const SizedBox.shrink();
    }
    if (isFileProcessing(file)) {
      return const CircularProgressIndicator();
    }
    return IconButton(
      icon: const Icon(Icons.delete),
      color: Theme.of(context).colorScheme.primary,
      onPressed: enabled ? () => _deleteFileWithConfirmation(file) : null,
    );
  }

  @override
  Future<void> checkAndUploadFiles<T>(
    List<T> fileData,
    Future<(String, File?, Uint8List?)> Function(T) fileDataExtractor,
  ) async {
    final filesValid = await checkFileCount(fileData);
    if (!filesValid) return;

    if (widget.overwriteSingleFile) {
      assert(
        widget.numberOfFiles == 1,
        'overwriteSingleFile is only supported when numberOfFiles is 1.',
      );
      assert(
        widget.files.length <= 1,
        'overwriteSingleFile is only supported when there is at most '
        'one file present.',
      );
      await deleteFiles(widget.files);
    }

    for (final fileData in fileData) {
      final (name, file, bytes) = await fileDataExtractor(fileData);

      final filesExtensionsValid = await _checkFileExtension(name);
      if (!filesExtensionsValid) return;

      final existingFileNamesValid = await _checkExistingFileNames(name);
      if (!existingFileNamesValid) return;

      final fileSizeValid = await _checkFileSize(name, file, bytes);
      if (!fileSizeValid) return;

      final newFile = await processFile(name, file, bytes);
      await uploadFile(file: newFile);
    }
  }

  Future<bool> _checkFileSize(String name, File? file, Uint8List? bytes) async {
    final maxSizeKiB = widget.maximumFileSizeInKiB;
    if (maxSizeKiB == null) return true;

    final int fileSizeInKiB = file != null
        ? await file.length() ~/ 1024
        : bytes != null
        ? bytes.length ~/ 1024
        : 0;

    if (fileSizeInKiB > maxSizeKiB) {
      unawaited(
        YustUi.alertService.showAlert(
          LocaleKeys.fileUpload.tr(),
          LocaleKeys.alertFileTooBig.tr(
            namedArgs: {
              'fileName': name,
              'maxFileSize': YustUi.fileHelpers.formatFileSize(maxSizeKiB),
            },
          ),
        ),
      );
      return false;
    }
    return true;
  }

  Future<bool> _checkFileExtension<T>(String fileName) async {
    final extension = fileName.split('.').last;
    if (widget.allowedExtensions != null &&
        !widget.allowedExtensions!.contains(extension)) {
      unawaited(
        YustUi.alertService.showAlert(
          LocaleKeys.fileUpload.tr(),
          widget.allowedExtensions!.isEmpty
              ? LocaleKeys.alertNoAllowedExtensions.tr()
              : LocaleKeys.alertAllowedExtensions.tr(
                  namedArgs: {
                    'allowedExtensions': widget.allowedExtensions!.join(', '),
                  },
                ),
        ),
      );
      return false;
    }
    return true;
  }

  Future<bool> _checkExistingFileNames(String fileName) async {
    if (fileHandler.getFiles().any((file) => file.name == fileName)) {
      final confirmed = await YustUi.alertService.showConfirmation(
        LocaleKeys.alertFileAlreadyExists.tr(namedArgs: {'fileName': fileName}),
        LocaleKeys.continue_.tr(),
      );
      if (confirmed != true) return false;

      final fileToDelete = fileHandler.getFiles().firstWhere(
        (file) => file.name == fileName,
        orElse: () => YustFile(),
      );
      await fileHandler.deleteFile(fileToDelete);
    }
    return true;
  }

  bool fileExists(String? fileName) =>
      fileHandler.getFiles().any((file) => file.name == fileName);

  Future<void> _deleteFileWithConfirmation(YustFile yustFile) async {
    YustUi.helpers.unfocusCurrent();
    final confirmed = await YustUi.alertService.showConfirmation(
      LocaleKeys.confirmDelete.tr(),
      LocaleKeys.delete.tr(),
    );
    if (confirmed == true) {
      try {
        await _deleteFileAndCallOnChanged(yustFile);
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        await YustUi.alertService.showAlert(
          LocaleKeys.oops.tr(),
          LocaleKeys.alertCannotDeleteFile.tr(
            namedArgs: {'error': e.toString()},
          ),
        );
      }
    }
  }

  Future<void> _deleteFileAndCallOnChanged(YustFile yustFile) async {
    await fileHandler.deleteFile(yustFile);
    if (!yustFile.cached) {
      widget.onChanged!(fileHandler.getOnlineFiles());
    }
  }

  Future<void> _renameFile(YustFile yustFile) async {
    final newFileName = await YustUi.alertService.showTextFieldDialog(
      LocaleKeys.alertFileRename.tr(),
      '',
      LocaleKeys.save.tr(),
      initialText: yustFile.getFileNameWithoutExtension(),
      validator: (value) =>
          (_isNewFileNameValid(value, yustFile) &&
              !fileExists('$value.${yustFile.getFilenameExtension()}'))
          ? null
          : LocaleKeys.invalidFileName.tr(),
    );

    if (newFileName == null) {
      return;
    }
    setFileProcessing(yustFile);
    setState(() {});

    final newFileNameWithExtension =
        '$newFileName.${yustFile.getFilenameExtension()}';

    await _reuploadFileForRename(yustFile, newFileNameWithExtension);
    await _deleteFileAndCallOnChanged(yustFile);

    clearFileProcessing(yustFile);
    setState(() {});
  }

  Future<void> _reuploadFileForRename(
    YustFile yustFile,
    String newFileName,
  ) async {
    final bytes = await Yust.fileService.downloadFile(
      path: yustFile.storageFolderPath ?? '',
      name: yustFile.name ?? '',
    );

    final newFile = await processFile(newFileName, yustFile.file, bytes);
    await uploadFile(file: newFile);
  }

  bool _isNewFileNameValid(String? filename, YustFile oldFile) {
    return filename != null &&
        filename.isNotEmpty &&
        filename.length < 256 &&
        YustUi.fileHelpers.isValidFileName(filename);
  }

  String _getFileName(PlatformFile platformFile) {
    var name = platformFile.name.split('/').last;
    final ext = platformFile.extension;
    if (ext != null && name.split('.').last != ext) {
      name += '.$ext';
    }
    return name;
  }

  File? _platformFileToFile(PlatformFile platformFile) {
    return (!kIsWeb && platformFile.path != null)
        ? File(platformFile.path!)
        : null;
  }
}
