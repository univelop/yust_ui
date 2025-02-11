import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/widgets/yust_dropzone_list_tile.dart';
import 'package:yust_ui/yust_ui.dart';

// ignore: depend_on_referenced_packages
import 'package:flutter_dropzone_platform_interface/flutter_dropzone_platform_interface.dart';
import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';

class YustImagePicker extends StatefulWidget {
  final String? label;

  /// Path to the storage folder.
  final String storageFolderPath;

  /// [linkedDocPath] and [linkedDocAttribute] are needed for the offline compatibility.
  /// If not given, uploads are only possible with internet connection
  final String? linkedDocPath;

  /// [linkedDocPath] and [linkedDocAttribute] are needed for the offline compatibility.
  /// If not given, uploads are only possible with internet connection
  final String? linkedDocAttribute;

  @Deprecated('Use [numberOfFiles] instead')
  final bool multiple;

  /// When [numberOfFiles] is null, the user can upload as many files as he
  /// wants. Otherwise the user can only upload [numberOfFiles] files.
  final num? numberOfFiles;
  final List<YustFile> images;
  final bool zoomable;
  final void Function(List<YustFile> images)? onChanged;
  final Widget? prefixIcon;
  final bool newestFirst;
  final bool readOnly;
  final String yustQuality;
  final bool divider;
  final bool showCentered;
  final bool showPreview;
  final bool overwriteSingleFile;
  final bool enableDropzone;
  final Widget? suffixIcon;
  final bool convertToJPEG;
  final bool addGpsWatermark;
  final bool addTimestampWatermark;
  final YustWatermarkPosition watermarkPosition;
  final bool displayCoordinatesInDegreeMinuteSecond;
  final Locale locale;

  /// default is 15
  final int imageCount;

  const YustImagePicker({
    super.key,
    this.label,
    required this.storageFolderPath,
    this.linkedDocPath,
    this.linkedDocAttribute,
    this.multiple = false,
    this.numberOfFiles,
    this.suffixIcon,
    this.convertToJPEG = true,
    required this.images,
    this.zoomable = false,
    this.onChanged,
    this.prefixIcon,
    this.readOnly = false,
    this.newestFirst = false,
    this.yustQuality = 'medium',
    this.divider = true,
    this.showCentered = false,
    this.showPreview = true,
    this.overwriteSingleFile = false,
    this.enableDropzone = false,
    this.addGpsWatermark = false,
    this.addTimestampWatermark = false,
    this.displayCoordinatesInDegreeMinuteSecond = false,
    this.locale = const Locale('de'),
    this.watermarkPosition = YustWatermarkPosition.bottomLeft,
    int? imageCount,
  }) : imageCount = imageCount ?? 15;
  @override
  YustImagePickerState createState() => YustImagePickerState();
}

class YustImagePickerState extends State<YustImagePicker>
    with AutomaticKeepAliveClientMixin {
  late YustFileHandler _fileHandler;
  late bool _enabled;
  late int _currentImageNumber;

  @override
  void initState() {
    _fileHandler = YustUi.fileHandlerManager.createFileHandler(
      storageFolderPath: widget.storageFolderPath,
      linkedDocAttribute: widget.linkedDocAttribute,
      linkedDocPath: widget.linkedDocPath,
      newestFirst: widget.newestFirst,
      onFileUploaded: () {
        if (mounted) {
          setState(() {});
        }
        widget.onChanged!(_fileHandler.getOnlineFiles());
      },
    );

    _enabled = (widget.onChanged != null && !widget.readOnly);
    _currentImageNumber = widget.imageCount;

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _enabled = widget.onChanged != null && !widget.readOnly;
    _fileHandler.newestFirst = widget.newestFirst;
    return FutureBuilder(
      future: _fileHandler.updateFiles(widget.images, loadFiles: true),
      builder: (context, snapshot) => _buildImagePicker(context),
    );
  }

  Widget _buildImagePicker(BuildContext context) {
    if (kIsWeb && widget.enableDropzone && _enabled) {
      return YustDropzoneListTile(
        suffixChild: _buildSuffixChild(context),
        label: widget.label,
        prefixIcon: widget.prefixIcon,
        below: _buildImages(context),
        divider: widget.divider,
        onDropMultiple: (controller, ev) async {
          await checkAndUploadImages<DropzoneFileInterface>(ev ?? [],
              (fileData) async {
            final data = await controller.getFileData(fileData);
            return (fileData.name.toString(), null, data);
          });
        },
      );
    } else {
      return YustListTile(
        label: widget.label,
        suffixChild: _buildSuffixChild(context),
        prefixIcon: widget.prefixIcon,
        below: _buildImages(context),
        divider: widget.divider,
      );
    }
  }

  Widget _buildImages(BuildContext context) {
    if (widget.showPreview) {
      // ignore: deprecated_member_use_from_same_package
      return widget.multiple || (widget.numberOfFiles ?? 2) > 1
          ? _buildGallery(context)
          : Padding(
              padding: const EdgeInsets.only(bottom: 2.0),
              child: _buildSingleImage(
                  context, _fileHandler.getFiles().firstOrNull),
            );
    } else {
      return const SizedBox.shrink();
    }
  }

  Widget _buildSuffixChild(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPickButtons(context),
          if (widget.suffixIcon != null) widget.suffixIcon!
        ],
      );

  Widget _buildPickButtons(BuildContext context) {
    if (!_enabled ||
        (widget.showPreview &&
            // ignore: deprecated_member_use_from_same_package
            widget.numberOfFiles == 1 &&
            _fileHandler.getFiles().firstOrNull != null &&
            !widget.overwriteSingleFile)) {
      return const SizedBox.shrink();
    }

    final pictureFiles = [..._fileHandler.getFiles()];
    final canAddMore = widget.numberOfFiles != null
        ? pictureFiles.length < widget.numberOfFiles! ||
            (widget.numberOfFiles == 1 && widget.overwriteSingleFile)
        : true;

    return SizedBox(
      width: 150,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (!widget.showPreview && pictureFiles.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              color: Theme.of(context).colorScheme.primary,
              iconSize: 40,
              onPressed: () async {
                YustUi.helpers.unfocusCurrent();
                final confirmed = await YustUi.alertService.showConfirmation(
                    // ignore: deprecated_member_use_from_same_package
                    widget.multiple
                        ? LocaleKeys.alertDeleteAllImages.tr()
                        : LocaleKeys.confirmDelete.tr(),
                    LocaleKeys.delete.tr());
                if (confirmed == true) {
                  try {
                    for (final yustFile in pictureFiles) {
                      await _fileHandler.deleteFile(yustFile);
                    }
                    widget.onChanged!(_fileHandler.getOnlineFiles());
                    if (mounted) {
                      setState(() {});
                    }
                  } catch (e) {
                    await YustUi.alertService.showAlert(
                        LocaleKeys.oops.tr(),
                        LocaleKeys.alertCannotDeleteImage
                            .tr(namedArgs: {'error': e.toString()}));
                  }
                }
              },
            ),
          if (!kIsWeb && canAddMore)
            IconButton(
              color: Theme.of(context).colorScheme.primary,
              iconSize: 40,
              icon: const Icon(Icons.camera_alt),
              onPressed:
                  _enabled ? () => _pickImages(ImageSource.camera) : null,
            ),
          if (canAddMore)
            IconButton(
              color: Theme.of(context).colorScheme.primary,
              iconSize: 40,
              icon: const Icon(Icons.image),
              onPressed:
                  _enabled ? () => _pickImages(ImageSource.gallery) : null,
            ),
        ],
      ),
    );
  }

  Widget _buildGallery(BuildContext context) {
    if (_fileHandler.getFiles().isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildGalleryView(context),
        if (_fileHandler.getFiles().length > _currentImageNumber)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.surface,
              ),
              onPressed: () {
                _currentImageNumber += widget.imageCount;
                setState(() {
                  _buildGallery(context);
                });
              },
              icon: const Icon(Icons.refresh),
              label: Text(LocaleKeys.loadMore.tr()),
            ),
          ),
        const SizedBox(height: 2)
      ],
    );
  }

  GridView _buildGalleryView(
    BuildContext context,
  ) {
    var pictureFiles = _fileHandler.getFiles().length > _currentImageNumber
        ? _fileHandler.getFiles().sublist(0, _currentImageNumber)
        : _fileHandler.getFiles();

    return GridView.extent(
      shrinkWrap: true,
      maxCrossAxisExtent: 180,
      primary: false,
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      children: pictureFiles.map((file) {
        return _buildSingleImage(context, file);
      }).toList(),
    );
  }

  Widget _buildSingleImage(BuildContext context, YustFile? file) {
    return Stack(
      alignment: AlignmentDirectional.center,
      children: [
        _buildImagePreview(context, file),
        _buildProgressIndicator(context, file),
        _buildRemoveButton(context, file),
        _buildCachedIndicator(context, file),
      ],
    );
  }

  Widget _buildImagePreview(BuildContext context, YustFile? file) {
    if (file == null) {
      return const SizedBox.shrink();
    }

    Widget? preview = YustCachedImage(
      file: file,
      fit: BoxFit.cover,
    );
    final zoomEnabled =
        ((file.url != null || file.bytes != null || file.file != null) &&
            widget.zoomable);
    // ignore: deprecated_member_use_from_same_package
    if (widget.multiple || (widget.numberOfFiles ?? 2) > 1) {
      return AspectRatio(
        aspectRatio: 1,
        child: GestureDetector(
          onTap: zoomEnabled ? () => _showImages(file) : null,
          child: file.url != null
              ? Hero(
                  tag: file.url!,
                  child: preview,
                )
              : preview,
        ),
      );
    } else {
      if (widget.showCentered) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: file.url != null
              ? Hero(
                  tag: file.url!,
                  child: preview,
                )
              : preview,
        );
      } else {
        return Container(
            constraints: const BoxConstraints(
              minHeight: 100,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 300,
                maxWidth: 400,
              ),
              child: GestureDetector(
                onTap: zoomEnabled ? () => _showImages(file) : null,
                child: file.url != null
                    ? Hero(
                        tag: file.url!,
                        child: preview,
                      )
                    : preview,
              ),
            ));
      }
    }
  }

  Widget _buildProgressIndicator(BuildContext context, YustFile? file) {
    if (file?.processing != true) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              LocaleKeys.uploadImage.tr(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoveButton(BuildContext context, YustFile? yustFile) {
    if (yustFile == null || !_enabled) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: 10,
      right: 10,
      child: CircleAvatar(
        radius: 20,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: IconButton(
          icon: const Icon(Icons.delete),
          color: Colors.black,
          onPressed: () async {
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
                    LocaleKeys.alertCannotDeleteImage
                        .tr(namedArgs: {'error': e.toString()}));
              }
            }
          },
        ),
      ),
    );
  }

  Widget _buildCachedIndicator(BuildContext context, YustFile? yustFile) {
    if (yustFile == null || !yustFile.cached || !_enabled) {
      return const SizedBox.shrink();
    }
    return Positioned(
      bottom: 5,
      right: 5,
      child: IconButton(
        icon: const Icon(Icons.cloud_upload_outlined),
        color: Colors.white,
        onPressed: () async {
          await YustUi.alertService.showAlert(
              LocaleKeys.localImage.tr(), LocaleKeys.alertLocalImage.tr());
        },
      ),
    );
  }

  Future<void> checkAndUploadImages<T>(List<T> images,
      Future<(String, File?, Uint8List?)> Function(T) imageDataExtractor,
      {bool setGPSToLocation = false}) async {
    await EasyLoading.show(status: LocaleKeys.addingImages.tr());

    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none &&
        (widget.linkedDocPath == null || widget.linkedDocAttribute == null)) {
      await EasyLoading.dismiss();
      await YustUi.alertService.showAlert(LocaleKeys.missingConnection.tr(),
          LocaleKeys.alertMissingConnectionAddImages.tr());
      return;
    }
    final pictureFiles = List<YustFile>.from(_fileHandler.getFiles());

    // Single Image with Override
    if (widget.numberOfFiles == 1 &&
        widget.overwriteSingleFile &&
        pictureFiles.isNotEmpty) {
      await EasyLoading.dismiss();
      final confirmed = await YustUi.alertService.showConfirmation(
          LocaleKeys.alertConfirmOverwriteFile.tr(), LocaleKeys.continue_.tr());
      if (confirmed == false) return;
    }
    // Image Limit overstepped
    else if (widget.numberOfFiles != null &&
        pictureFiles.length + images.length > widget.numberOfFiles!) {
      await EasyLoading.dismiss();
      await YustUi.alertService.showAlert(
          LocaleKeys.fileUpload.tr(),
          widget.numberOfFiles == 1
              ? LocaleKeys.alertMaxOneFile.tr()
              : LocaleKeys.alertMaxNumberFiles.tr(
                  namedArgs: {'numberFiles': widget.numberOfFiles.toString()}));
      return;
    }

    for (final image in images) {
      final (path, file, bytes) = await imageDataExtractor(image);

      final fileExtension = path.split('.').lastOrNull?.toLowerCase();

      if (kIsWeb && fileExtension == 'heic') {
        await EasyLoading.dismiss();
        await YustUi.alertService.showAlert(
            LocaleKeys.fileUpload.tr(),
            LocaleKeys.alertInvalidFileType.tr(namedArgs: {
              'supportedTypes': yustAllowedImageExtensions.join(', ')
            }));
        continue;
      }

      if (!yustAllowedImageExtensions.contains(fileExtension)) {
        await EasyLoading.dismiss();
        await YustUi.alertService.showAlert(
            LocaleKeys.fileUpload.tr(),
            LocaleKeys.alertInvalidFileType.tr(namedArgs: {
              'supportedTypes': yustAllowedImageExtensions.join(', ')
            }));
        continue;
      }

      await uploadFile(
        path: path,
        file: file,
        bytes: bytes,
        // Because of the reason stated above,
        // we need to do the resizing ourself
        resize: true,
        convertToJPEG: widget.convertToJPEG,
        setGPSToLocation: setGPSToLocation,
        addGpsWatermark: widget.addGpsWatermark,
        addTimestampWatermark: widget.addTimestampWatermark,
        watermarkPosition: widget.watermarkPosition,
        displayCoordinatesInDegreeMinuteSecond:
            widget.displayCoordinatesInDegreeMinuteSecond,
      );
    }
    if (widget.numberOfFiles == 1 && widget.overwriteSingleFile) {
      await _deleteFiles(pictureFiles);
    }

    await EasyLoading.dismiss();
  }

  Future<void> _pickImages(ImageSource imageSource) async {
    YustUi.helpers.unfocusCurrent();
    if (!kIsWeb) {
      // Request Location Permission for GPS Data
      await Permission.accessMediaLocation.request();
      await Permission.locationWhenInUse.request();

      final picker = ImagePicker();
      // ignore: deprecated_member_use_from_same_package
      if ((widget.multiple || (widget.numberOfFiles ?? 2) > 1) &&
          imageSource == ImageSource.gallery) {
        final images = await picker.pickMultiImage();

        await checkAndUploadImages(images, (image) async {
          final file = File(image.path);
          return (image.path, file, null);
        });
      } else {
        final image = await picker.pickImage(source: imageSource);
        if (image != null) {
          await checkAndUploadImages([image], (image) async {
            final file = File(image.path);
            return (image.path, file, null);
          }, setGPSToLocation: imageSource == ImageSource.camera);
        }
      }
    }
    // Else, we are on Web
    else {
      // ignore: deprecated_member_use_from_same_package
      if (widget.multiple || (widget.numberOfFiles ?? 2) > 1) {
        final result = await FilePicker.platform
            .pickFiles(type: FileType.image, allowMultiple: true);
        if (result == null) return;

        await checkAndUploadImages(result.files, (file) async {
          return (file.name, null, file.bytes);
        });
      } else {
        final result =
            await FilePicker.platform.pickFiles(type: FileType.image);
        if (result == null) return;
        await checkAndUploadImages(result.files, (file) async {
          return (file.name, null, file.bytes);
        });
      }
    }
  }

  Future<void> _deleteFiles(List<YustFile> pictureFiles) async {
    for (final yustFile in pictureFiles) {
      await _fileHandler.deleteFile(yustFile);
    }
    widget.onChanged!(_fileHandler.getOnlineFiles());
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> uploadFile({
    required String path,
    File? file,
    Uint8List? bytes,
    bool resize = false,
    bool convertToJPEG = true,
    bool setGPSToLocation = false,
    bool addGpsWatermark = false,
    bool addTimestampWatermark = false,
    YustWatermarkPosition watermarkPosition = YustWatermarkPosition.bottomLeft,
    bool displayCoordinatesInDegreeMinuteSecond = false,
    Locale locale = const Locale('de'),
  }) async {
    final YustFile newYustFile = await YustFileHelpers().processImage(
      file: file,
      bytes: bytes,
      path: path,
      resize: resize,
      convertToJPEG: convertToJPEG,
      yustQuality: widget.yustQuality,
      setGPSToLocation: setGPSToLocation,
      storageFolderPath: widget.storageFolderPath,
      linkedDocPath: widget.linkedDocPath,
      linkedDocAttribute: widget.linkedDocAttribute,
      addGpsWatermark: addGpsWatermark,
      addTimestampWatermark: addTimestampWatermark,
      watermarkPosition: watermarkPosition,
      locale: locale,
      displayCoordinatesInDegreeMinuteSecond:
          displayCoordinatesInDegreeMinuteSecond,
    );

    await _createDatabaseEntry();
    await _fileHandler.addFile(newYustFile);

    if (_currentImageNumber < _fileHandler.getFiles().length) {
      _currentImageNumber += widget.imageCount;
    }
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

  void _showImages(YustFile activeFile) {
    YustUi.helpers.unfocusCurrent();
    YustImageScreen.navigateToScreen(
      context: context,
      files: _fileHandler.getFiles(),
      activeImageIndex: _fileHandler.getFiles().indexOf(activeFile),
      allowDrawing: !widget.readOnly,
      onSave: (file, newImage) {
        file.storageFolderPath = widget.storageFolderPath;
        file.linkedDocPath = widget.linkedDocPath;
        file.linkedDocAttribute = widget.linkedDocAttribute;

        _fileHandler.updateFile(file, bytes: newImage);

        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}
