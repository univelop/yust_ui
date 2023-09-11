import 'dart:io';

import 'package:dotted_border/dotted_border.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:yust/yust.dart';

import '../util/yust_file_handler.dart';
import '../yust_ui.dart';
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

  final bool allowMultiple;

  final bool divider;

  final List<String>? allowedExtensions;

  final bool allowOnlyImages;

  const YustFilePicker({
    Key? key,
    this.label,
    this.showModifiedAt = false,
    required this.files,
    required this.storageFolderPath,
    this.linkedDocPath,
    this.linkedDocAttribute,
    this.onChanged,
    this.prefixIcon,
    this.enableDropzone = false,
    this.readOnly = false,
    this.allowMultiple = true,
    this.allowedExtensions,
    this.divider = true,
    this.allowOnlyImages = false,
  }) : super(key: key);

  @override
  YustFilePickerState createState() => YustFilePickerState();
}

class YustFilePickerState extends State<YustFilePicker> {
  late YustFileHandler _fileHandler;
  final Map<String?, bool> _processing = {};
  late DropzoneViewController controller;
  var isDragging = false;
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
    if (kIsWeb && widget.enableDropzone) {
      return _buildDropzone(context);
    } else {
      return YustListTile(
        suffixChild: (widget.allowMultiple || widget.files.isEmpty)
            ? _buildAddButton(context)
            : null,
        label: widget.label,
        prefixIcon: widget.prefixIcon,
        below: _buildFiles(context),
        divider: widget.divider,
      );
    }
  }

  Widget _buildDropzone(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _buildDropzoneArea(context),
        ),
        YustListTile(
            suffixChild: isDragging ? null : _buildAddButton(context),
            label: widget.label,
            prefixIcon: widget.prefixIcon,
            below: _buildDropzoneInterfaceAndFiles(),
            divider: widget.divider),
      ],
    );
  }

  Widget _buildDropzoneInterfaceAndFiles() => Column(
        children: [
          if (isDragging) _buildDropzoneInterface(),
          _buildFiles(context),
        ],
      );

  /// This widget will accept files from a drag and drop interaction
  Widget _buildDropzoneArea(BuildContext context) => Builder(
        builder: (context) => DropzoneView(
          operation: DragOperation.copy,
          cursor: CursorType.grab,
          onCreated: (ctrl) => controller = ctrl,
          onLoaded: () {},
          onError: (ev) {},
          onHover: () {
            setState(() {
              isDragging = true;
            });
          },
          onLeave: () {
            setState(() {
              isDragging = false;
            });
          },
          onDrop: (ev) async {},
          onDropMultiple: (ev) async {
            setState(() {
              isDragging = false;
            });
            for (final file in ev ?? []) {
              final bytes = await controller.getFileData(file);
              await uploadFile(name: file.name, file: null, bytes: bytes);
            }
          },
        ),
      );

  /// This Widget is a visual drag and drop indicator. It shows a dotted box, an icon as well as a button to manually upload files
  Widget _buildDropzoneInterface() {
    final dropZoneColor =
        isDragging ? Colors.blue : const Color.fromARGB(255, 116, 116, 116);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(100, 2, 2, 2),
        child: DottedBorder(
          borderType: BorderType.RRect,
          radius: const Radius.circular(12),
          padding: const EdgeInsets.all(6),
          dashPattern: const [6, 5],
          strokeWidth: 3,
          strokeCap: StrokeCap.round,
          color: dropZoneColor,
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            child: SizedBox(
              height: 200,
              width: 400,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Icon(Icons.cloud_upload_outlined,
                      size: 35, color: dropZoneColor),
                  Text(
                    'Datei(en) hierher ziehen',
                    style: TextStyle(fontSize: 20, color: dropZoneColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    if (!_enabled) {
      return const SizedBox.shrink();
    }
    return IconButton(
      iconSize: 40,
      icon:
          Icon(Icons.add_circle, color: Theme.of(context).colorScheme.primary),
      onPressed: _enabled ? _pickFiles : null,
    );
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
                : Text(isBroken ? 'Fehlerhafte Datei' : file.name!,
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
                !fileExists(
                    '$value.${yustFile.getFilenameExtension()}'))
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
        await YustUi.alertService.showAlert('Lokal gespeicherte Datei',
            'Diese Datei ist noch nicht hochgeladen.');
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
      allowedExtensions:
          (widget.allowedExtensions != null) ? widget.allowedExtensions : null,
      allowMultiple: widget.allowMultiple,
    );
    if (result != null) {
      for (final platformFile in result.files) {
        await uploadFile(
          name: _getFileName(platformFile),
          file: _platformFileToFile(platformFile),
          bytes: platformFile.bytes,
        );
      }
    }
  }

  Future<void> uploadFile(
      {required String name,
      File? file,
      Uint8List? bytes,
      callSetState = true}) async {
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

    if (fileExists(newYustFile.name)) {
      await YustUi.alertService.showAlert('Nicht möglich',
          'Eine Datei mit dem Namen ${newYustFile.name} existiert bereits.');
    } else {
      await _createDatabaseEntry();
      await _fileHandler.addFile(newYustFile);
    }
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
    final confirmed = await YustUi.alertService
        .showConfirmation('Wirklich löschen?', 'Löschen');
    if (confirmed == true) {
      try {
        await _doDeleteFile(yustFile);
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        await YustUi.alertService
            .showAlert('Ups', 'Die Datei kann nicht gelöscht werden. $e');
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
}
