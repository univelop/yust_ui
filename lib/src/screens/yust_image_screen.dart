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
  final List<YustFile> files;

  final int activeImageIndex;
  final void Function(YustFile file, Uint8List newImage) onSave;

  /// Indicates whether drawing is allowed on the image.
  ///
  /// This feature is only available on mobile and desktop apps.
  final bool allowDrawing;

  const YustImageScreen({
    super.key,
    required this.files,
    required this.onSave,
    this.activeImageIndex = 0,
    this.allowDrawing = false,
  });

  static void navigateToScreen({
    required BuildContext context,
    required List<YustFile> files,
    int activeImageIndex = 0,
    bool allowDrawing = false,
    required void Function(YustFile file, Uint8List newImage) onSave,
  }) {
    unawaited(
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => YustImageScreen(
          files: files,
          onSave: onSave,
          activeImageIndex: activeImageIndex,
          allowDrawing: allowDrawing,
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
          child: widget.files.length == 1
              ? _buildSingle(context)
              : _buildMultiple(context)),
    );
  }

  Widget _buildSingle(BuildContext context) {
    final file = widget.files.first;
    return Stack(children: [
      PhotoView(
        imageProvider: _getImageOfUrl(file),
        minScale: PhotoViewComputedScale.contained,
        heroAttributes: PhotoViewHeroAttributes(tag: file.url ?? ''),
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
      ),
      if (!kIsWeb && widget.allowDrawing) _buildDrawButton(context, file),
      if (kIsWeb) _buildCloseButton(context),
      _buildShareButton(context, file),
    ]);
  }

  Widget _buildMultiple(BuildContext context) {
    return Stack(
      children: [
        PhotoViewGallery.builder(
          itemCount: widget.files.length,
          scrollPhysics: const BouncingScrollPhysics(),
          pageController: _pageController,
          onPageChanged: (index) {
            setState(() {
              activeImageIndex = index;
            });
          },
          builder: (BuildContext context, int index) {
            return PhotoViewGalleryPageOptions(
              imageProvider: _getImageOfUrl(widget.files[index]),
              minScale: PhotoViewComputedScale.contained,
              heroAttributes:
                  PhotoViewHeroAttributes(tag: widget.files[index].url ?? ''),
              onTapUp: (context, details, controllerValue) {
                Navigator.pop(context);
              },
            );
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
        if (!kIsWeb && widget.allowDrawing)
          _buildDrawButton(context, widget.files[activeImageIndex]),
        if (kIsWeb) _buildCloseButton(context),
        _buildShareButton(context, widget.files[activeImageIndex]),
      ],
    );
  }

  Widget _buildDrawButton(BuildContext context, YustFile file) {
    if (file.url == null && file.devicePath == null) {
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
                        image: _getImageOfUrl(file),
                        onSave: (image) async {
                          if (image != null) {
                            widget.onSave(file, image);
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

  Widget _buildShareButton(BuildContext context, YustFile file) {
    return Positioned(
      right: kIsWeb ? 70.0 : 0.0,
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
                    YustUi.fileHelpers.downloadAndLaunchFile(
                        context: context, url: file.url!, name: file.name!);
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
  ImageProvider<Object> _getImageOfUrl(YustFile file) {
    if (file.cached) {
      var imageFile = File(file.devicePath!);
      return MemoryImage(Uint8List.fromList(imageFile.readAsBytesSync()));
    } else {
      return NetworkImage(file.url!);
    }
  }
}
