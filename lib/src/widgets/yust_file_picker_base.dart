import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../util/yust_file_handler.dart';
import '../yust_ui.dart';
import 'yust_dropzone_list_tile.dart';
import 'yust_list_tile.dart';

// ignore: depend_on_referenced_packages
import 'package:flutter_dropzone_platform_interface/flutter_dropzone_platform_interface.dart';

abstract class YustFilePickerBase<T extends YustFile> extends StatefulWidget {
  final String? label;
  final List<T> files;
  final String storageFolderPath;
  final String? linkedDocPath;
  final String? linkedDocAttribute;
  final void Function(List<T> files)? onChanged;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool enableDropzone;
  final bool readOnly;
  final bool divider;
  final bool allowMultiSelectDownload;
  final bool allowMultiSelectDeletion;
  final void Function(List<T>)? onMultiSelectDownload;
  final bool wrapSuffixChild;
  final bool newestFirst;
  final bool multiple;
  final num? numberOfFiles;
  final bool overwriteSingleFile;

  /// Number of items to show initially and load more on demand. Default is 15.
  final int previewCount;

  const YustFilePickerBase({
    super.key,
    this.label,
    required this.files,
    required this.storageFolderPath,
    this.linkedDocPath,
    this.linkedDocAttribute,
    this.onChanged,
    this.prefixIcon,
    this.suffixIcon,
    this.enableDropzone = false,
    this.readOnly = false,
    this.divider = true,
    this.allowMultiSelectDownload = false,
    this.allowMultiSelectDeletion = false,
    this.onMultiSelectDownload,
    this.wrapSuffixChild = false,
    this.newestFirst = false,
    this.multiple = true,
    this.numberOfFiles,
    this.overwriteSingleFile = false,
    this.previewCount = 15,
  });
}

abstract class YustFilePickerBaseState<T extends YustFile,
        W extends YustFilePickerBase<T>> extends State<W>
    with AutomaticKeepAliveClientMixin {
  late YustFileHandler _fileHandler;
  late bool _enabled;
  bool _selecting = false;
  final List<T> _selectedFiles = [];
  late Future<void> _updateFuture;
  int currentDisplayCount = 15;

  @override
  void initState() {
    super.initState();

    _fileHandler = YustUi.fileHandlerManager.createFileHandler(
      storageFolderPath: widget.storageFolderPath,
      linkedDocAttribute: widget.linkedDocAttribute,
      linkedDocPath: widget.linkedDocPath,
      newestFirst: widget.newestFirst,
      onFileUploaded: () {
        if (mounted) {
          setState(() {});
        }
        _increaseDisplayCountIfNeeded();
        widget.onChanged!(convertFiles(_fileHandler.getOnlineFiles()));
      },
    );

    _enabled = (widget.onChanged != null && !widget.readOnly);
    currentDisplayCount = widget.previewCount;
    _updateFuture =
        _fileHandler.updateFiles(widget.files, loadFiles: shouldLoadFiles);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _enabled = widget.onChanged != null && !widget.readOnly;
    _fileHandler.newestFirst = widget.newestFirst;
    return FutureBuilder(
      future: _updateFuture,
      builder: (context, snapshot) => _buildFilePicker(context),
    );
  }

  // Abstract methods to be implemented by subclasses
  List<T> convertFiles(List<YustFile> files);
  bool get shouldLoadFiles;
  Widget buildFileDisplay(BuildContext context);
  List<Widget> buildSpecificActionButtons(BuildContext context);
  Future<void> pickFiles();

  // Shared multi-select functionality
  bool get _allSelected {
    final totalFiles = _fileHandler.getFiles().length;
    return _selectedFiles.length == totalFiles;
  }

  Widget _buildFilePicker(BuildContext context) {
    if (kIsWeb && widget.enableDropzone && _enabled && !_selecting) {
      return YustDropzoneListTile(
        suffixChild: _buildSuffixChild(context),
        label: widget.label,
        prefixIcon: widget.prefixIcon,
        below: buildFileDisplay(context),
        divider: widget.divider,
        onDropMultiple: (controller, ev) async {
          await handleDroppedFiles<DropzoneFileInterface>(ev ?? [],
              (fileData) async {
            final data = await controller.getFileData(fileData);
            return (fileData.name.toString(), null, data);
          });
        },
        wrapSuffixChild: widget.wrapSuffixChild,
      );
    } else {
      return YustListTile(
        label: widget.label,
        suffixChild: _buildSuffixChild(context),
        prefixIcon: widget.prefixIcon,
        below: buildFileDisplay(context),
        divider: widget.divider,
        wrapSuffixChild: widget.wrapSuffixChild,
      );
    }
  }

  Widget _buildSuffixChild(BuildContext context) => Wrap(
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
                ...buildSpecificActionButtons(context),
                if (widget.suffixIcon != null) widget.suffixIcon!,
              ],
      );

  Widget _buildSelectAllButton() {
    return TextButton.icon(
      onPressed: () => unawaited(_toggleSelectAll()),
      icon: Icon(_allSelected ? Icons.cancel : Icons.check_circle_outline),
      label: Text(_allSelected ? LocaleKeys.none.tr() : LocaleKeys.all.tr()),
    );
  }

  Future<void> _toggleSelectAll() async {
    if (_allSelected) {
      setState(() {
        _selectedFiles.clear();
      });
      return;
    }

    final allFiles = convertFiles(_fileHandler.getFiles());
    final hasHiddenItems = allFiles.length > currentDisplayCount;
    bool? includeHiddenItems = false;

    if (hasHiddenItems) {
      includeHiddenItems = await YustUi.alertService.showConfirmation(
        LocaleKeys.selectAll.tr(),
        LocaleKeys.all.tr(),
        description: LocaleKeys.alsoSelectHiddenFiles.tr(),
        cancelText: LocaleKeys.onlyVisibleFiles.tr(),
      );
    }

    if (includeHiddenItems == null) return;

    setState(() {
      _selectedFiles.clear();
      _selectedFiles.addAll(includeHiddenItems == true
          ? allFiles
          : allFiles.take(currentDisplayCount));
    });
  }

  Widget _buildCancelSelectionButton() {
    return TextButton(
      onPressed: _cancelSelection,
      child: Text(LocaleKeys.cancel.tr()),
    );
  }

  void _cancelSelection() {
    setState(() {
      _selecting = false;
      _selectedFiles.clear();
    });
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

  Widget _buildDownloadSelectedButton(BuildContext context) {
    return IconButton(
      color: Theme.of(context).colorScheme.primary,
      icon: const Icon(Icons.download),
      tooltip: LocaleKeys.download.tr(),
      onPressed:
          _selectedFiles.isNotEmpty && widget.onMultiSelectDownload != null
              ? () {
                  widget.onMultiSelectDownload!(List<T>.of(_selectedFiles));
                  _cancelSelection();
                }
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
    _cancelSelection();

    await EasyLoading.dismiss();
  }

  Future<void> _deleteFiles(List<T> files) async {
    for (final yustFile in files) {
      await _fileHandler.deleteFile(yustFile);

      if (mounted) {
        setState(() {});
      }
    }
    widget.onChanged!(convertFiles(_fileHandler.getOnlineFiles()));
    if (mounted) {
      setState(() {});
    }
  }

  // Shared validation methods
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
    if (widget.overwriteSingleFile && widget.files.isNotEmpty) {
      final confirmed = await YustUi.alertService.showConfirmation(
          LocaleKeys.alertConfirmOverwriteFile.tr(), LocaleKeys.continue_.tr());
      return confirmed ?? false;
    }

    return true;
  }

  Future<void> handleDroppedFiles<U>(
    List<U> fileData,
    Future<(String, File?, Uint8List?)> Function(U) fileDataExtractor,
  ) async {
    final filesValid = await checkFileAmount(fileData);
    if (!filesValid) return;

    if (widget.overwriteSingleFile) {
      await _deleteFiles(widget.files);
    }

    for (final fileData in fileData) {
      final (name, file, bytes) = await fileDataExtractor(fileData);
      await processFile(name, file, bytes);
    }
  }

  // Abstract method for file processing - to be implemented by subclasses
  Future<void> processFile(String name, File? file, Uint8List? bytes);

  Future<void> createDatabaseEntry() async {
    try {
      if (widget.linkedDocPath != null &&
          !_fileHandler.existsDocData(
              await _fileHandler.getFirebaseDoc(widget.linkedDocPath!))) {
        widget.onChanged!(convertFiles(_fileHandler.getOnlineFiles()));
      }
      // ignore: empty_catches
    } catch (e) {}
  }

  // Shared connectivity check
  Future<bool> checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none &&
        (widget.linkedDocPath == null || widget.linkedDocAttribute == null)) {
      await YustUi.alertService.showAlert(LocaleKeys.missingConnection.tr(),
          LocaleKeys.alertMissingConnectionAddImages.tr());
      return false;
    }
    return true;
  }

  // Shared indicator widgets
  Widget buildCachedIndicator(T file) {
    if (!file.cached || !_enabled) {
      return const SizedBox.shrink();
    }
    if (file.processing == true) {
      return const CircularProgressIndicator();
    }
    return IconButton(
      icon: const Icon(Icons.cloud_upload_outlined),
      color: Colors.white,
      onPressed: () async {
        await YustUi.alertService.showAlert(
            LocaleKeys.localFile.tr(), LocaleKeys.alertLocalFile.tr());
      },
    );
  }

  Widget buildSelectionCheckbox(T? file) {
    if (!_selecting || file == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 10,
      left: 10,
      child: Checkbox(
        value: _selectedFiles.contains(file),
        shape: const CircleBorder(),
        onChanged: (value) => _toggleSelectionForFile(file),
        fillColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return Theme.of(context).primaryColor;
          }
          return Colors.grey.shade300;
        }),
      ),
    );
  }

  void _toggleSelectionForFile(T file) {
    setState(() {
      if (_selectedFiles.contains(file)) {
        _selectedFiles.remove(file);
      } else {
        _selectedFiles.add(file);
      }
    });
  }

  void loadMoreItems() {
    setState(() {
      currentDisplayCount += widget.previewCount;
    });
  }

  void _increaseDisplayCountIfNeeded() {
    if (currentDisplayCount < _fileHandler.getFiles().length) {
      currentDisplayCount += widget.previewCount;
    }
  }

  // Getters for access to shared state
  YustFileHandler get fileHandler => _fileHandler;
  bool get enabled => _enabled;
  bool get selecting => _selecting;
  List<T> get selectedFiles => _selectedFiles;

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.files != widget.files) {
      _updateFuture =
          _fileHandler.updateFiles(widget.files, loadFiles: shouldLoadFiles);
      setState(() {});
    }
  }
}
