import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/widgets/yust_drop_zone.dart';

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
        if (kIsWeb &&
            widget.enableDropzone &&
            (widget.allowedExtensions?.isNotEmpty ?? true)) {
          return YustDropZone(
            onDrop: (f) async {
              await uploadFile(
                  name: f.name ?? 'Unkown File', file: null, bytes: f.bytes);
            },
            suffixChild: Wrap(
              children: [
                if (widget.allowedExtensions != null) _buildInfoIcon(context),
                _buildAddButton(context),
              ],
            ),
            divider: widget.divider,
            label: widget.label,
            prefixIcon: widget.prefixIcon,
            child: _buildFiles(),
          );
        } else {
          return YustListTile(
            suffixChild: Wrap(children: [
              if (widget.allowedExtensions != null) _buildInfoIcon(context),
              if (widget.allowMultiple || widget.files.isEmpty)
                _buildAddButton(context)
            ]),
            label: widget.label,
            prefixIcon: widget.prefixIcon,
            below: _buildFiles(),
            divider: widget.divider,
          );
        }
      },
    );
  }

  Widget _buildInfoIcon(BuildContext context) {
    return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Tooltip(
          preferBelow: false,
          message: widget.allowedExtensions?.isEmpty ?? true
              ? 'Es sind keine Dateiendugen erlaubt.'
              : 'Erlaubte Dateiendungen:\n'
                  '${widget.allowedExtensions!.join(', ')}',
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

  Widget _buildFiles() {
    var files = _fileHandler.getFiles();
    files.sort((a, b) => (a.name!).compareTo(b.name!));
    return Column(
      children: files.map((file) => _buildFile(file)).toList(),
    );
  }

  Widget _buildFile(YustFile file) {
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
          _fileHandler.showFile(file);
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
      allowedExtensions: widget.allowedExtensions,
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

  Future<void> uploadFile({
    required String name,
    File? file,
    Uint8List? bytes,
  }) async {
    final extension = name.split('.').last;
    if (widget.allowedExtensions != null &&
        !widget.allowedExtensions!.contains(extension)) {
      unawaited(YustUi.alertService.showAlert(
          'File Upload',
          widget.allowedExtensions!.isEmpty
              ? 'Es sind keine Dateiendungen zum Upload erlaubt.'
              : 'Es sind nur die folgenden Dateiendungen erlaubt:\n'
                  '${widget.allowedExtensions!.join(', ')}'));
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
      await YustUi.alertService.showAlert('Nicht möglich',
          'Eine Datei mit dem Namen ${newYustFile.name} existiert bereits.');
    } else {
      await _createDatebaseEntry();
      await _fileHandler.addFile(newYustFile);
    }
    _processing[newYustFile.name] = false;
    widget.onChanged!(_fileHandler.getOnlineFiles());
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _createDatebaseEntry() async {
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
    final confirmed = await YustUi.alertService
        .showConfirmation('Wirklich löschen?', 'Löschen');
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
