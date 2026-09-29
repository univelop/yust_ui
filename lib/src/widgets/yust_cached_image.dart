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
      // ignore: deprecated_member_use
    } else if (file.url != null || file.path != null) {
      final showThumbnail =
          (mode == YustCachedImageMode.preferThumbnail ||
              mode == YustCachedImageMode.thumbnailOnly) &&
          file.hasThumbnail;

      if (mode == YustCachedImageMode.thumbnailOnly && !showThumbnail) {
        return preview;
      }

      final thumbnailUrl = showThumbnail ? file.getThumbnailUrl() : null;
      final originalUrl = mode == YustCachedImageMode.thumbnailOnly
          ? null
          : file.getOriginalUrl();
      final url = thumbnailUrl ?? originalUrl;

      if (url == null) return preview;

      final fallbackUrl = url == thumbnailUrl ? originalUrl : null;
      if (kIsWeb) return _buildWebImage(url, fallbackUrl: fallbackUrl);

      preview = _buildCachedImage(
        url,
        cacheKey: _cacheKey(thumbnail: url == thumbnailUrl),
        fallbackUrl: fallbackUrl,
      );
    }

    return preview;
  }

  /// Keeps the cache entry stable when the signed part of the url rotates.
  String? _cacheKey({required bool thumbnail}) {
    if (file.path == null) return null;
    final size = thumbnail ? YustFileThumbnailSize.normal.name : 'original';
    return '${file.path}/${file.name}#${file.hash}@$size';
  }

  Widget _buildWebImage(String url, {String? fallbackUrl}) => Image.network(
    url,
    width: width,
    height: height,
    fit: fit,
    cacheHeight: resizeInCache == true ? 300 : null,
    cacheWidth: resizeInCache == true ? 300 : null,
    frameBuilder: (context, child, frame, sync) =>
        frame != null ? child : _buildLoadingIndicator(),
    loadingBuilder: (context, child, loadingProgress) =>
        loadingProgress == null ? child : _buildLoadingIndicator(),
    errorBuilder: fallbackUrl == null
        ? null
        : (context, _, _) => _buildWebImage(fallbackUrl),
  );

  Widget _buildLoadingIndicator() => const Center(
    child: SizedBox(
      width: 50,
      height: 50,
      child: CircularProgressIndicator(),
    ),
  );

  Widget _buildCachedImage(
    String url, {
    String? cacheKey,
    String? fallbackUrl,
  }) {
    final isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    return CachedNetworkImage(
      width: width,
      height: height,
      imageUrl: url,
      cacheKey: cacheKey,
      maxWidthDiskCache: isMobile ? 300 : null,
      maxHeightDiskCache: isMobile ? 300 : null,
      imageBuilder: (context, image) => Image(
        image: image,
        fit: fit,
      ),
      errorWidget: (context, _, _) => fallbackUrl == null
          ? Image.asset(
              placeholder ?? YustUi.imagePlaceholderPath!,
              fit: BoxFit.cover,
            )
          : _buildCachedImage(
              fallbackUrl,
              cacheKey: _cacheKey(thumbnail: false),
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
}
