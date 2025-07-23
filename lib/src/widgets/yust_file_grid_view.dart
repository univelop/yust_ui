import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';

class YustFileGridView<T extends YustFile> extends StatelessWidget {
  final List<T> files;
  final int currentItemCount;
  final int itemsPerPage;
  final Widget Function(BuildContext, T?) itemBuilder;
  final VoidCallback? onLoadMore;

  const YustFileGridView({
    super.key,
    required this.files,
    required this.currentItemCount,
    required this.itemsPerPage,
    required this.itemBuilder,
    this.onLoadMore,
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
        if (files.length > currentItemCount && onLoadMore != null)
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
        const SizedBox(height: 2)
      ],
    );
  }

  GridView _buildGridView(BuildContext context) {
    final displayFiles = files.length > currentItemCount
        ? files.sublist(0, currentItemCount)
        : files;

    return GridView.extent(
      shrinkWrap: true,
      maxCrossAxisExtent: 180,
      primary: false,
      mainAxisSpacing: 2,
      crossAxisSpacing: 2,
      children: displayFiles.map((file) {
        return itemBuilder(context, file);
      }).toList(),
    );
  }
}
