import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

class YustFileListView<T extends YustFile> extends StatelessWidget {
  final List<T> files;
  final int totalFileCount;
  final Widget Function(BuildContext, T) itemBuilder;
  final Widget loadMoreButton;

  const YustFileListView({
    super.key,
    required this.files,
    required this.itemBuilder,
    required this.totalFileCount,
    required this.loadMoreButton,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        ...files.map((file) => itemBuilder(context, file)),
        if (totalFileCount > files.length) loadMoreButton,
      ],
    );
  }
}
