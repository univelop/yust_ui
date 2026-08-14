import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:yust/yust.dart';
import 'package:meta/meta.dart';
import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../util/offline/file_list_controller.dart';
import '../util/offline/file_operation.dart';
import '../util/offline/offline_file_target.dart';
import '../util/yust_file_handler.dart';
import '../yust_ui.dart';
import 'yust_dropzone_list_tile.dart';
import 'yust_list_tile.dart';
import 'yust_file_picker.dart';
import 'yust_image_picker.dart';
import 'yust_file_list_view.dart';
import 'yust_file_grid_view.dart';
import 'yust_file_tap_mode.dart';

/// Base class for file pickers.
///
/// Used by the [YustFilePicker] and [YustImagePicker] widgets
/// to outsource common functionality.
abstract class YustFilePickerBase<T extends YustFile> extends StatefulWidget {
  /// Label for the file picker.
  final String? label;

  /// Files to display.
  final List<T> files;

  /// Storage folder path.
  final String storageFolderPath;

  /// Linked document path. e.g. '/records/record-123'
  final String? linkedDocPath;

  /// Linked document attribute. e.g. 'images'
  final String? linkedDocAttribute;

  /// Callback when files change, for a host that has to persist the list itself.
  ///
  /// Not called for file changes of a picker bound to a document
  /// ([linkedDocPath]): there the offline queue writes each file to that
  /// document under its own field mask, and the host sees the result through the
  /// document's stream. Persisting the whole attribute from this picker's
  /// snapshot as well would drop files another device added while this one was
  /// offline. It also still drives the non-file callbacks (enabled/disabled
  /// state, selection) as before.
  final void Function(List<T> files)? onChanged;

  /// Prefix icon.
  final Widget? prefixIcon;

  /// Suffix icon.
  final Widget? suffixIcon;

  /// Whether to enable the dropzone.
  final bool enableDropzone;

  /// Whether the file picker is read only.
  final bool readOnly;

  /// Whether to show a divider between the label and the file picker.
  final bool divider;

  /// Whether to allow multi-select download.
  final bool allowMultiSelectDownload;

  /// Whether to allow multi-select deletion.
  final bool allowMultiSelectDeletion;

  /// Whether files can be marked as favorites.
  ///
  /// When enabled, a favorite toggle is shown per file, favorites are shown
  /// first within the picker (display-only, the stored order is unchanged) and
  /// the multi-select toolbar gains a single smart favorite toggle.
  final bool allowFavorites;

  /// Callback when multi-select download is triggered.
  ///
  /// The real download functionality has to be implemented
  /// by the parent widget/application.
  final void Function(List<T>)? onMultiSelectDownload;

  /// Whether to wrap the suffix child.
  final bool wrapSuffixChild;

  /// Whether to show the newest files first.
  final bool newestFirst;

  /// Number of files to pick.
  final num numberOfFiles;

  /// Whether a single file can be overwritten.
  final bool overwriteSingleFile;

  /// Number of items to show initially and load more on demand.
  ///
  /// Default is [defaultPreviewCount].
  final int previewCount;

  /// Whether thumbnails should be created for new files and be shown for existing ones.
  ///
  /// If false, no thumbnails will be created or shown.
  final bool thumbnails;

  /// Whether the linked document stores files as a map with hash and file
  /// instead of a list e.g. array of files.
  ///
  /// This is needed for the offline upload of files.
  final bool linkedDocStoresFilesAsMap;

  /// Controls what happens when a file is tapped.
  final YustFileTapMode tapMode;

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
    this.allowFavorites = false,
    this.onMultiSelectDownload,
    this.wrapSuffixChild = false,
    this.newestFirst = false,
    this.numberOfFiles = defaultNumberOfFiles,
    this.overwriteSingleFile = false,
    this.previewCount = defaultPreviewCount,
    this.thumbnails = false,
    this.linkedDocStoresFilesAsMap = false,
    this.tapMode = YustFileTapMode.preview,
  });

  /// Default number of items to show initially and load more on demand.
  static const defaultPreviewCount = 15;

  /// Default number of files to pick.
  static const defaultNumberOfFiles = 2;

  /// Icon shown when a file IS a favorite. Single source of truth so the glyph
  /// can be swapped in one place.
  static const IconData favoriteIcon = Icons.star;

  /// Icon shown when a file is NOT a favorite.
  static const IconData notFavoriteIcon = Icons.star_border;

  /// Color of an active (favorite) star. Gold is the universal "favorite"
  /// signal; keeping it here lets the whole feature be re-tinted in one place.
  static const Color favoriteActiveColor = Colors.amber;

  /// Translucent scrim used behind favorite / action buttons that sit on top
  /// of image thumbnails, so the icon stays legible over any photo.
  static const Color thumbnailScrimColor = Colors.black54;

  /// Inset (top & right) of an overlay button on an image thumbnail.
  static const double thumbnailOverlayInset = 10;

  /// Radius of the circular scrim behind a thumbnail overlay button.
  static const double thumbnailOverlayRadius = 20;

  /// Star icon reflecting [isFavorite]. [inactiveColor] tints the non-favorite
  /// glyph (e.g. white on a dark thumbnail); the active star is always gold.
  static Icon favoriteStarIcon(bool isFavorite, {Color? inactiveColor}) => Icon(
    isFavorite ? favoriteIcon : notFavoriteIcon,
    color: isFavorite ? favoriteActiveColor : inactiveColor,
  );

  /// Tooltip for a favorite toggle reflecting [isFavorite].
  static String favoriteTooltip(bool isFavorite) => isFavorite
      ? LocaleKeys.removeFromFavorites.tr()
      : LocaleKeys.addToFavorites.tr();

  /// Non-interactive favorite marker: a disabled [IconButton] so it inherits
  /// the exact same density / padding / tap-target metrics as the checkbox and
  /// action icon buttons it sits next to, and therefore lines up with them.
  /// [onPressed] is null (not tappable); the star stays gold via [disabledColor].
  /// Used in read-only / selecting views.
  static Widget favoriteMarker() => const IconButton(
    onPressed: null,
    disabledColor: favoriteActiveColor,
    icon: Icon(favoriteIcon),
  );
}

abstract class YustFilePickerBaseState<
  T extends YustFile,
  W extends YustFilePickerBase<T>
>
    extends State<W>
    with AutomaticKeepAliveClientMixin {
  /// Legacy path: built only when [YustFilePickerBase.documentWriter] is null.
  YustFileHandler? _fileHandler;

  /// New path: built (and owned) here when a [documentWriter] is supplied.
  FileListController<T>? _controller;

  late bool _enabled;
  bool _selecting = false;
  final List<T> _selectedFiles = [];
  late Future<void> _updateFuture;
  int currentDisplayCount = YustFilePickerBase.defaultPreviewCount;
  final Map<String?, bool> _processing = {};

  @override
  void initState() {
    super.initState();

    _enabled = (widget.onChanged != null && !widget.readOnly);
    currentDisplayCount = widget.previewCount;

    final handler = YustUi.fileOperationHandler;
    if (handler != null) {
      _controller = FileListController<T>(
        handler: handler,
        target: OfflineFileTarget(
          storageFolderPath: widget.storageFolderPath,
          linkedDocPath: widget.linkedDocPath,
          linkedDocAttribute: widget.linkedDocAttribute,
          storesFilesAsMap: widget.linkedDocStoresFilesAsMap,
        ),
        newestFirst: widget.newestFirst,
        onOnlineFilesChanged: notifyFilesChanged,
      )..addListener(_onControllerChanged);
      _updateFuture = _controller!.setOnlineFiles(widget.files);
    } else {
      _fileHandler = YustUi.fileHandlerManager.createFileHandler(
        storageFolderPath: widget.storageFolderPath,
        linkedDocAttribute: widget.linkedDocAttribute,
        linkedDocPath: widget.linkedDocPath,
        newestFirst: widget.newestFirst,
        onFileUploaded: () {
          if (mounted) {
            setState(() {});
          }
          if (currentDisplayCount < _fileHandler!.getFiles().length) {
            currentDisplayCount += widget.previewCount;
          }
          widget.onChanged!(convertFiles(_fileHandler!.getOnlineFiles()));
        },
      );
      _updateFuture = _fileHandler!.updateFiles(widget.files, loadFiles: true);
    }
  }

  /// Rebuilds when the controller's file list changes (upload completes, cache
  /// resolves). The controller notifies its own [onOnlineFilesChanged] for
  /// persistence; here we only refresh the UI and grow the display window.
  void _onControllerChanged() {
    if (!mounted) return;
    if (currentDisplayCount < _controller!.files.length) {
      currentDisplayCount += widget.previewCount;
    }
    setState(() {});
  }

  /// Reports a file change to the host on the legacy path.
  ///
  /// A no-op once a [FileListController] is active: it reports after every
  /// mutation itself, and it — not this widget — knows whether the host is the
  /// one that has to persist the files (see
  /// [FileListController.onOnlineFilesChanged]).
  @nonVirtual
  void notifyFilesChanged(List<T> files) {
    if (_controller != null) return;
    widget.onChanged?.call(files);
  }

  /// All tracked files (both paths), in the source's storage order.
  List<T> get sourceFiles => _controller != null
      ? _controller!.files
      : convertFiles(_fileHandler!.getFiles());

  /// Files already persisted online (both paths).
  List<T> get sourceOnlineFiles => _controller != null
      ? _controller!.onlineFiles
      : convertFiles(_fileHandler!.getOnlineFiles());

  /// Adds and uploads [file] through whichever backend is active.
  Future<void> addSourceFile(T file) => _controller != null
      ? _controller!.add(file)
      : _fileHandler!.addFile(file);

  /// Deletes [file] through whichever backend is active.
  Future<void> deleteSourceFile(T file) => _controller != null
      ? _controller!.delete(file)
      : _fileHandler!.deleteFile(file);

  /// Replaces [file]'s bytes (e.g. a re-drawn image) and re-uploads.
  Future<void> replaceSourceFileBytes(T file, Uint8List bytes) =>
      _controller != null
      ? _controller!.replaceBytes(file, bytes)
      : _fileHandler!.updateFile(file, bytes: bytes);

  /// Renames [file] to [newName] through the controller, or null on the legacy
  /// path (the caller falls back to its own reupload flow). The controller
  /// enqueues a single rename operation instead of a download + reupload + delete.
  Future<void>? renameViaController(T file, String newName) =>
      _controller?.rename(file, newName);

  Future<void> _reconcileSourceFiles(List<T> files) => _controller != null
      ? _controller!.setOnlineFiles(files)
      : _fileHandler!.updateFiles(files, loadFiles: true);

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _enabled = widget.onChanged != null && !widget.readOnly;
    _fileHandler?.newestFirst = widget.newestFirst;
    _controller?.newestFirst = widget.newestFirst;

    return FutureBuilder(
      future: _updateFuture,
      builder: (context, snapshot) => _buildFilePicker(context),
    );
  }

  /// Get the legacy file handler. Null on the new controller-backed path;
  /// subclasses should prefer [sourceFiles] / [addSourceFile] / etc.
  YustFileHandler? get fileHandler => _fileHandler;

  /// Whether the file picker is enabled.
  bool get enabled => _enabled;

  /// Whether the file picker is selecting.
  bool get selecting => _selecting;

  /// Get the selected files.
  List<T> get selectedFiles => _selectedFiles;

  /// Convert files to the type of the file picker.
  ///
  /// This is used to convert the files to the type of the file picker.
  /// e.g. [YustImage] for [YustImagePicker] and [YustFile] for [YustFilePicker].
  @mustBeOverridden
  List<T> convertFiles(List<YustFile> files);

  /// Build the file display.
  ///
  /// This is used to build the file display.
  /// e.g. [YustFileListView] for [YustFilePicker] and [YustFileGridView] for [YustImagePicker].
  @mustBeOverridden
  Widget buildFileDisplay(BuildContext context);

  /// Build the specific action buttons.
  @mustBeOverridden
  List<Widget> buildActionButtons(BuildContext context);

  /// Open the file picker.
  @mustBeOverridden
  Future<void> pickFiles();

  /// Create a file object from the given parameters.
  ///
  /// This is used to create the appropriate file type for each picker.
  @mustBeOverridden
  Future<T> processFile(String name, File? file, Uint8List? bytes);

  /// Check and upload files.
  ///
  /// Can be overridden by subclasses to implement their own validation and upload
  /// logic that will be used for dropped files.
  @mustBeOverridden
  Future<void> checkAndUploadFiles<U>(
    List<U> fileData,
    Future<(String, File?, Uint8List?)> Function(U) fileDataExtractor,
  );

  /// Sort the files.
  List<T> sortFiles(List<T> files) => files;

  /// Whether all files are selected.
  bool get _allSelected {
    final totalFiles = sourceFiles.length;
    return _selectedFiles.length == totalFiles;
  }

  /// Get all files in the order they are displayed in (sorted, favorites
  /// first when enabled), without applying the [currentDisplayCount] limit.
  @nonVirtual
  List<T> getOrderedFiles({List<T>? files}) {
    final ordered = sortFiles(files ?? sourceFiles);
    if (widget.allowFavorites) {
      // Stable partition: favorites first, existing order kept within groups.
      return [
        ...ordered.where((file) => file.favorite),
        ...ordered.where((file) => !file.favorite),
      ];
    }
    return ordered;
  }

  /// Get the currently visible files based on how they are displayed.
  @nonVirtual
  List<T> getVisibleFiles({List<T>? files}) =>
      getOrderedFiles(files: files).take(currentDisplayCount).toList();

  /// Persists a metadata change the caller already applied to [files], then
  /// rebuilds.
  ///
  /// On the controller path each file gets its own queued update, so the write
  /// is field-masked to that file and cannot overwrite entries this device has
  /// not seen. The legacy handler has no queue, so there the whole list still
  /// goes back through [YustFilePickerBase.onChanged].
  Future<void> _persistMetadataAndRefresh(List<T> files) async {
    if (_controller != null) {
      for (final file in files) {
        await _controller!.updateMetadata(file);
      }
    } else {
      widget.onChanged?.call(sourceOnlineFiles);
    }
    if (mounted) setState(() {});
  }

  /// Toggle the favorite flag of a file and notify listeners.
  @nonVirtual
  Future<void> toggleFavorite(T file) async {
    file.favorite = !file.favorite;
    await _persistMetadataAndRefresh([file]);
  }

  /// Whether every currently selected file is already a favorite.
  bool get _allSelectedAreFavorites =>
      _selectedFiles.isNotEmpty &&
      _selectedFiles.every((file) => file.favorite);

  /// Smart toggle for the selection: if all selected files are already
  /// favorites, un-favorite them all; otherwise favorite them all.
  Future<void> _toggleFavoriteSelectedFiles() async {
    final favorite = !_allSelectedAreFavorites;
    for (final file in _selectedFiles) {
      file.favorite = favorite;
    }
    await _persistMetadataAndRefresh(_selectedFiles.toList());
  }

  /// Create a database entry for the files.
  @nonVirtual
  Future<void> createDatabaseEntry() async {
    // Controller path persists via its injected doc writer, so this
    // legacy "ensure the linked doc exists" step is a no-operation there.
    final handler = _fileHandler;
    if (handler == null) return;
    try {
      if (widget.linkedDocPath != null &&
          !handler.existsDocData(
            await handler.getFirebaseDoc(widget.linkedDocPath!),
          )) {
        widget.onChanged!(convertFiles(handler.getOnlineFiles()));
      }
      // ignore: empty_catches
    } catch (e) {}
  }

  /// Check the connectivity.
  @nonVirtual
  Future<bool> checkConnectivity() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.every((e) => e == ConnectivityResult.none) &&
        (widget.linkedDocPath == null || widget.linkedDocAttribute == null)) {
      await YustUi.alertService.showAlert(
        LocaleKeys.missingConnection.tr(),
        LocaleKeys.alertMissingConnectionAddImages.tr(),
      );
      return false;
    }
    return true;
  }

  /// Whether [file] is on this device but not yet in Storage.
  ///
  /// The controller knows this exactly — the file still has an upload operation in the
  /// queue. On the legacy path only "has a local copy" is available.
  @nonVirtual
  bool isAwaitingUpload(T file) =>
      _controller?.isPendingUpload(file) ?? file.cached;

  /// Whether [file]'s sync is timed out and waiting on the user. Always false on
  /// the legacy path, which has no queue.
  @nonVirtual
  bool hasSyncTimedOut(T file) => _controller?.isTimedOut(file) ?? false;

  /// Marker for a file the queue has not sent yet. Amber: waiting to upload,
  /// already usable locally. Red: timed out, tap to retry. Both non-blocking, and
  /// tappable because a tooltip alone is unreachable by touch.
  @nonVirtual
  Widget buildCachedIndicator(T file) {
    if (!_enabled) return const SizedBox.shrink();
    if (hasSyncTimedOut(file)) return _buildSyncFailedIndicator();
    if (!isAwaitingUpload(file)) return const SizedBox.shrink();
    return IconButton(
      icon: const Icon(Icons.warning_amber_rounded),
      color: Colors.amber,
      tooltip: LocaleKeys.alertLocalFile.tr(),
      onPressed: () => unawaited(
        YustUi.alertService.showAlert(
          LocaleKeys.localFile.tr(),
          LocaleKeys.alertLocalFile.tr(),
        ),
      ),
    );
  }

  Widget _buildSyncFailedIndicator() => IconButton(
    icon: const Icon(Icons.sync_problem),
    color: Theme.of(context).colorScheme.error,
    tooltip: LocaleKeys.alertFileSyncFailed.tr(),
    onPressed: () => unawaited(_confirmRetrySync()),
  );

  Future<void> _confirmRetrySync() async {
    final retry = await YustUi.alertService.showConfirmation(
      LocaleKeys.alertFileSyncFailed.tr(),
      LocaleKeys.retry.tr(),
    );
    if (retry == true)
      await YustUi.fileOperationHandler?.retryTimedOutOperations();
  }

  @nonVirtual
  Widget buildLoadMoreButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.surface,
        ),
        onPressed: () {
          setState(() {
            currentDisplayCount += widget.previewCount;
          });
        },
        icon: const Icon(Icons.expand_more),
        label: Text(LocaleKeys.loadMore.tr()),
      ),
    );
  }

  // Set a file as processing
  @nonVirtual
  void setFileProcessing(T? file) => _processing[file?.name] = true;

  // Check if a file is processing
  @nonVirtual
  bool isFileProcessing(T? file) => _processing[file?.name] ?? false;

  // Clear a file from processing
  @nonVirtual
  void clearFileProcessing(T? file) => _processing.remove(file?.name);

  // Upload a file
  @nonVirtual
  Future<void> uploadFile({
    required T file,
    bool callSetState = true,
  }) async {
    setFileProcessing(file);
    if (mounted && callSetState) {
      setState(() {});
    }

    try {
      await createDatabaseEntry();
      await addSourceFile(file);

      clearFileProcessing(file);
      notifyFilesChanged(sourceOnlineFiles);
      if (mounted && callSetState) {
        setState(() {});
      }
    } catch (e) {
      clearFileProcessing(file);
      if (mounted && callSetState) {
        setState(() {});
      }
      rethrow;
    }
  }

  /// Deletes all files
  @nonVirtual
  Future<void> deleteFiles(List<T> files) async {
    for (final yustFile in files) {
      await deleteSourceFile(yustFile);

      if (mounted) {
        setState(() {});
      }
    }
    notifyFilesChanged(sourceOnlineFiles);
    if (mounted) {
      setState(() {});
    }
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
          await checkAndUploadFiles<DropzoneFileInterface>(ev ?? [], (
            fileData,
          ) async {
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

  /// Build the suffix child of the YustListTile.
  ///
  /// Contains the control buttons etc
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
            // Favorite toggling is an edit action; only offer it when editable,
            // so read-only views (e.g. link bricks) show markers but no toggle.
            if (widget.allowFavorites && _enabled)
              _buildFavoriteSelectedButton(context),
          ]
        : [
            if ((widget.allowMultiSelectDownload ||
                    widget.allowMultiSelectDeletion ||
                    (widget.allowFavorites && _enabled)) &&
                sourceFiles.length > 1)
              _buildStartSelectionButton(),
            ...buildActionButtons(context),
            if (widget.suffixIcon != null) widget.suffixIcon!,
          ],
  );

  /// Build the select all button.
  Widget _buildSelectAllButton() {
    return TextButton.icon(
      onPressed: () => unawaited(_toggleSelectAll()),
      icon: Icon(_allSelected ? Icons.cancel : Icons.check_circle_outline),
      label: Text(_allSelected ? LocaleKeys.none.tr() : LocaleKeys.all.tr()),
    );
  }

  /// Toggle selection of all files.
  Future<void> _toggleSelectAll() async {
    if (_allSelected) {
      setState(() {
        _selectedFiles.clear();
      });
      return;
    }

    final allFiles = sourceFiles;
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
      if (includeHiddenItems == true) {
        _selectedFiles.addAll(allFiles);
      } else {
        // Select only the currently visible files
        _selectedFiles.addAll(getVisibleFiles(files: allFiles));
      }
    });
  }

  /// Toggle the selection of a file.
  void toggleFileSelection(T? file) {
    if (file == null) return;

    setState(() {
      if (selectedFiles.contains(file)) {
        selectedFiles.remove(file);
      } else {
        _selectedFiles.add(file);
      }
    });
  }

  /// Build the cancel selection button.
  Widget _buildCancelSelectionButton() {
    return TextButton(
      onPressed: _cancelSelection,
      child: Text(LocaleKeys.cancel.tr()),
    );
  }

  /// Cancel the selection.
  void _cancelSelection() {
    setState(() {
      _selecting = false;
      _selectedFiles.clear();
    });
  }

  /// Build the start selection button.
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

  /// Build the download selected button.
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

  /// Build the delete selected button.
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

  /// Builds the smart favorite toggle for the current selection.
  Widget _buildFavoriteSelectedButton(BuildContext context) {
    final allFavorites = _allSelectedAreFavorites;
    return IconButton(
      mouseCursor: SystemMouseCursors.click,
      icon: YustFilePickerBase.favoriteStarIcon(allFavorites),
      tooltip: YustFilePickerBase.favoriteTooltip(allFavorites),
      onPressed: _enabled && _selectedFiles.isNotEmpty
          ? () => unawaited(_toggleFavoriteSelectedFiles())
          : null,
    );
  }

  /// Delete the selected files.
  Future<void> _deleteSelectedFiles() async {
    final confirmed = await YustUi.alertService.showConfirmation(
      LocaleKeys.confirmationNeeded.tr(),
      LocaleKeys.delete.tr(),
      description: LocaleKeys.alertConfirmDeleteSelectedFiles.tr(
        namedArgs: {'count': _selectedFiles.length.toString()},
      ),
    );
    if (confirmed != true) return;

    await EasyLoading.show(status: LocaleKeys.deletingFiles.tr());

    await deleteFiles(_selectedFiles);
    _cancelSelection();

    await EasyLoading.dismiss();
  }

  Future<bool> checkFileCount(List<dynamic> fileElements) async {
    final numberOfFiles = widget.numberOfFiles;

    // Tried to upload so many files that the overall limit will be exceeded
    if (!widget.overwriteSingleFile &&
        widget.files.length + fileElements.length > numberOfFiles) {
      unawaited(
        YustUi.alertService.showAlert(
          LocaleKeys.fileUpload.tr(),
          LocaleKeys.fileLimitWillExceed.tr(
            namedArgs: {'limit': widget.numberOfFiles.toString()},
          ),
        ),
      );
      return false;
    }

    // Override is enabled and the user tries to upload more than one file /
    // more than one file is already uploaded
    if (widget.overwriteSingleFile &&
        (fileElements.length > 1 || widget.files.length > 1)) {
      unawaited(
        YustUi.alertService.showAlert(
          LocaleKeys.fileUpload.tr(),
          LocaleKeys.fileLimitWillExceed.tr(
            namedArgs: {'limit': widget.numberOfFiles.toString()},
          ),
        ),
      );
      return false;
    }

    // Upload one file when overwriting is enabled
    if (widget.overwriteSingleFile && widget.files.isNotEmpty) {
      final confirmed = await YustUi.alertService.showConfirmation(
        LocaleKeys.alertConfirmOverwriteFile.tr(),
        LocaleKeys.continue_.tr(),
      );
      return confirmed ?? false;
    }

    return true;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void didUpdateWidget(covariant W oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Compared by content, not by list identity: the host rebuilds this picker
    // with a freshly built list on every frame, so an identity check would
    // reconcile (and re-emit) on every unrelated rebuild.
    if (_filesSignature(oldWidget.files) != _filesSignature(widget.files)) {
      _updateFuture = _reconcileSourceFiles(widget.files);
      setState(() {});
    }
  }

  String _filesSignature(List<T> files) => files
      .map((file) => '${file.offlineKey}:${file.name}:${file.path}')
      .join('|');
}
