import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import '../yust_ui.dart';

class YustCachedImage extends StatelessWidget {
  final YustFile file;
  final String? placeholder;
  final BoxFit? fit;
  final double? width;
  final double? height;
  const YustCachedImage({
    super.key,
    required this.file,
    this.fit,
    this.height,
    this.width,
    this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    // define default preview
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
      preview = CachedNetworkImage(
        width: width,
        height: height,
        imageUrl: file.url!,
        maxWidthDiskCache:
            !kIsWeb && (Platform.isAndroid || Platform.isIOS) ? 300 : null,
        maxHeightDiskCache:
            !kIsWeb && (Platform.isAndroid || Platform.isIOS) ? 300 : null,
        imageBuilder: (context, image) {
          return Image(
            image: image,
            fit: fit,
          );
        },
        errorWidget: (context, _, __) => Image.asset(
            placeholder ?? YustUi.imagePlaceholderPath!,
            fit: BoxFit.cover),
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
