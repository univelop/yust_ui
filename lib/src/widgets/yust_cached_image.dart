import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import '../yust_ui.dart';

/// Mode to display the image.
enum YustCachedImageMode {
  /// If a thumbnail is available, it will be preferred over the original image.
  /// Otherwise the original image will be displayed.
  preferThumbnail,

  /// Only the original image will be displayed.
  originalOnly,

  /// Only the thumbnail will be displayed.
  ///
  /// If no thumbnail is available, a placeholder will be shown.
  thumbnailOnly,
}

class YustCachedImage extends StatelessWidget {
  /// The file to display.
  final YustFile file;

  /// Placeholder text to display while the image is loading.
  final String? placeholder;

  /// Fit of the image.
  final BoxFit? fit;

  /// Width of the image.
  final double? width;

  /// Height of the image.
  final double? height;

  /// Resize image in cache to 300x300
  ///
  /// This may destroy the aspect ratio of the image
  final bool? resizeInCache;

  /// Mode to display the image.
  final YustCachedImageMode mode;

  const YustCachedImage({
    super.key,
    required this.file,
    this.fit,
    this.height,
    this.width,
    this.placeholder,
    this.resizeInCache,
    this.mode = YustCachedImageMode.preferThumbnail,
  });

  @override
  Widget build(BuildContext context) {
    Widget preview = Container(
      height: height ?? 150,
      width: width ?? 150,
      color: Colors.grey,
      child: const Icon(Icons.question_mark),
    );

    if (file.file != null && file.bytes == null) {
      file.bytes = file.file!.readAsBytesSync();
    }

    if (file.bytes != null) {
      preview = Image.memory(
        file.bytes!,
        width: width,
        height: height,
        fit: fit,
      );
    } else if (file.url != null) {
      final showThumbnail =
          (mode == YustCachedImageMode.preferThumbnail ||
              mode == YustCachedImageMode.thumbnailOnly) &&
          file.hasThumbnail();

      if (mode == YustCachedImageMode.thumbnailOnly && !showThumbnail) {
        return preview;
      }

      final url = showThumbnail
          ? file.getThumbnailUrl()!
          : file.getOriginalUrl();

      if (url == null) return preview;

      if (kIsWeb) {
        return Image.network(
          url,
          width: width,
          height: height,
          fit: fit,
          cacheHeight: resizeInCache == true ? 300 : null,
          cacheWidth: resizeInCache == true ? 300 : null,
          frameBuilder: (context, child, frame, sync) {
            if (frame != null) return child;

            return const Center(
              child: SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(),
              ),
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;

            return const Center(
              child: SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(),
              ),
            );
          },
        );
      }

      preview = CachedNetworkImage(
        width: width,
        height: height,
        imageUrl: url,
        maxWidthDiskCache: !kIsWeb && (Platform.isAndroid || Platform.isIOS)
            ? 300
            : null,
        maxHeightDiskCache: !kIsWeb && (Platform.isAndroid || Platform.isIOS)
            ? 300
            : null,
        imageBuilder: (context, image) {
          return Image(
            image: image,
            fit: fit,
          );
        },
        errorWidget: (context, _, _) => Image.asset(
          placeholder ?? YustUi.imagePlaceholderPath!,
          fit: BoxFit.cover,
        ),
        progressIndicatorBuilder: (context, url, downloadProgress) => Container(
          margin: const EdgeInsets.all(50),
          child: Center(
            child: CircularProgressIndicator(
              value: downloadProgress.progress,
            ),
          ),
        ),
        fit: fit,
      );
    }

    return preview;
  }
}
