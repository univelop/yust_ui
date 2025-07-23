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

    // Sort files by name
    final sortedFiles = List<T>.from(files);
    sortedFiles.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

    final displayFiles =
        currentItemCount != null && sortedFiles.length > currentItemCount!
            ? sortedFiles.sublist(0, currentItemCount!)
            : sortedFiles;

    return Column(
      children: [
        ...displayFiles.map((file) => itemBuilder(context, file)),
        if (currentItemCount != null &&
            sortedFiles.length > currentItemCount! &&
            loadMoreButton != null)
          loadMoreButton!,
      ],
    );
  }
}
