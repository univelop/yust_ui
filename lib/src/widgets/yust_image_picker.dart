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

/// A widget that allows the user to pick images from the gallery or camera.
class YustImagePicker extends YustFilePickerBase<YustImage> {
  /// Whether the image can be zoomed e.g. clicked to show the image in a full screen view.
  final bool zoomable;

  /// Quality of the image
  final String yustQuality;

  /// Whether to show the image centered in the widget
  ///
  /// Only takes affect if just one image is shown.
  final bool showCentered;

  /// Whether to show the preview of the image
  ///
  /// If false, this widget acts as a picker only.
  final bool showPreview;

  /// Whether all uploaded images should be converted to JPEG
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
    required List<YustImage> images,
    super.linkedDocPath,
    super.linkedDocAttribute,
    super.numberOfFiles = YustFilePickerBase.defaultNumberOfFiles,
    super.suffixIcon,
    super.onChanged,
    super.prefixIcon,
    super.readOnly = false,
    super.newestFirst = false,
    super.divider = true,
    super.overwriteSingleFile = false,
    super.enableDropzone = false,
    super.allowMultiSelectDownload = false,
    super.allowMultiSelectDeletion = false,
    super.onMultiSelectDownload,
    super.wrapSuffixChild = false,
    super.previewCount = YustFilePickerBase.defaultPreviewCount,
    this.convertToJPEG = true,
    this.zoomable = false,
    this.yustQuality = 'medium',
    this.showCentered = false,
    this.showPreview = true,
    this.addGpsWatermark = false,
    this.addTimestampWatermark = false,
    this.watermarkLocationAppearance = YustLocationAppearance.decimalDegree,
    this.locale = const Locale('de'),
    this.watermarkPosition = YustWatermarkPosition.bottomLeft,
  }) : super(files: images);

  /// A convenience constructor for a single image picker.
  const YustImagePicker.single({
    super.key,
    super.label,
    required super.storageFolderPath,
    required List<YustImage> images,
    super.linkedDocPath,
    super.linkedDocAttribute,
    super.suffixIcon,
    super.onChanged,
    super.prefixIcon,
    super.readOnly = false,
    super.newestFirst = false,
    super.divider = true,
    super.enableDropzone = false,
    super.wrapSuffixChild = false,
    super.overwriteSingleFile = false,
    this.convertToJPEG = true,
    this.zoomable = false,
    this.yustQuality = 'medium',
    this.showCentered = false,
    this.showPreview = true,
    this.addGpsWatermark = false,
    this.addTimestampWatermark = false,
    this.watermarkLocationAppearance = YustLocationAppearance.decimalDegree,
    this.locale = const Locale('de'),
    this.watermarkPosition = YustWatermarkPosition.bottomLeft,
  }) : super(files: images, numberOfFiles: 1);

  @override
  YustImagePickerState createState() => YustImagePickerState();
}

class YustImagePickerState
    extends YustFilePickerBaseState<YustImage, YustImagePicker> {
  @override
  List<YustImage> convertFiles(List<YustFile> files) =>
      YustImage.fromYustFiles(files);

  @override
  Widget build(BuildContext context) {
    // Use build function from parent class so that shared logic can be reused.
    return super.build(context);
  }

  @override
  Widget buildFileDisplay(BuildContext context) {
    if (!widget.showPreview) {
      return const SizedBox.shrink();
    }

    return widget.numberOfFiles > 1
        ? _buildGallery(context)
        : Padding(
            padding: const EdgeInsets.only(bottom: 2.0),
            child: _buildSingleImage(
              context,
              fileHandler.getFiles().firstOrNull != null
                  ? YustImage.fromYustFile(fileHandler.getFiles().first)
                  : null,
            ),
          );
  }

  @override
  Future<void> pickFiles() => _pickImages(ImageSource.gallery);

  @override
  List<Widget> buildActionButtons(BuildContext context) {
    return _buildPickButtons(context);
  }

  @override
  Future<YustImage> processFile(String name, File? file, Uint8List? bytes) =>
      _createImageObject(name, file, bytes);

  Future<YustImage> _createImageObject(
    String name,
    File? file,
    Uint8List? bytes, {
    bool setGPSToLocation = false,
    bool addGpsWatermark = false,
    bool addTimestampWatermark = false,
  }) => YustImageHelpers().processImage(
    file: file,
    bytes: bytes,
    path: name,
    resize: true,
    convertToJPEG: widget.convertToJPEG,
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
    final canAddMore =
        pictureFiles.length < widget.numberOfFiles ||
        (widget.numberOfFiles == 1 && widget.overwriteSingleFile);

    return [
      if (!widget.showPreview && pictureFiles.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.delete),
          color: Theme.of(context).colorScheme.primary,
          onPressed: () async {
            YustUi.helpers.unfocusCurrent();
            final confirmed = await YustUi.alertService.showConfirmation(
              widget.numberOfFiles > 1
                  ? LocaleKeys.alertDeleteAllImages.tr()
                  : LocaleKeys.confirmDelete.tr(),
              LocaleKeys.delete.tr(),
            );
            if (confirmed == true) {
              try {
                for (final yustFile in pictureFiles) {
                  await fileHandler.deleteFile(yustFile);
                }
                widget.onChanged!(
                  YustImage.fromYustFiles(fileHandler.getOnlineFiles()),
                );
                if (mounted) {
                  setState(() {});
                }
              } catch (e) {
                await YustUi.alertService.showAlert(
                  LocaleKeys.oops.tr(),
                  LocaleKeys.alertCannotDeleteImage.tr(
                    namedArgs: {'error': e.toString()},
                  ),
                );
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
      files: getVisibleFiles(),
      itemBuilder: (context, file) => _buildSingleImage(context, file),
      loadMoreButton: buildLoadMoreButton(context),
      totalFileCount: widget.files.length,
    );
  }

  Widget _buildSingleImage(BuildContext context, YustImage? file) {
    return Stack(
      alignment: AlignmentDirectional.center,
      children: [
        _buildImagePreview(context, file),
        _buildProgressIndicator(context, file),
        selecting
            ? _buildSelectionCheckbox(file)
            : _buildRemoveButton(context, file),
        if (file != null) buildCachedIndicator(file),
      ],
    );
  }

  Widget _buildSelectionCheckbox(YustImage? image) {
    if (!selecting || image == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 10,
      left: 10,
      child: Checkbox(
        value: selectedFiles.contains(image),
        shape: const CircleBorder(),
        onChanged: (value) => toggleFileSelection(image),
        fillColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return Theme.of(context).primaryColor;
          }
          return Colors.grey.shade300;
        }),
      ),
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
    if (widget.numberOfFiles > 1) {
      return AspectRatio(
        aspectRatio: 1,
        child: GestureDetector(
          onTap: () {
            if (selecting) {
              toggleFileSelection(file);
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
                  toggleFileSelection(file);
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
          ),
        );
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
                color: Theme.of(context).colorScheme.secondary,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
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
              LocaleKeys.confirmDelete.tr(),
              LocaleKeys.delete.tr(),
            );
            if (confirmed == true) {
              try {
                await fileHandler.deleteFile(yustFile);
                if (!yustFile.cached) {
                  widget.onChanged!(
                    YustImage.fromYustFiles(fileHandler.getOnlineFiles()),
                  );
                }
                if (mounted) {
                  setState(() {});
                }
              } catch (e) {
                await YustUi.alertService.showAlert(
                  LocaleKeys.oops.tr(),
                  LocaleKeys.alertCannotDeleteImage.tr(
                    namedArgs: {'error': e.toString()},
                  ),
                );
              }
            }
          },
        ),
      ),
    );
  }

  @override
  Future<void> checkAndUploadFiles<U>(
    List<U> fileData,
    Future<(String, File?, Uint8List?)> Function(U) fileDataExtractor,
  ) => _checkAndUploadImages(fileData, fileDataExtractor);

  Future<void> _checkAndUploadImages<T>(
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

    final willOverwrite =
        widget.numberOfFiles == 1 &&
        widget.overwriteSingleFile &&
        pictureFiles.isNotEmpty;

    final effectiveCurrentFileCount = willOverwrite ? 0 : pictureFiles.length;

    if (effectiveCurrentFileCount + images.length > widget.numberOfFiles) {
      await EasyLoading.dismiss();
      await YustUi.alertService.showAlert(
        LocaleKeys.fileUpload.tr(),
        widget.numberOfFiles == 1
            ? LocaleKeys.alertMaxOneFile.tr()
            : LocaleKeys.alertMaxNumberFiles.tr(
                namedArgs: {'numberFiles': widget.numberOfFiles.toString()},
              ),
      );
      return;
    }

    // Single Image with Override
    if (willOverwrite) {
      await EasyLoading.dismiss();
      final confirmed = await YustUi.alertService.showConfirmation(
        LocaleKeys.alertConfirmOverwriteFile.tr(),
        LocaleKeys.continue_.tr(),
      );
      if (confirmed != true) return;
    }

    for (final image in images) {
      final (path, file, bytes) = await imageDataExtractor(image);

      final fileExtension = path.split('.').lastOrNull?.toLowerCase();

      if (kIsWeb && fileExtension == 'heic') {
        await EasyLoading.dismiss();
        await YustUi.alertService.showAlert(
          LocaleKeys.fileUpload.tr(),
          LocaleKeys.alertInvalidFileType.tr(
            namedArgs: {
              'supportedTypes': yustAllowedImageExtensions.join(', '),
            },
          ),
        );
        continue;
      }

      if (!yustAllowedImageExtensions.contains(fileExtension)) {
        await EasyLoading.dismiss();
        await YustUi.alertService.showAlert(
          LocaleKeys.fileUpload.tr(),
          LocaleKeys.alertInvalidFileType.tr(
            namedArgs: {
              'supportedTypes': yustAllowedImageExtensions.join(', '),
            },
          ),
        );
        continue;
      }

      final newImage = await _createImageObject(
        path,
        file,
        bytes,
        setGPSToLocation: setGPSToLocation,
        addGpsWatermark: addGpsWatermark,
        addTimestampWatermark: addTimestampWatermark,
      );

      await uploadFile(file: newImage);
    }
    if (widget.numberOfFiles == 1 && widget.overwriteSingleFile) {
      await deleteFiles(pictureFiles);
    }

    await EasyLoading.dismiss();
  }

  Future<void> _pickImages(ImageSource imageSource) async {
    YustUi.helpers.unfocusCurrent();
    if (!kIsWeb) {
      await Permission.accessMediaLocation.request();
      await Permission.locationWhenInUse.request();

      final picker = ImagePicker();
      if (widget.numberOfFiles > 1 && imageSource == ImageSource.gallery) {
        final images = await picker.pickMultiImage();

        await _checkAndUploadImages(images, (image) async {
          final file = File(image.path);
          return (image.path, file, null);
        });
      } else {
        final image = await picker.pickImage(source: imageSource);
        if (image != null) {
          await _checkAndUploadImages(
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
      return;
    }

    // We are on Web
    final multipleFiles = widget.numberOfFiles > 1;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: multipleFiles,
    );
    if (result == null) return;

    await _checkAndUploadImages(result.files, (file) async {
      return (file.name, null, file.bytes);
    });
  }

  void _showImages(YustImage activeFile) {
    YustUi.helpers.unfocusCurrent();
    YustImageScreen.navigateToScreen(
      context: context,
      images: YustImage.fromYustFiles(fileHandler.getFiles()),
      activeImageIndex: fileHandler.getFiles().indexWhere(
        (file) => file.hash == activeFile.hash && file.name == activeFile.name,
      ),
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
