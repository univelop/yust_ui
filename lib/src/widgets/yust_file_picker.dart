import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:yust/yust.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_dropzone_platform_interface/flutter_dropzone_platform_interface.dart';
import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../util/yust_file_handler.dart';
import '../yust_ui.dart';
import 'yust_dropzone_list_tile.dart';
import 'yust_list_tile.dart';

class YustFilePicker extends StatefulWidget {
  final String? label;

  final List<YustFile> files;

  /// Path to folder where the files are stored.
  final String storageFolderPath;

  /// [linkedDocPath] and [linkedDocAttribute] are needed for the offline compatibility.
  /// If not given, uploads are only possible with internet connection
  final String? linkedDocPath;

  /// [linkedDocPath] and [linkedDocAttribute] are needed for the offline compatibility.
  /// If not given, uploads are only possible with internet connection
  final String? linkedDocAttribute;

  final void Function(List<YustFile> files)? onChanged;

  final Widget? prefixIcon;

  final bool enableDropzone;

  final bool readOnly;

  final bool showModifiedAt;

  @Deprecated('Use [numberOfFiles] instead')
  final bool allowMultiple;

  /// When [numberOfFiles] is null, the user can upload as many files as he
  /// wants. Otherwise the user can only upload [numberOfFiles] files.
  final num? numberOfFiles;

  final bool divider;

  final List<String>? allowedExtensions;

  final bool allowOnlyImages;

  final Widget? suffixIcon;

  final bool overwriteSingleFile;

  /// Maximum size of each file in kibibytes.
  ///
  /// NULL means no limit.
  final num? maximumFileSizeInKiB;

  /// Whether to allow multiple files to be downloaded at once.
  ///
  /// Defaults to false.
  final bool allowMultiSelectDownload;

  /// Whether to allow multiple files to be deleted at once.
  ///
  /// Defaults to false.
  final bool allowMultiSelectDeletion;

  /// Callback for multi-select download.
  /// Called when the user selects multiple files and clicks the download button.
  final void Function(List<YustFile>)? onMultiSelectDownload;

  const YustFilePicker({
    super.key,
    this.label,
    this.showModifiedAt = false,
    required this.files,
    required this.storageFolderPath,
    this.linkedDocPath,
    this.linkedDocAttribute,
    this.onChanged,
    this.suffixIcon,
    this.prefixIcon,
    this.enableDropzone = false,
    this.readOnly = false,
    this.allowMultiple = true,
    this.numberOfFiles,
    this.allowedExtensions,
    this.divider = true,
    this.allowOnlyImages = false,
    this.overwriteSingleFile = false,
    this.maximumFileSizeInKiB,
    this.allowMultiSelectDownload = false,
    this.allowMultiSelectDeletion = false,
    this.onMultiSelectDownload,
  });

  @override
  YustFilePickerState createState() => YustFilePickerState();
}

class YustFilePickerState extends State<YustFilePicker>
    with AutomaticKeepAliveClientMixin {
  late YustFileHandler _fileHandler;
  final Map<String?, bool> _processing = {};
  late bool _enabled;
  bool _selecting = false;
  final List<YustFile> _selectedFiles = [];
  late Future<void> _updateFuture;

  @override
  void initState() {
    super.initState();

    _fileHandler = YustUi.fileHandlerManager.createFileHandler(
      storageFolderPath: widget.storageFolderPath,
      linkedDocAttribute: widget.linkedDocAttribute,
      linkedDocPath: widget.linkedDocPath,
      onFileUploaded: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
    _enabled = (widget.onChanged != null && !widget.readOnly);

    _updateFuture = _fileHandler.updateFiles(widget.files);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _enabled = widget.onChanged != null && !widget.readOnly;
    return FutureBuilder(
      future: _updateFuture,
      builder: (context, snapshot) {
        return _buildFilePicker(context);
      },
    );
  }

  bool get _allSelected =>
      _selectedFiles.length == _fileHandler.getFiles().length;

  Widget _buildFilePicker(BuildContext context) {
    if (kIsWeb &&
        widget.enableDropzone &&
        _enabled &&
        (widget.allowedExtensions?.isNotEmpty ?? true) &&
        !_selecting) {
      return YustDropzoneListTile(
        suffixChild: _buildSuffixChild(),
        label: widget.label,
        prefixIcon: widget.prefixIcon,
        below: _buildFiles(context),
        divider: widget.divider,
        onDropMultiple: (controller, ev) async {
          await checkAndUploadFiles<DropzoneFileInterface>(ev ?? [],
              (fileData) async {
            final data = await controller.getFileData(fileData);
            return (fileData.name.toString(), null, data);
          });
        },
        responsiveSuffixChild: true,
      );
    } else {
      return YustListTile(
        suffixChild: _buildSuffixChild(),
        label: widget.label,
        prefixIcon: widget.prefixIcon,
        below: _buildFiles(context),
        divider: widget.divider,
        responsiveSuffixChild: true,
      );
    }
  }

  Widget _buildSuffixChild() => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: _selecting
            ? [
                _buildSelectAllButton(),
                _buildCancelSelectionButton(),
                if (widget.allowMultiSelectDownload)
                  _buildDownloadSelectedButton(context),
                if (widget.allowMultiSelectDeletion)
                  _buildDeleteSelectedButton(context),
              ]
            : [
                if ((widget.allowMultiSelectDownload ||
                        widget.allowMultiSelectDeletion) &&
                    _fileHandler.getFiles().length > 1)
                  _buildStartSelectionButton(),
                _buildAddButton(context),
                if (widget.suffixIcon != null) widget.suffixIcon!,
              ],
      );

  Widget _buildDownloadSelectedButton(BuildContext context) {
    return IconButton(
      color: Theme.of(context).colorScheme.primary,
      icon: const Icon(Icons.download),
      tooltip: LocaleKeys.download.tr(),
      onPressed:
          _selectedFiles.isNotEmpty && widget.onMultiSelectDownload != null
              ? () => widget.onMultiSelectDownload!(_selectedFiles)
              : null,
    );
  }

  Widget _buildDeleteSelectedButton(BuildContext context) {
    return IconButton(
      color: Theme.of(context).colorScheme.primary,
      icon: const Icon(Icons.delete),
      tooltip: LocaleKeys.delete.tr(),
      onPressed: _enabled && _selectedFiles.isNotEmpty
          ? () => unawaited(_deleteSelectedFiles())
          : null,
    );
  }

  String? _getTooltipMessage() {
    final messages = <String>[];

    if (widget.allowedExtensions != null) {
      if (widget.allowedExtensions!.isEmpty) {
        messages.add(LocaleKeys.tooltipNoAllowedExtensions.tr());
      } else {
        messages.add(LocaleKeys.tooltipAllowedExtensions.tr(namedArgs: {
          'allowedExtensions': widget.allowedExtensions!.join(', ')
        }));
      }
    }

    if (widget.maximumFileSizeInKiB != null) {
      messages.add(LocaleKeys.tooltipMaxFileSize.tr(namedArgs: {
        'maxFileSize':
            YustUi.fileHelpers.formatFileSize(widget.maximumFileSizeInKiB ?? 0)
      }));
    }

    return messages.isEmpty ? null : messages.join('\n');
  }

  Widget _buildSelectAllButton() {
    return TextButton.icon(
      onPressed: () {
        setState(() {
          if (_allSelected) {
            _selectedFiles.clear();
          } else {
            _selectedFiles.clear();
            _selectedFiles.addAll(_fileHandler.getFiles());
          }
        });
      },
      icon: Icon(_allSelected ? Icons.cancel : Icons.check_circle_outline),
      label: Text(_allSelected ? LocaleKeys.none.tr() : LocaleKeys.all.tr()),
    );
  }

  Widget _buildStartSelectionButton() {
    return TextButton(
      onPressed: () {
        setState(() {
          _selecting = true;
        });
      },
      child: Text(LocaleKeys.select.tr()),
    );
  }

  Widget _buildCancelSelectionButton() {
    return TextButton(
      onPressed: () {
        setState(() {
          _selecting = false;
          _selectedFiles.clear();
        });
      },
      child: Text(LocaleKeys.cancel.tr()),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    final canAddMore = widget.numberOfFiles != null
        ? widget.files.length < widget.numberOfFiles! ||
            (widget.numberOfFiles == 1 && widget.overwriteSingleFile)
        : true;

    if (_enabled && canAddMore) {
      return IconButton(
        tooltip: _getTooltipMessage(),
        color: Theme.of(context).colorScheme.primary,
        icon: const Icon(Icons.add_circle),
        onPressed: _enabled && (widget.allowedExtensions?.isNotEmpty ?? true)
            ? _pickFiles
            : null,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildFiles(BuildContext context) {
    var files = _fileHandler.getFiles();
    files.sort((a, b) => (a.name!).compareTo(b.name!));
    return Column(
      children: files.map((file) => _buildFile(context, file)).toList(),
    );
  }

  Widget _buildFile(BuildContext context, YustFile file) {
    final isBroken = file.name == null ||
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
          if (_selecting)
            Checkbox(
                value: _selectedFiles.contains(file),
                onChanged: (_) => _toggleFileSelection(file)),
          Icon(!isBroken ? Icons.insert_drive_file : Icons.dangerous),
          const SizedBox(width: 8),
          Expanded(
            child: shouldShowDate
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        // file.name is not null because shouldShowDate == true
                        Text(file.name!, overflow: TextOverflow.ellipsis),
                        Text(
                          YustHelpers().formatDate(file.modifiedAt,
                              format: 'dd.MM.yyyy HH:mm'),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ])
                : Text(isBroken ? LocaleKeys.brokenFile.tr() : file.name!,
                    overflow: TextOverflow.ellipsis),
          ),
          _buildCachedIndicator(file),
        ],
      ),
      trailing: _selecting ? null : _buildTrailing(file),
      onTap: () {
        YustUi.helpers.unfocusCurrent();

        if (_selecting) {
          _toggleFileSelection(file);
          return;
        }

        if (!isBroken) {
          _fileHandler.showFile(context, file);
        }
      },
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    );
  }

  void _toggleFileSelection(YustFile file) {
    setState(() {
      if (_selectedFiles.contains(file)) {
        _selectedFiles.remove(file);
      } else {
        _selectedFiles.add(file);
      }
    });
  }

  Widget _buildTrailing(YustFile file) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildDownloadButton(file),
          _buildFileRenameButton(file),
          _buildDeleteButton(file),
        ],
      );

  Widget _buildDownloadButton(YustFile file) => IconButton(
        icon: (kIsWeb) ? const Icon(Icons.download) : const Icon(Icons.share),
        color: Theme.of(context).primaryColor,
        onPressed: () async {
          if (file.isValid()) {
            await YustUi.fileHelpers.downloadAndLaunchFile(
                context: context, url: file.url!, name: file.name!);
          }
        },
      );

  Widget _buildFileRenameButton(YustFile file) {
    if (!_enabled) {
      return const SizedBox.shrink();
    }
    if (_processing[file.name] == true) {
      return const SizedBox.shrink();
    }
    return IconButton(
      icon: const Icon(Icons.edit),
      color: Theme.of(context).colorScheme.primary,
      onPressed: _enabled ? () => _renameFile(file) : null,
    );
  }

  Future<void> _renameFile(YustFile yustFile) async {
    final newFileName = await YustUi.alertService.showTextFieldDialog(
        'Wie soll die Datei heißen?', '', 'Speichern',
        initialText: yustFile.getFileNameWithoutExtension(),
        validator: (value) => (_isNewFileNameValid(value, yustFile) &&
                !fileExists('$value.${yustFile.getFilenameExtension()}'))
            ? null
            : 'Der Dateiname ist nicht valide!');

    if (newFileName == null) {
      return;
    }
    _processing[yustFile.name] = true;
    setState(() {});

    final newFileNameWithExtension =
        '$newFileName.${yustFile.getFilenameExtension()}';

    await _reuploadFileForRename(yustFile, newFileNameWithExtension);
    await _deleteFileAndCallOnChanged(yustFile);

    _processing[yustFile.name] = false;
    setState(() {});
  }

  Future<void> _deleteSelectedFiles() async {
    final confirmed = await YustUi.alertService.showConfirmation(
      LocaleKeys.confirmationNeeded.tr(),
      LocaleKeys.delete.tr(),
      description: LocaleKeys.alertConfirmDeleteSelectedFiles
          .tr(namedArgs: {'count': _selectedFiles.length.toString()}),
    );
    if (confirmed != true) return;

    await EasyLoading.show(status: LocaleKeys.deletingFiles.tr());

    await _deleteFiles(_selectedFiles);

    setState(() {
      _selectedFiles.clear();
    });

    await EasyLoading.dismiss();

    if (_fileHandler.getFiles().isEmpty) {
      setState(() {
        _selecting = false;
      });
    }
  }

  Future<void> _reuploadFileForRename(
      YustFile yustFile, String newFileName) async {
    final bytes = await Yust.fileService.downloadFile(
        path: yustFile.storageFolderPath ?? '', name: yustFile.name ?? '');
    await uploadFile(
      name: newFileName,
      file: yustFile.file,
      bytes: bytes,
      callSetState: false,
    );
  }

  Future<void> _deleteFileAndCallOnChanged(YustFile yustFile) async {
    await _fileHandler.deleteFile(yustFile);
    if (!yustFile.cached) {
      widget.onChanged!(_fileHandler.getOnlineFiles());
    }
  }

  bool _isNewFileNameValid(String? filename, YustFile oldFile) {
    return filename != null &&
        filename.isNotEmpty &&
        filename.length < 256 &&
        YustUi.fileHelpers.isValidFileName(filename);
  }

  Widget _buildDeleteButton(YustFile file) {
    if (!_enabled) {
      return const SizedBox.shrink();
    }
    if (_processing[file.name] == true) {
      return const CircularProgressIndicator();
    }
    return IconButton(
      icon: const Icon(Icons.delete),
      color: Theme.of(context).colorScheme.primary,
      onPressed: _enabled ? () => _deleteFileWithConfirmation(file) : null,
    );
  }

  Widget _buildCachedIndicator(YustFile file) {
    if (!file.cached || !_enabled) {
      return const SizedBox.shrink();
    }
    if (file.processing == true) {
      return const CircularProgressIndicator();
    }
    return IconButton(
      icon: const Icon(Icons.cloud_upload_outlined),
      color: Colors.black,
      onPressed: () async {
        await YustUi.alertService.showAlert(
            LocaleKeys.localFile.tr(), LocaleKeys.alertLocalFile.tr());
      },
    );
  }

  Future<void> _pickFiles() async {
    YustUi.helpers.unfocusCurrent();
    final type = (widget.allowedExtensions != null)
        ? FileType.custom
        : (widget.allowOnlyImages ? FileType.image : FileType.any);
    final result = await FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: widget.allowedExtensions,
      allowMultiple: (widget.numberOfFiles ?? 2) > 1,
    );
    if (result == null) return;

    await checkAndUploadFiles(
      result.files,
      (file) async =>
          (_getFileName(file), _platformFileToFile(file), file.bytes),
    );
  }

  Future<void> checkAndUploadFiles<T>(List<T> fileData,
      Future<(String, File?, Uint8List?)> Function(T) fileDataExtractor) async {
    final filesValid = await checkFileAmount(fileData);
    if (!filesValid) return;

    if (widget.overwriteSingleFile) {
      assert(widget.numberOfFiles == 1,
          'overwriteSingleFile is only supported when numberOfFiles is 1.');
      assert(
          widget.files.length <= 1,
          'overwriteSingleFile is only supported when there is at most '
          'one file present.');
      await _deleteFiles(widget.files);
    }

    for (final fileData in fileData) {
      final (name, file, bytes) = await fileDataExtractor(fileData);

      final filesExtensionsValid = await checkFileExtension(name);
      if (!filesExtensionsValid) return;

      final existingFileNamesValid = await _checkExistingFileNames(name);
      if (!existingFileNamesValid) return;

      final fileSizeValid = await _checkFileSize(name, file, bytes);
      if (!fileSizeValid) return;

      await uploadFile(
        name: name,
        file: file,
        bytes: bytes,
      );
    }
  }

  Future<bool> _checkFileSize(String name, File? file, Uint8List? bytes) async {
    final maxSizeKiB = widget.maximumFileSizeInKiB;
    // No restriction on file size
    if (maxSizeKiB == null) return true;

    final int fileSizeInKiB = file != null
        ? await file.length() ~/ 1024
        : bytes != null
            ? bytes.length ~/ 1024
            : 0;

    if (fileSizeInKiB > maxSizeKiB) {
      unawaited(YustUi.alertService.showAlert(
        LocaleKeys.fileUpload.tr(),
        LocaleKeys.alertFileTooBig.tr(namedArgs: {
          'fileName': name,
          'maxFileSize': YustUi.fileHelpers.formatFileSize(maxSizeKiB)
        }),
      ));
      return false;
    }
    return true;
  }

  Future<bool> checkFileAmount(List<dynamic> fileElements) async {
    final numberOfFiles = widget.numberOfFiles;
    // No restriction on file count
    if (numberOfFiles == null) return true;

    // Tried to upload so many files that the overall limit will be exceeded
    if (!widget.overwriteSingleFile &&
        widget.files.length + fileElements.length > numberOfFiles) {
      unawaited(YustUi.alertService.showAlert(
        LocaleKeys.fileUpload.tr(),
        LocaleKeys.fileLimitWillExceed
            .tr(namedArgs: {'limit': widget.numberOfFiles.toString()}),
      ));
      return false;
    }

    // Override is enabled and the user tries to upload more than one file /
    // more than one file is already uploaded
    if (widget.overwriteSingleFile &&
        (fileElements.length > 1 || widget.files.length > 1)) {
      unawaited(YustUi.alertService.showAlert(
        LocaleKeys.fileUpload.tr(),
        LocaleKeys.fileLimitWillExceed
            .tr(namedArgs: {'limit': widget.numberOfFiles.toString()}),
      ));
      return false;
    }

    // Upload one file when overwriting is enabled
    // (We know the user also has only uploaded one file, because otherwise the
    // limit would be exceeded)
    if (widget.overwriteSingleFile && widget.files.isNotEmpty) {
      final confirmed = await YustUi.alertService.showConfirmation(
          LocaleKeys.alertConfirmOverwriteFile.tr(), LocaleKeys.continue_.tr());
      return confirmed ?? false;
    }

    return true;
  }

  Future<bool> checkFileExtension<T>(String fileName) async {
    final extension = fileName.split('.').last;
    if (widget.allowedExtensions != null &&
        !widget.allowedExtensions!.contains(extension)) {
      unawaited(YustUi.alertService.showAlert(
          LocaleKeys.fileUpload.tr(),
          widget.allowedExtensions!.isEmpty
              ? LocaleKeys.alertNoAllowedExtensions.tr()
              : LocaleKeys.alertAllowedExtensions.tr(namedArgs: {
                  'allowedExtensions': widget.allowedExtensions!.join(', ')
                })));
      return false;
    }
    return true;
  }

  Future<bool> _checkExistingFileNames(String fileName) async {
    if (_fileHandler.getFiles().any((file) => file.name == fileName)) {
      final confirmed = await YustUi.alertService.showConfirmation(
          LocaleKeys.alertFileAlreadyExists
              .tr(namedArgs: {'fileName': fileName}),
          LocaleKeys.continue_.tr());
      if (confirmed == false) return false;

      final fileToDelete = _fileHandler.getFiles().firstWhere(
          (file) => file.name == fileName,
          orElse: () => YustFile());
      await _fileHandler.deleteFile(fileToDelete);
    }
    return true;
  }

  Future<void> _deleteFiles(List<YustFile> files) async {
    for (final yustFile in files) {
      await _fileHandler.deleteFile(yustFile);

      if (mounted) {
        setState(() {});
      }
    }
    widget.onChanged!(_fileHandler.getOnlineFiles());
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> uploadFile({
    required String name,
    File? file,
    Uint8List? bytes,
    callSetState = true,
  }) async {
    final newYustFile = YustFile(
      name: name,
      modifiedAt: Yust.helpers.utcNow(),
      file: file,
      bytes: bytes,
      storageFolderPath: widget.storageFolderPath,
      linkedDocPath: widget.linkedDocPath,
      linkedDocAttribute: widget.linkedDocAttribute,
    );
    _processing[newYustFile.name] = true;
    if (mounted && callSetState) {
      setState(() {});
    }

    await _createDatabaseEntry();
    await _fileHandler.addFile(newYustFile);

    _processing[newYustFile.name] = false;
    widget.onChanged!(_fileHandler.getOnlineFiles());
    if (mounted && callSetState) {
      setState(() {});
    }
  }

  bool fileExists(String? fileName) =>
      _fileHandler.getFiles().any((file) => file.name == fileName);

  Future<void> _createDatabaseEntry() async {
    try {
      if (widget.linkedDocPath != null &&
          !_fileHandler.existsDocData(
              await _fileHandler.getFirebaseDoc(widget.linkedDocPath!))) {
        widget.onChanged!(_fileHandler.getOnlineFiles());
      }
      // ignore: empty_catches
    } catch (e) {}
  }

  Future<void> _deleteFileWithConfirmation(YustFile yustFile) async {
    YustUi.helpers.unfocusCurrent();
    final confirmed = await YustUi.alertService.showConfirmation(
        LocaleKeys.confirmDelete.tr(), LocaleKeys.delete.tr());
    if (confirmed == true) {
      try {
        await _deleteFileAndCallOnChanged(yustFile);
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        await YustUi.alertService.showAlert(
            LocaleKeys.oops.tr(),
            LocaleKeys.alertCannotDeleteFile
                .tr(namedArgs: {'error': e.toString()}));
      }
    }
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

  @override
  bool get wantKeepAlive => true;
}
