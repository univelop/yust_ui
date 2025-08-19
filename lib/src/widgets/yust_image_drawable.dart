import 'dart:ui';

import 'package:flutter/material.dart' as mt;
import 'package:flutter_painter/flutter_painter.dart';

/// Drawable to use an image as a background.
@mt.immutable
class YustImageDrawable extends BackgroundDrawable {
  /// The image to be used as a background.
  final Image image;

  /// Creates a [ImageBackgroundDrawable] to use an image as a background.
  const YustImageDrawable({required this.image});

  /// Draws the image on the provided [canvas] of size [size].
  @override
  void draw(Canvas canvas, Size size) {
    var height = _calcHeight(size);
    var width = _calcWidth(size);
    var offset = _calcOffset(size, width, height);

    canvas.clipRect(Rect.fromPoints(offset, Offset(width, height) + offset));
    canvas.drawImageRect(
      image,
      Rect.fromPoints(
        Offset.zero,
        Offset(image.width.toDouble(), image.height.toDouble()),
      ),
      Rect.fromPoints(offset, Offset(width, height) + offset),
      Paint(),
    );
  }

  Offset _calcOffset(Size size, double width, double height) {
    var distHeight = _isVertical(image) ? (size.height - height) / 2.0 : 0.0;
    var distWidth = _isVertical(image) ? 0.0 : (size.width - width) / 2.0;
    return Offset(distWidth, distHeight);
  }

  double _calcHeight(Size size) {
    var verticalFactor = size.width / image.width;
    return (_isVertical(image) ? (image.height * verticalFactor) : size.height)
        .toDouble();
  }

  double _calcWidth(Size size) {
    var horizontalFactor = size.height / image.height;
    return (_isVertical(image) ? size.width : (image.width * horizontalFactor))
        .toDouble();
  }

  bool _isVertical(Image image) {
    return image.width > image.height;
  }
}

/// An extension on ui.Image to create a background drawable easily.
extension YustImageDrawableGetter on Image {
  /// Returns an [ImageBackgroundDrawable] of the current [Image].
  YustImageDrawable get yustBackgroundDrawable =>
      YustImageDrawable(image: this);
}
