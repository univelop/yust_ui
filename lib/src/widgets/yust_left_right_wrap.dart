import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A widget that arranges two children side by side, wrapping them if necessary.
/// The left child is aligned to the left, and the right child is aligned to the right.
/// If the combined width of the children exceeds the available width, they will be
/// wrapped to the next line.
class YustLeftRightWrap extends MultiChildRenderObjectWidget {
  YustLeftRightWrap({
    super.key,
    required Widget left,
    required Widget right,
  }) : super(children: [left, right]);

  @override
  RenderYustLeftRightWrap createRenderObject(BuildContext context) {
    return RenderYustLeftRightWrap(children: []);
  }
}

class YustLeftRightWrapParentData extends ContainerBoxParentData<RenderBox> {}

class RenderYustLeftRightWrap extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, YustLeftRightWrapParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          YustLeftRightWrapParentData
        > {
  RenderYustLeftRightWrap({
    required List<RenderBox> children,
  }) {
    addAll(children);
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! YustLeftRightWrapParentData) {
      child.parentData = YustLeftRightWrapParentData();
    }
  }

  @override
  void performLayout() {
    final BoxConstraints childConstraints = constraints.loosen();

    final RenderBox leftChild = firstChild!;
    final RenderBox rightChild = lastChild!;

    leftChild.layout(childConstraints, parentUsesSize: true);
    rightChild.layout(childConstraints, parentUsesSize: true);

    final YustLeftRightWrapParentData leftParentData =
        leftChild.parentData as YustLeftRightWrapParentData;
    final YustLeftRightWrapParentData rightParentData =
        rightChild.parentData as YustLeftRightWrapParentData;

    // Whether the rightChild should be wrapped to the next line.
    // e.g. the combined width of the children exceeds the total available width.
    final bool wrapped =
        leftChild.size.width + rightChild.size.width > constraints.maxWidth;

    // We want to vertically center the children in the available space.
    final double heightDifferenceLeft = max(
      rightChild.size.height - leftChild.size.height,
      0,
    );
    final double heightDifferenceRight = max(
      leftChild.size.height - rightChild.size.height,
      0,
    );

    // If wrapping, calculate the Y offset to position the right child beneath the left.
    final double wrappedHeightRight =
        leftChild.size.height + (heightDifferenceRight / 2);

    // Horizontal offset to right-align the right child.
    final double widthOffsetRight =
        constraints.maxWidth - rightChild.size.width;

    leftParentData.offset = Offset(0, heightDifferenceLeft / 2);

    // Position the right child:
    // - If wrapped, it will be placed below the left child.
    // - If not wrapped, it will be right-aligned.
    rightParentData.offset = Offset(
      widthOffsetRight,
      wrapped ? wrappedHeightRight : heightDifferenceRight / 2,
    );

    // Set the final size of this render box:
    // - If wrapped, both children will be stacked vertically.
    // - If not, the tallest child will be used for the height.
    size = Size(
      constraints.maxWidth,
      wrapped
          ? leftChild.size.height + rightChild.size.height
          : max(leftChild.size.height, rightChild.size.height),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }
}
