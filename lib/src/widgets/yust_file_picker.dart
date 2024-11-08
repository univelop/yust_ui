import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

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

  const YustFilePicker(
      {super.key,
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
      this.overwriteSingleFile = false});

  @override
  YustFilePickerState createState() => YustFilePickerState();
}

class YustFilePickerState extends State<YustFilePicker>
    with AutomaticKeepAliveClientMixin {
  late YustFileHandler _fileHandler;
  final Map<String?, bool> _processing = {};
  late bool _enabled;

  @override
  void initState() {
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

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    _enabled = widget.onChanged != null && !widget.readOnly;
    return FutureBuilder(
      future: _fileHandler.updateFiles(widget.files),
      builder: (context, snapshot) {
        return _buildFilePicker(context);
      },
    );
  }

  Widget _buildFilePicker(BuildContext context) {
    if (kIsWeb &&
        widget.enableDropzone &&
        _enabled &&
        (widget.allowedExtensions?.isNotEmpty ?? true)) {
      return YustDropzoneListTile(
        suffixChild: _buildSuffixChild(),
        label: widget.label,
        prefixIcon: widget.prefixIcon,
        below: _buildFiles(context),
        divider: widget.divider,
        onDropMultiple: (controller, ev) async {
          await checkAndUploadFiles(ev ?? [], (fileData) async {
            final data = await controller.getFileData(fileData);
            return (fileData.name.toString(), null, data);
          });
        },
      );
    } else {
      return YustListTile(
        suffixChild: _buildSuffixChild(),
        label: widget.label,
        prefixIcon: widget.prefixIcon,
        below: _buildFiles(context),
        divider: widget.divider,
      );
    }
  }

  Widget _buildSuffixChild() {
    return Wrap(children: [
      if (widget.allowedExtensions != null) _buildInfoIcon(context),
      _buildAddButton(context),
      if (widget.suffixIcon != null) widget.suffixIcon!
    ]);
  }

  Widget _buildInfoIcon(BuildContext context) {
    return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Tooltip(
          preferBelow: false,
          message: widget.allowedExtensions?.isEmpty ?? true
              ? LocaleKeys.tooltipNoAllowedExtensions.tr()
              : LocaleKeys.tooltipAllowedExtensions.tr(namedArgs: {
                  'allowedExtensions':
                      widget.allowedExtensions?.join(', ') ?? ''
                }),
          child: Icon(
              size: 40,
              Icons.info,
              color: Theme.of(context).colorScheme.primary),
        ));
  }

  Widget _buildAddButton(BuildContext context) {
    final canAddMore = widget.numberOfFiles != null
        ? widget.files.length < widget.numberOfFiles! ||
            (widget.numberOfFiles == 1 && widget.overwriteSingleFile)
        : true;

    if (_enabled && canAddMore) {
      return IconButton(
        iconSize: 40,
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
      trailing: _buildTrailing(file),
      onTap: () {
        YustUi.helpers.unfocusCurrent();
        if (!isBroken) {
          _fileHandler.showFile(context, file);
        }
      },
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
    await _doDeleteFile(yustFile);

    _processing[yustFile.name] = false;
    setState(() {});
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

  Future<void> _doDeleteFile(YustFile yustFile) async {
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

      await uploadFile(
        name: name,
        file: file,
        bytes: bytes,
      );
    }
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
        await _doDeleteFile(yustFile);
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
