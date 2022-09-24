import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:dotted_border/dotted_border.dart';
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

  final List<String?> newFiles;

  final bool showDeleteNotification;

  final void Function()? deleteNotification;

  final void Function(String)? deleteSingleNotification;

  const YustFilePicker({
    Key? key,
    this.label,
    required this.files,
    required this.storageFolderPath,
    this.linkedDocPath,
    this.linkedDocAttribute,
    this.onChanged,
    this.prefixIcon,
    this.enableDropzone = false,
    this.readOnly = false,
    this.newFiles = const [],
    this.showDeleteNotification = false,
    this.deleteNotification,
    this.deleteSingleNotification,
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
        if (kIsWeb && widget.enableDropzone) {
          return _buildDropzone(context);
        } else {
          return YustListTile(
              suffixChild: _buildAddButton(context),
              label: widget.label,
              prefixIcon: widget.prefixIcon,
              below: _buildFiles(context));
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
          suffixChild:
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            widget.showDeleteNotification && widget.newFiles.isNotEmpty
                ? _buildNotificationDelButton()
                : const SizedBox.shrink(),
            isDragging ? _buildDropzoneInterface() : _buildAddButton(context),
          ]),
          label: widget.label,
          prefixIcon: widget.prefixIcon,
          below: _buildFiles(context),
        ),
      ],
    );
  }

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
        (file.cached && file.bytes == null && file.file == null) ||
        (kIsWeb && file.url == null && file.bytes == null && file.file == null);
    final badge = widget.newFiles.contains(file.name)
            ? Padding(
                padding: const EdgeInsets.only(left: 4.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  height: 8,
                  width: 8,
                ),
              )
            : const SizedBox.shrink();
    return ListTile(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          badge,
          Icon(!isBroken ? Icons.insert_drive_file : Icons.dangerous),
          const SizedBox(width: 8),
          Expanded(
            child: Text(isBroken ? 'Fehlerhafte Datei' : file.name!,
                overflow: TextOverflow.ellipsis),
          ),
          _buildCachedIndicator(file),
        ],
      ),
      trailing: _buildDeleteButton(file),
      onTap: () {
        YustUi.helpers.unfocusCurrent();
        if (!isBroken) {
          if (widget.deleteSingleNotification != null) {
            //TODO Make sure name of file isnt null!
            widget.deleteSingleNotification!(file.name!);
          }
          _fileHandler.showFile(context, file);
        }
      },
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
    );
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
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      for (final platformFile in result.files) {
        await uploadFile(
          name: _getFileName(platformFile),
          file: _platformFileToFile(platformFile),
          bytes: platformFile.bytes,
        );
      }
      //TODO: Check if connection to server established
      widget.onChanged!(_fileHandler.getOnlineFiles());
    }
  }

  Future<void> uploadFile({
    required String name,
    File? file,
    Uint8List? bytes,
  }) async {
    final newYustFile = YustFile(
      name: name,
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
    /*TODO: Move onChanged to top when all Files are uploaded!
    if (!newYustFile.cached) {
      widget.onChanged!(_fileHandler.getOnlineFiles());
    }*/
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
          if (widget.deleteSingleNotification != null) {
            //TODO Make sure name of file isnt null!
            widget.deleteSingleNotification!(yustFile.name!);
          }
          widget.onChanged!(_fileHandler.getOnlineFiles());
        }
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        await YustUi.alertService.showAlert(
            'Ups', 'Die Datei kann nicht gelöscht werden. ${e.toString()}');
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

  Widget _buildNotificationDelButton() {
    return TextButton(
        onPressed: widget.deleteNotification, child: const Text('Gelesen'));
  }
}
