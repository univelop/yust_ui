import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

class YustFileListView<T extends YustFile> extends StatelessWidget {
  final List<T> files;
  final int? currentItemCount;
  final int? itemsPerPage;
  final Widget Function(BuildContext, T) itemBuilder;
  final Widget? loadMoreButton;

  const YustFileListView({
    super.key,
    required this.files,
    required this.itemBuilder,
    this.currentItemCount,
    this.itemsPerPage,
    this.loadMoreButton,
  });

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayFiles =
        currentItemCount != null && files.length > currentItemCount!
            ? files.sublist(0, currentItemCount!)
            : files;

    return Column(
      children: [
        ...displayFiles.map((file) => itemBuilder(context, file)),
        if (currentItemCount != null &&
            files.length > currentItemCount! &&
            loadMoreButton != null)
          loadMoreButton!,
      ],
    );
  }
}
