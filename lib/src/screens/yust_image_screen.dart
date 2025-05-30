import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/screens/yust_image_drawing_screen.dart';

import '../yust_ui.dart';

class YustImageScreen extends StatefulWidget {
  final List<YustImage> images;

  final int activeImageIndex;
  final void Function(YustImage image, Uint8List newImage)? onSave;

  /// Indicates whether drawing is allowed on the image.
  ///
  /// This feature is only available on mobile and desktop apps.
  final bool allowDrawing;

  /// Indicates whether the share button should be shown.
  final bool allowShare;

  /// Keep native resolution of the image
  final bool keepNativeResolution;

  const YustImageScreen({
    super.key,
    required this.images,
    this.onSave,
    this.activeImageIndex = 0,
    this.allowDrawing = false,
    this.allowShare = true,
    this.keepNativeResolution = false,
  });

  static void navigateToScreen({
    required BuildContext context,
    required List<YustImage> images,
    int activeImageIndex = 0,
    bool allowDrawing = false,
    bool allowShare = true,
    bool keepNativeResolution = false,
    void Function(YustImage image, Uint8List newImage)? onSave,
  }) {
    unawaited(
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => YustImageScreen(
          images: images,
          onSave: onSave,
          activeImageIndex: activeImageIndex,
          keepNativeResolution: keepNativeResolution,
          allowDrawing: allowDrawing,
          allowShare: allowShare,
        ),
      )),
    );
  }

  @override
  State<YustImageScreen> createState() => _YustImageScreenState();
}

class _YustImageScreenState extends State<YustImageScreen> {
  late int activeImageIndex;
  late PageController _pageController;
  @override
  void initState() {
    activeImageIndex = widget.activeImageIndex;
    _pageController = PageController(initialPage: activeImageIndex);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: SafeArea(
          child: widget.images.length == 1
              ? _buildSingle(context)
              : _buildMultiple(context)),
    );
  }

  Widget _buildSingle(BuildContext context) {
    final image = widget.images.first;
    return Stack(children: [
      widget.keepNativeResolution
          ? _getNativeResolutionPhotoView(image)
          : _getScaledUpPhotoView(image),
      if (!kIsWeb && widget.allowDrawing && widget.onSave != null)
        _buildDrawButton(context, image),
      if (kIsWeb) _buildCloseButton(context),
      if (widget.allowShare) _buildShareButton(context, image),
    ]);
  }

  Widget _buildMultiple(BuildContext context) {
    return Stack(
      children: [
        PhotoViewGallery.builder(
          itemCount: widget.images.length,
          scrollPhysics: const BouncingScrollPhysics(),
          pageController: _pageController,
          onPageChanged: (index) {
            setState(() {
              activeImageIndex = index;
            });
          },
          builder: (BuildContext context, int index) {
            final currentImage = widget.images[index];

            return widget.keepNativeResolution
                ? _getNativeResolutionPhotoViewOptions(currentImage, index)
                : _getScaledUpPhotoViewOptions(currentImage);
          },
          loadingBuilder: (context, event) => const Center(
            child: SizedBox(
              width: 20.0,
              height: 20.0,
              child: CircularProgressIndicator(),
            ),
          ),
        ),
        if (kIsWeb)
          Container(
            padding: const EdgeInsets.all(20.0),
            alignment: Alignment.centerLeft,
            child: CircleAvatar(
              backgroundColor: Colors.black,
              radius: 25,
              child: IconButton(
                iconSize: 35,
                color: Colors.white,
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                ),
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutSine,
                  );
                },
              ),
            ),
          ),
        if (kIsWeb)
          Container(
            padding: const EdgeInsets.all(20.0),
            alignment: Alignment.centerRight,
            child: CircleAvatar(
              backgroundColor: Colors.black,
              radius: 25,
              child: IconButton(
                iconSize: 35,
                color: Colors.white,
                icon: const Icon(Icons.arrow_forward_ios),
                onPressed: () {
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutSine,
                  );
                },
              ),
            ),
          ),
        if (!kIsWeb && widget.allowDrawing && widget.onSave != null)
          _buildDrawButton(context, widget.images[activeImageIndex]),
        if (kIsWeb) _buildCloseButton(context),
        if (widget.allowShare)
          _buildShareButton(context, widget.images[activeImageIndex]),
      ],
    );
  }

  PhotoView _getScaledUpPhotoView(YustImage image) {
    return PhotoView(
      imageProvider: _getImageOfUrl(image),
      minScale: PhotoViewComputedScale.contained,
      heroAttributes: PhotoViewHeroAttributes(tag: image.url ?? ''),
      onTapUp: (context, details, controllerValue) {
        Navigator.pop(context);
      },
      loadingBuilder: (context, event) => const Center(
        child: SizedBox(
          width: 20.0,
          height: 20.0,
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }

  PhotoViewGalleryPageOptions _getScaledUpPhotoViewOptions(
      YustImage currentImage) {
    return PhotoViewGalleryPageOptions(
      imageProvider: _getImageOfUrl(currentImage),
      minScale: PhotoViewComputedScale.contained,
      heroAttributes: PhotoViewHeroAttributes(tag: currentImage.url ?? ''),
      onTapUp: (context, details, controllerValue) {
        Navigator.pop(context);
      },
    );
  }

  PhotoView _getNativeResolutionPhotoView(YustImage image) {
    return PhotoView.customChild(
      initialScale: PhotoViewComputedScale.contained,
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 2.0,
      heroAttributes: PhotoViewHeroAttributes(tag: image.url ?? ''),
      onTapUp: (context, details, controllerValue) {
        Navigator.pop(context);
      },
      child: _buildScalableImage(_getImageOfUrl(image)),
    );
  }

  PhotoViewGalleryPageOptions _getNativeResolutionPhotoViewOptions(
      YustImage currentImage, int index) {
    return PhotoViewGalleryPageOptions.customChild(
      child: _buildScalableImage(_getImageOfUrl(currentImage)),
      initialScale: PhotoViewComputedScale.contained,
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 2.0,
      heroAttributes:
          PhotoViewHeroAttributes(tag: widget.images[index].url ?? ''),
      onTapUp: (context, details, controllerValue) {
        Navigator.pop(context);
      },
    );
  }

  Widget _buildScalableImage(ImageProvider<Object> imageProvider) {
    return Image(
      image: imageProvider,
      fit: BoxFit.scaleDown,
      loadingBuilder: (BuildContext context, Widget child,
          ImageChunkEvent? loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(
          child: SizedBox(
            width: 20.0,
            height: 20.0,
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
  }

  Widget _buildDrawButton(BuildContext context, YustImage image) {
    if (image.url == null && image.devicePath == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      right: 70.0,
      child: RepaintBoundary(
        child: Container(
          margin: const EdgeInsets.all(20),
          child: CircleAvatar(
            backgroundColor: Colors.black,
            radius: 25,
            child: Builder(
              builder: (BuildContext context) {
                return IconButton(
                  iconSize: 35,
                  color: Colors.white,
                  onPressed: () {
                    YustImageDrawingScreen.navigateToScreen(
                        context: context,
                        image: _getImageOfUrl(image),
                        onSave: (imageBytes) async {
                          if (imageBytes != null) {
                            widget.onSave!(image, imageBytes);
                            setState(() {});
                          }
                        });
                  },
                  icon: const Icon(Icons.draw_outlined),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      alignment: Alignment.topRight,
      child: CircleAvatar(
        backgroundColor: Colors.black,
        radius: 25,
        child: IconButton(
            iconSize: 35,
            color: Colors.white,
            icon: const Icon(Icons.close),
            onPressed: () {
              Navigator.pop(context);
            }),
      ),
    );
  }

  Widget _buildShareButton(BuildContext context, YustImage image) {
    return Positioned(
      right: kIsWeb ? 70.0 : 0.0,
      child: RepaintBoundary(
        child: Container(
          margin: const EdgeInsets.all(20),
          child: CircleAvatar(
            backgroundColor: Colors.black,
            radius: 25,
            child: Builder(
              builder: (BuildContext buttonContext) {
                return IconButton(
                  iconSize: 35,
                  color: Colors.white,
                  onPressed: () {
                    YustUi.fileHelpers.downloadAndLaunchFile(
                        context: buttonContext,
                        url: image.url!,
                        name: image.name!);
                  },
                  icon: kIsWeb
                      ? const Icon(Icons.download)
                      : const Icon(Icons.share),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// because of the offline cache the file could be a stored online or on device
  ImageProvider<Object> _getImageOfUrl(YustImage image) {
    if (image.cached) {
      var imageFile = File(image.devicePath!);
      return MemoryImage(Uint8List.fromList(imageFile.readAsBytesSync()));
    } else {
      return NetworkImage(image.url!);
    }
  }
}
