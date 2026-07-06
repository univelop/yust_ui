import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/screens/yust_image_drawing_screen.dart';
import 'package:yust_ui/src/widgets/yust_file_picker_base.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
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

  /// Whether the favorite toggle should be shown.
  final bool allowFavorites;

  /// Whether the delete action should be shown.
  final bool allowDelete;

  /// Called when the favorite flag of an image should be toggled.
  ///
  /// The callback is responsible for flipping [YustImage.favorite] and
  /// persisting the change; the screen re-renders afterwards.
  final void Function(YustImage image)? onToggleFavorite;

  /// Called when an image should be deleted. Should return `true` when the
  /// image was actually deleted so the screen can drop it from the gallery.
  final Future<bool> Function(YustImage image)? onDelete;

  /// Keep native resolution of the image
  final bool keepNativeResolution;

  const YustImageScreen({
    super.key,
    required this.images,
    this.onSave,
    this.activeImageIndex = 0,
    this.allowDrawing = false,
    this.allowShare = true,
    this.allowFavorites = false,
    this.allowDelete = false,
    this.onToggleFavorite,
    this.onDelete,
    this.keepNativeResolution = false,
  });

  static void navigateToScreen({
    required BuildContext context,
    required List<YustImage> images,
    int activeImageIndex = 0,
    bool allowDrawing = false,
    bool allowShare = true,
    bool allowFavorites = false,
    bool allowDelete = false,
    bool keepNativeResolution = false,
    void Function(YustImage image)? onToggleFavorite,
    Future<bool> Function(YustImage image)? onDelete,
    void Function(YustImage image, Uint8List newImage)? onSave,
  }) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => YustImageScreen(
            images: images,
            onSave: onSave,
            activeImageIndex: activeImageIndex,
            keepNativeResolution: keepNativeResolution,
            allowDrawing: allowDrawing,
            allowShare: allowShare,
            allowFavorites: allowFavorites,
            allowDelete: allowDelete,
            onToggleFavorite: onToggleFavorite,
            onDelete: onDelete,
          ),
        ),
      ),
    );
  }

  @override
  State<YustImageScreen> createState() => _YustImageScreenState();
}

class _YustImageScreenState extends State<YustImageScreen> {
  late int activeImageIndex;
  late PageController _pageController;
  late FocusNode _focusNode;

  /// Local, mutable copy of the images so the gallery can shrink when an image
  /// is deleted from within the viewer.
  late List<YustImage> _images;

  @override
  void initState() {
    _images = List<YustImage>.of(widget.images);
    activeImageIndex = widget.activeImageIndex;
    _pageController = PageController(initialPage: activeImageIndex);
    _focusNode = FocusNode();
    super.initState();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// Toggles the favorite flag of [image] via the parent callback and rebuilds.
  ///
  /// The callback flips [YustImage.favorite] on the shared instance, so a plain
  /// [setState] is enough to reflect the new state here.
  void _handleToggleFavorite(YustImage image) {
    widget.onToggleFavorite?.call(image);
    if (mounted) setState(() {});
  }

  /// Deletes [image] via the parent callback and removes it from the gallery.
  ///
  /// Pops the screen once the last image is gone, otherwise keeps showing the
  /// neighboring image.
  Future<void> _handleDelete(YustImage image) async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    final deleted = await onDelete(image);
    if (!deleted || !mounted) return;

    setState(() {
      final index = _images.indexOf(image);
      if (index >= 0) _images.removeAt(index);
      if (activeImageIndex >= _images.length && activeImageIndex > 0) {
        activeImageIndex = _images.length - 1;
      }
    });

    if (_images.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    if (_pageController.hasClients) {
      _pageController.jumpToPage(
        activeImageIndex.clamp(0, _images.length - 1),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: SafeArea(
          child: _images.length == 1
              ? _buildSingle(context)
              : _buildMultiple(context),
        ),
      ),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent && _images.length > 1) {
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
          activeImageIndex > 0) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
          activeImageIndex < _images.length - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  Widget _buildSingle(BuildContext context) {
    final image = _images.first;
    return Stack(
      children: [
        widget.keepNativeResolution
            ? _getNativeResolutionPhotoView(image)
            : _getScaledUpPhotoView(image),
        _buildActionBar(context, image),
      ],
    );
  }

  Widget _buildMultiple(BuildContext context) {
    return Stack(
      children: [
        PhotoViewGallery.builder(
          itemCount: _images.length,
          scrollPhysics: const BouncingScrollPhysics(),
          pageController: _pageController,
          onPageChanged: (index) {
            setState(() {
              activeImageIndex = index;
            });
          },
          builder: (BuildContext context, int index) {
            final currentImage = _images[index];

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
        if (kIsWeb && activeImageIndex > 0)
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
        if (kIsWeb && activeImageIndex < _images.length - 1)
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
        _buildActionBar(context, _images[activeImageIndex]),
      ],
    );
  }

  PhotoView _getScaledUpPhotoView(YustImage image) {
    return PhotoView(
      imageProvider: _loadImage(image),
      minScale: PhotoViewComputedScale.contained,
      heroAttributes: PhotoViewHeroAttributes(
        tag: _getImageTag(image),
      ),
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
    YustImage currentImage,
  ) {
    return PhotoViewGalleryPageOptions(
      imageProvider: _loadImage(currentImage),
      minScale: PhotoViewComputedScale.contained,
      heroAttributes: PhotoViewHeroAttributes(
        tag: _getImageTag(currentImage),
      ),
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
      heroAttributes: PhotoViewHeroAttributes(
        tag: _getImageTag(image),
      ),
      onTapUp: (context, details, controllerValue) {
        Navigator.pop(context);
      },
      child: _buildScalableImage(_loadImage(image)),
    );
  }

  PhotoViewGalleryPageOptions _getNativeResolutionPhotoViewOptions(
    YustImage currentImage,
    int index,
  ) {
    return PhotoViewGalleryPageOptions.customChild(
      child: _buildScalableImage(_loadImage(currentImage)),
      initialScale: PhotoViewComputedScale.contained,
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.covered * 2.0,
      heroAttributes: PhotoViewHeroAttributes(
        tag: _getImageTag(widget.images[index]),
      ),
      onTapUp: (context, details, controllerValue) {
        Navigator.pop(context);
      },
    );
  }

  String _getImageTag(YustImage image) =>
      image.path ?? image.getOriginalUrl() ?? '';

  Widget _buildScalableImage(ImageProvider<Object> imageProvider) {
    return Image(
      image: imageProvider,
      fit: BoxFit.scaleDown,
      loadingBuilder:
          (
            BuildContext context,
            Widget child,
            ImageChunkEvent? loadingProgress,
          ) {
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

  /// Top-right bar bundling all image actions (draw, delete, favorite, share)
  /// plus the web close button, laid out as a single row so buttons never
  /// overlap regardless of which ones are enabled.
  Widget _buildActionBar(BuildContext context, YustImage image) {
    final drawButton = (!kIsWeb && widget.allowDrawing && widget.onSave != null)
        ? _buildDrawButton(context, image)
        : null;
    final buttons = <Widget>[
      if (drawButton != null) drawButton,
      if (widget.allowDelete && widget.onDelete != null)
        _buildDeleteButton(context, image),
      if (widget.allowFavorites) _buildFavoriteButton(context, image),
      if (widget.allowShare) _buildShareButton(context, image),
      if (kIsWeb) _buildCloseButton(context),
    ];
    if (buttons.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i != 0) const SizedBox(width: 10),
              buttons[i],
            ],
          ],
        ),
      ),
    );
  }

  /// Wraps an action [icon] in the shared circular button used across the bar.
  Widget _actionButton({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
    Color iconColor = Colors.white,
  }) {
    return RepaintBoundary(
      child: CircleAvatar(
        backgroundColor: Colors.black,
        radius: 25,
        child: IconButton(
          iconSize: 35,
          color: iconColor,
          tooltip: tooltip,
          icon: Icon(icon),
          onPressed: onPressed,
        ),
      ),
    );
  }

  Widget? _buildDrawButton(BuildContext context, YustImage image) {
    if (image.getOriginalUrl() == null && image.devicePath == null) {
      return null;
    }
    return _actionButton(
      icon: Icons.draw_outlined,
      onPressed: () {
        YustImageDrawingScreen.navigateToScreen(
          context: context,
          image: _loadImage(image),
          onSave: (imageBytes) async {
            if (imageBytes != null) {
              widget.onSave!(image, imageBytes);
              setState(() {});
            }
          },
        );
      },
    );
  }

  Widget _buildFavoriteButton(BuildContext context, YustImage image) {
    return _actionButton(
      icon: image.favorite
          ? YustFilePickerBase.favoriteIcon
          : YustFilePickerBase.favoriteBorderIcon,
      iconColor: image.favorite
          ? YustFilePickerBase.favoriteActiveColor
          : Colors.white,
      tooltip: image.favorite
          ? LocaleKeys.removeFromFavorites.tr()
          : LocaleKeys.addToFavorites.tr(),
      onPressed: () => _handleToggleFavorite(image),
    );
  }

  Widget _buildDeleteButton(BuildContext context, YustImage image) {
    return _actionButton(
      icon: Icons.delete,
      tooltip: LocaleKeys.delete.tr(),
      onPressed: () => unawaited(_handleDelete(image)),
    );
  }

  Widget _buildCloseButton(BuildContext context) {
    return _actionButton(
      icon: Icons.close,
      onPressed: () => Navigator.pop(context),
    );
  }

  Widget _buildShareButton(BuildContext context, YustImage image) {
    return _actionButton(
      icon: kIsWeb ? Icons.download : Icons.share,
      onPressed: () => unawaited(
        YustUi.fileHelpers.downloadAndLaunchYustFile(
          context: context,
          file: image,
        ),
      ),
    );
  }

  /// because of the offline cache the file could be a stored online or on device
  ImageProvider<Object> _loadImage(YustImage image) {
    if (image.cached) {
      var imageFile = File(image.devicePath!);
      return MemoryImage(Uint8List.fromList(imageFile.readAsBytesSync()));
    } else {
      return NetworkImage(
        image.getOriginalUrl()!,
      );
    }
  }
}
