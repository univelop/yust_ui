import 'package:flutter/material.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/yust_ui.dart';

/// A widget that allows the user to pick a single image from the gallery or camera.
///
/// This is a convenience widget that wraps [YustImagePicker] with single image defaults:
class YustSingleImagePicker extends YustImagePicker {
  const YustSingleImagePicker({
    super.key,
    super.label,
    required super.storageFolderPath,
    required super.images,
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
    super.convertToJPEG = true,
    super.zoomable = false,
    super.yustQuality = 'medium',
    super.showCentered = false,
    super.showPreview = true,
    super.addGpsWatermark = false,
    super.addTimestampWatermark = false,
    super.watermarkLocationAppearance = YustLocationAppearance.decimalDegree,
    super.locale = const Locale('de'),
    super.watermarkPosition = YustWatermarkPosition.bottomLeft,
    super.overwriteSingleFile = false,
  }) : super(
          numberOfFiles: 1,
        );
}
