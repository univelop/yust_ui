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

  /// Callback when files change.
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

  /// Validation options for file picking.
  final YustFileValidationOptions validationOptions;

  /// Number of files to pick.
  num get numberOfFiles => validationOptions.numberOfFiles;

  /// Whether a single file can be overwritten.
  bool get overwriteSingleFile => validationOptions.overwriteSingleFile;

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
    this.validationOptions = const YustFileValidationOptions(
      numberOfFiles: defaultNumberOfFiles,
    ),
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
  late YustFileHandler _fileHandler;
  late bool _enabled;
  bool _selecting = false;
  final List<T> _selectedFiles = [];
  late Future<void> _updateFuture;
  int currentDisplayCount = YustFilePickerBase.defaultPreviewCount;
  final Map<String?, bool> _processing = {};

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
        if (currentDisplayCount < _fileHandler.getFiles().length) {
          currentDisplayCount += widget.previewCount;
        }
        widget.onChanged!(convertFiles(_fileHandler.getOnlineFiles()));
      },
    );

    _enabled = (widget.onChanged != null && !widget.readOnly);
    currentDisplayCount = widget.previewCount;
    _updateFuture = _fileHandler.updateFiles(widget.files, loadFiles: true);
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

  /// Get the file handler.
  YustFileHandler get fileHandler => _fileHandler;

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
    final totalFiles = _fileHandler.getFiles().length;
    return _selectedFiles.length == totalFiles;
  }

  /// Get all files in the order they are displayed in (sorted, favorites
  /// first when enabled), without applying the [currentDisplayCount] limit.
  @nonVirtual
  List<T> getOrderedFiles({List<T>? files}) {
    final ordered = sortFiles(convertFiles(files ?? _fileHandler.getFiles()));
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

  /// Re-emits the current file list so the parent can persist changes, then
  /// rebuilds. The handler stores the same instances, so mutating a file in
  /// place and re-emitting is enough.
  void _persistAndRefresh() {
    widget.onChanged?.call(convertFiles(_fileHandler.getOnlineFiles()));
    if (mounted) setState(() {});
  }

  /// Toggle the favorite flag of a file and notify listeners.
  @nonVirtual
  Future<void> toggleFavorite(T file) async {
    file.favorite = !file.favorite;
    _persistAndRefresh();
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
    _persistAndRefresh();
  }

  /// Create a database entry for the files.
  @nonVirtual
  Future<void> createDatabaseEntry() async {
    try {
      if (widget.linkedDocPath != null &&
          !_fileHandler.existsDocData(
            await _fileHandler.getFirebaseDoc(widget.linkedDocPath!),
          )) {
        widget.onChanged!(convertFiles(_fileHandler.getOnlineFiles()));
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

  /// Build the cached indicator.
  @nonVirtual
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
          LocaleKeys.localFile.tr(),
          LocaleKeys.alertLocalFile.tr(),
        );
      },
    );
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
      await fileHandler.addFile(file);

      clearFileProcessing(file);
      widget.onChanged!(convertFiles(fileHandler.getOnlineFiles()));
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
      await fileHandler.deleteFile(yustFile);

      if (mounted) {
        setState(() {});
      }
    }
    widget.onChanged!(convertFiles(fileHandler.getOnlineFiles()));
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
                _fileHandler.getFiles().length > 1)
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

    if (oldWidget.files != widget.files) {
      _updateFuture = _fileHandler.updateFiles(widget.files, loadFiles: true);
      setState(() {});
    }
  }
}
