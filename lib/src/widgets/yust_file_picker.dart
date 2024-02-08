import 'dart:async';
import 'dart:io';

import 'package:dotted_border/dotted_border.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
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

  @Deprecated('Use [numberOfFiles] instead')
  final bool allowMultiple;

  /// When [numberOfFiles] is null, the user can upload as many files as he
  /// wants. Otherwise the user can only upload [numberOfFiles] files.
  final num? numberOfFiles;

  final bool divider;

  final List<String>? allowedExtensions;

  final bool allowOnlyImages;

  const YustFilePicker({
    super.key,
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
    this.numberOfFiles,
    this.allowedExtensions,
    this.divider = true,
    this.allowOnlyImages = false,
  });

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
        if (kIsWeb &&
            widget.enableDropzone &&
            (widget.allowedExtensions?.isNotEmpty ?? true)) {
          return _buildDropzone(context);
        } else {
          return YustListTile(
            suffixChild: Wrap(children: [
              if (widget.allowedExtensions != null) _buildInfoIcon(context),
              // ignore: deprecated_member_use_from_same_package
              if (widget.allowMultiple ||
                  (widget.numberOfFiles ?? 2) > 1 ||
                  widget.files.isEmpty)
                _buildAddButton(context)
            ]),
            label: widget.label,
            prefixIcon: widget.prefixIcon,
            below: _buildFiles(context),
            divider: widget.divider,
          );
        }
      },
    );
  }

  Widget _buildDropzone(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: _buildDropzoneArea(context),
        ),
        YustListTile(
            suffixChild: isDragging
                ? null
                : Wrap(
                    children: [
                      if (widget.allowedExtensions != null)
                        _buildInfoIcon(context),
                      _buildAddButton(context),
                    ],
                  ),
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
                    LocaleKeys.dragFilesHere.tr(),
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
    if (!_enabled) {
      return const SizedBox.shrink();
    }
    return IconButton(
      iconSize: 40,
      color: Theme.of(context).colorScheme.primary,
      icon: const Icon(Icons.add_circle),
      onPressed: _enabled && (widget.allowedExtensions?.isNotEmpty ?? true)
          ? _pickFiles
          : null,
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
      onPressed: _enabled ? () => _deleteFile(file) : null,
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

  Future<void> uploadFile({
    required String name,
    File? file,
    Uint8List? bytes,
  }) async {
    final extension = name.split('.').last;
    if (widget.allowedExtensions != null &&
        !widget.allowedExtensions!.contains(extension)) {
      unawaited(YustUi.alertService.showAlert(
          LocaleKeys.fileUpload.tr(),
          widget.allowedExtensions!.isEmpty
              ? LocaleKeys.alertNoAllowedExtensions.tr()
              : LocaleKeys.alertAllowedExtensions.tr(namedArgs: {
                  'allowedExtensions': widget.allowedExtensions!.join(', ')
                })));
      return;
    }
    final numberOfFiles = widget.numberOfFiles;
    if (numberOfFiles != null && widget.files.length >= numberOfFiles) {
      unawaited(YustUi.alertService.showAlert(
          LocaleKeys.fileUpload.tr(),
          numberOfFiles == 1
              ? LocaleKeys.alertMaxOneFile.tr()
              : LocaleKeys.alertMaxNumberFiles
                  .tr(namedArgs: {'numberFiles': numberOfFiles.toString()})));
      return;
    }
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

    if (_fileHandler.getFiles().any((file) => file.name == newYustFile.name)) {
      await YustUi.alertService.showAlert(
          LocaleKeys.notPossible.tr(),
          LocaleKeys.alertFileAlreadyExists
              .tr(namedArgs: {'fileName': newYustFile.name ?? ''}));
    } else {
      await _createDatabaseEntry();
      await _fileHandler.addFile(newYustFile);
    }
    _processing[newYustFile.name] = false;
    widget.onChanged!(_fileHandler.getOnlineFiles());
    if (mounted) {
      setState(() {});
    }
  }

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

  Future<void> _deleteFile(YustFile yustFile) async {
    YustUi.helpers.unfocusCurrent();
    final confirmed = await YustUi.alertService.showConfirmation(
        LocaleKeys.confirmDelete.tr(), LocaleKeys.delete.tr());
    if (confirmed == true) {
      try {
        await _fileHandler.deleteFile(yustFile);
        if (!yustFile.cached) {
          widget.onChanged!(_fileHandler.getOnlineFiles());
        }
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
}
