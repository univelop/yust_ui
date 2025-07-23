import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/yust_ui.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';

class YustImagePicker extends YustFilePickerBase<YustImage> {
  final bool zoomable;
  final String yustQuality;
  final bool showCentered;
  final bool showPreview;
  final bool convertToJPEG;

  /// Whether the current location should be watermarked on the image or not
  final bool addGpsWatermark;

  /// Whether the current timestamp should be watermarked on the image or not
  final bool addTimestampWatermark;

  /// Position (corner) of the watermark in the image
  final YustWatermarkPosition watermarkPosition;

  /// Appearance of the coordinates in the watermarks
  final YustLocationAppearance watermarkLocationAppearance;

  /// Locale in which the timestamp watermark should be formatted
  final Locale locale;

  const YustImagePicker({
    super.key,
    super.label,
    required super.storageFolderPath,
    super.linkedDocPath,
    super.linkedDocAttribute,
    super.multiple = false,
    super.numberOfFiles,
    super.suffixIcon,
    this.convertToJPEG = true,
    required List<YustImage> images,
    this.zoomable = false,
    super.onChanged,
    super.prefixIcon,
    super.readOnly = false,
    super.newestFirst = false,
    this.yustQuality = 'medium',
    super.divider = true,
    this.showCentered = false,
    this.showPreview = true,
    super.overwriteSingleFile = false,
    super.enableDropzone = false,
    this.addGpsWatermark = false,
    this.addTimestampWatermark = false,
    this.watermarkLocationAppearance = YustLocationAppearance.decimalDegree,
    this.locale = const Locale('de'),
    this.watermarkPosition = YustWatermarkPosition.bottomLeft,
    super.allowMultiSelectDownload = false,
    super.allowMultiSelectDeletion = false,
    super.onMultiSelectDownload,
    super.wrapSuffixChild = false,
    super.previewCount = 15,
  }) : super(files: images);

  // Compatibility getter for existing API
  List<YustImage> get images => files;

  @override
  YustImagePickerState createState() => YustImagePickerState();
}

class YustImagePickerState
    extends YustFilePickerBaseState<YustImage, YustImagePicker> {
  // Abstract method implementations
  @override
  List<YustImage> convertFiles(List<YustFile> files) =>
      YustImage.fromYustFiles(files);

  @override
  bool get shouldLoadFiles => true;

  @override
  Widget buildFileDisplay(BuildContext context) {
    if (widget.showPreview) {
      return widget.multiple || (widget.numberOfFiles ?? 2) > 1
          ? _buildGallery(context)
          : Padding(
              padding: const EdgeInsets.only(bottom: 2.0),
              child: _buildSingleImage(
                  context,
                  fileHandler.getFiles().firstOrNull != null
                      ? YustImage.fromYustFile(fileHandler.getFiles().first)
                      : null),
            );
    } else {
      return const SizedBox.shrink();
    }
  }

  @override
  Future<void> pickFiles() => _pickImages(ImageSource.gallery);

  @override
  Future<void> processFile(String name, File? file, Uint8List? bytes) async {
    await uploadFile(
      path: name,
      file: file,
      bytes: bytes,
      resize: true,
      convertToJPEG: widget.convertToJPEG,
      setGPSToLocation: false,
      addGpsWatermark: widget.addGpsWatermark,
      addTimestampWatermark: widget.addTimestampWatermark,
    );
  }

  @override
  List<Widget> buildSpecificActionButtons(BuildContext context) {
    return _buildPickButtons(context);
  }

  // Image-specific methods
  List<Widget> _buildPickButtons(BuildContext context) {
    if (!enabled ||
        (widget.showPreview &&
            // ignore: deprecated_member_use_from_same_package
            widget.numberOfFiles == 1 &&
            fileHandler.getFiles().firstOrNull != null &&
            !widget.overwriteSingleFile)) {
      return [];
    }

    final pictureFiles = [...fileHandler.getFiles()];
    final canAddMore = widget.numberOfFiles != null
        ? pictureFiles.length < widget.numberOfFiles! ||
            (widget.numberOfFiles == 1 && widget.overwriteSingleFile)
        : true;

    return [
      if (!widget.showPreview && pictureFiles.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.delete),
          color: Theme.of(context).colorScheme.primary,
          onPressed: () async {
            YustUi.helpers.unfocusCurrent();
            final confirmed = await YustUi.alertService.showConfirmation(
                widget.multiple
                    ? LocaleKeys.alertDeleteAllImages.tr()
                    : LocaleKeys.confirmDelete.tr(),
                LocaleKeys.delete.tr());
            if (confirmed == true) {
              try {
                for (final yustFile in pictureFiles) {
                  await fileHandler.deleteFile(yustFile);
                }
                widget.onChanged!(
                    YustImage.fromYustFiles(fileHandler.getOnlineFiles()));
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
          icon: const Icon(Icons.camera_alt),
          onPressed: enabled ? () => _pickImages(ImageSource.camera) : null,
        ),
      if (canAddMore)
        IconButton(
          color: Theme.of(context).colorScheme.primary,
          icon: const Icon(Icons.image),
          onPressed: enabled ? () => _pickImages(ImageSource.gallery) : null,
        ),
    ];
  }

  Widget _buildGallery(BuildContext context) {
    if (fileHandler.getFiles().isEmpty) {
      return const SizedBox.shrink();
    }

    return YustFileGridView<YustImage>(
      files: YustImage.fromYustFiles(fileHandler.getFiles()),
      currentItemCount: currentDisplayCount,
      itemsPerPage: widget.previewCount,
      itemBuilder: (context, file) => _buildSingleImage(context, file),
      onLoadMore: loadMoreItems,
    );
  }

  Widget _buildSingleImage(BuildContext context, YustImage? file) {
    return Stack(
      alignment: AlignmentDirectional.center,
      children: [
        _buildImagePreview(context, file),
        _buildProgressIndicator(context, file),
        selecting
            ? buildSelectionCheckbox(file)
            : _buildRemoveButton(context, file),
        if (file != null) buildCachedIndicator(file),
      ],
    );
  }

  Widget _buildImagePreview(BuildContext context, YustImage? file) {
    if (file == null) {
      return const SizedBox.shrink();
    }

    Widget? preview = YustCachedImage(
      file: file,
      fit: BoxFit.cover,
      resizeInCache: widget.yustQuality == 'original' && !widget.showCentered,
    );
    final zoomEnabled =
        ((file.url != null || file.bytes != null || file.file != null) &&
            widget.zoomable);
    if (widget.multiple || (widget.numberOfFiles ?? 2) > 1) {
      return AspectRatio(
        aspectRatio: 1,
        child: GestureDetector(
          onTap: () {
            if (selecting) {
              _toggleSelectionForImage(file);
              return;
            }

            if (zoomEnabled) {
              _showImages(file);
            }
          },
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
                onTap: () {
                  if (selecting) {
                    _toggleSelectionForImage(file);
                    return;
                  }

                  if (zoomEnabled) {
                    _showImages(file);
                  }
                },
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

  Widget _buildProgressIndicator(BuildContext context, YustImage? file) {
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

  void _toggleSelectionForImage(YustImage? yustFile) {
    if (yustFile == null) return;

    setState(() {
      if (selectedFiles.contains(yustFile)) {
        selectedFiles.remove(yustFile);
      } else {
        selectedFiles.add(yustFile);
      }
    });
  }

  Widget _buildRemoveButton(BuildContext context, YustImage? yustFile) {
    if (yustFile == null || !enabled) {
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
                await fileHandler.deleteFile(yustFile);
                if (!yustFile.cached) {
                  widget.onChanged!(
                      YustImage.fromYustFiles(fileHandler.getOnlineFiles()));
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

  Future<void> checkAndUploadImages<T>(
    List<T> images,
    Future<(String, File?, Uint8List?)> Function(T) imageDataExtractor, {
    bool setGPSToLocation = false,
    bool addGpsWatermark = false,
    bool addTimestampWatermark = false,
  }) async {
    await EasyLoading.show(status: LocaleKeys.addingImages.tr());

    if (!await checkConnectivity()) {
      await EasyLoading.dismiss();
      return;
    }

    final pictureFiles = List<YustImage>.from(fileHandler.getFiles());

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
        resize: true,
        convertToJPEG: widget.convertToJPEG,
        setGPSToLocation: setGPSToLocation,
        addGpsWatermark: addGpsWatermark,
        addTimestampWatermark: addTimestampWatermark,
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
      await Permission.accessMediaLocation.request();
      await Permission.locationWhenInUse.request();

      final picker = ImagePicker();
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
          await checkAndUploadImages(
            [image],
            (image) async {
              final file = File(image.path);
              return (image.path, file, null);
            },
            setGPSToLocation: true,
            addGpsWatermark: widget.addGpsWatermark,
            addTimestampWatermark: widget.addTimestampWatermark,
          );
        }
      }
    }
    // Else, we are on Web
    else {
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

  Future<void> _deleteFiles(List<YustImage> pictureFiles) async {
    for (final yustFile in pictureFiles) {
      await fileHandler.deleteFile(yustFile);

      if (mounted) {
        setState(() {});
      }
    }
    widget.onChanged!(YustImage.fromYustFiles(fileHandler.getOnlineFiles()));
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
  }) async {
    final YustImage newYustFile = await YustImageHelpers().processImage(
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
      watermarkPosition: widget.watermarkPosition,
      locale: widget.locale,
      watermarkLocationAppearance: widget.watermarkLocationAppearance,
    );

    await createDatabaseEntry();
    await fileHandler.addFile(newYustFile);

    widget.onChanged!(YustImage.fromYustFiles(fileHandler.getOnlineFiles()));
    if (mounted) {
      setState(() {});
    }
  }

  void _showImages(YustImage activeFile) {
    YustUi.helpers.unfocusCurrent();
    YustImageScreen.navigateToScreen(
      context: context,
      images: YustImage.fromYustFiles(fileHandler.getFiles()),
      activeImageIndex: fileHandler.getFiles().indexWhere((file) =>
          file.hash == activeFile.hash && file.name == activeFile.name),
      allowDrawing: !widget.readOnly,
      onSave: (file, newImage) {
        file.storageFolderPath = widget.storageFolderPath;
        file.linkedDocPath = widget.linkedDocPath;
        file.linkedDocAttribute = widget.linkedDocAttribute;

        fileHandler.updateFile(file, bytes: newImage);

        if (mounted) {
          setState(() {});
        }
      },
    );
  }
}
