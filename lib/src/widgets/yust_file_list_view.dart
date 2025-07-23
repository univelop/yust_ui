import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';

class YustFileListView<T extends YustFile> extends StatelessWidget {
  final List<T> files;
  final int? currentItemCount;
  final int? itemsPerPage;
  final Widget Function(BuildContext, T) itemBuilder;
  final VoidCallback? onLoadMore;

  const YustFileListView({
    super.key,
    required this.files,
    required this.itemBuilder,
    this.currentItemCount,
    this.itemsPerPage,
    this.onLoadMore,
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
            onLoadMore != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.surface,
              ),
              onPressed: onLoadMore,
              icon: const Icon(Icons.refresh),
              label: Text(LocaleKeys.loadMore.tr()),
            ),
          ),
      ],
    );
  }
}
