import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

class YustFileGridView<T extends YustFile> extends StatelessWidget {
  final List<T> files;
  final int totalFileCount;
  final Widget Function(BuildContext, T?) itemBuilder;
  final Widget loadMoreButton;

  const YustFileGridView({
    super.key,
    required this.files,
    required this.totalFileCount,
    required this.itemBuilder,
    required this.loadMoreButton,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildGridView(context),
        if (totalFileCount > files.length) loadMoreButton,
        const SizedBox(height: 2),
      ],
    );
  }

  GridView _buildGridView(BuildContext context) => GridView.extent(
    shrinkWrap: true,
    maxCrossAxisExtent: 180,
    primary: false,
    mainAxisSpacing: 2,
    crossAxisSpacing: 2,
    children: files.map((file) {
      return itemBuilder(context, file);
    }).toList(),
  );
}
