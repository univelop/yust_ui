import 'dart:io';
import 'dart:typed_data';
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

  const YustImageScreen({
    Key? key,
    required this.files,
    required this.onSave,
    this.activeImageIndex = 0,
  }) : super(key: key);

  static const String routeName = '/imageScreen';

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
    if (widget.files.length == 1) {
      return _buildSingle(context);
    } else {
      return _buildMultiple(context);
    }
  }

  Widget _buildSingle(BuildContext context) {
    final file = widget.files.first;
    if (file.url == null) {
      return const SizedBox.shrink();
    }
    return Stack(children: [
      PhotoView(
        imageProvider: _getImageOfUrl(file),
        minScale: PhotoViewComputedScale.contained,
        heroAttributes: PhotoViewHeroAttributes(tag: file.url!),
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
      _buildDrawButton(context, file),
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
        if (!kIsWeb) _buildDrawButton(context, widget.files[activeImageIndex]),
        if (kIsWeb) _buildCloseButton(context),
        _buildShareButton(context, widget.files[activeImageIndex]),
      ],
    );
  }

  Widget _buildDrawButton(BuildContext context, YustFile file) {
    //TODO: 910 differ between cached and online

    if (file.url == null && file.file == null) {
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
                    Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (context) => YustImageDrawingScreen(
                        image: _getImageOfUrl(file),
                        onSave: (image) {        
                          if (image != null) {
                            setState(() {
                              widget.onSave(file, image);
                            });
                          }
                        },
                      ),
                    ));
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
      return FileImage(File(file.devicePath!));
    } else {
      return NetworkImage(file.url!);
    }
  }
}
