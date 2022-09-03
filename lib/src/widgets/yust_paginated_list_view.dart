import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:paginate_firestore/paginate_firestore.dart';
import 'package:paginate_firestore/widgets/empty_display.dart';
import 'package:yust/yust.dart';

class YustPaginatedListView<T extends YustDoc> extends StatelessWidget {
  final YustDocSetup<T> modelSetup;
  final Widget Function(BuildContext, T?, int) listItemBuilder;
  final List<String> orderBy;
  final List<YustFilter>? filters;
  final bool Function(T doc)? hideItem;
  final ScrollController? scrollController;
  final Widget? header;
  final Widget? footer;
  final Widget? emptyInfo;

  const YustPaginatedListView({
    Key? key,
    required this.modelSetup,
    required this.listItemBuilder,
    required this.orderBy,
    this.filters,
    this.hideItem,
    this.scrollController,
    this.emptyInfo,
    this.header,
    this.footer,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final query = Yust.databaseService
        .getQuery(modelSetup, filters: filters, orderByList: orderBy) as Query;

    return PaginateFirestore(
      scrollController: scrollController,
      header: header,
      footer: footer,
      onEmpty: emptyInfo ?? const EmptyDisplay(),
      itemBuilderType: PaginateBuilderType.listView,
      itemBuilder: (context, documentSnapshot, index) =>
          _itemBuilder(index, context, documentSnapshot[index]),
      // orderBy is compulsary to enable pagination
      query: query,
      itemsPerPage: 50,
      isLive: true,
      initialLoader: SingleChildScrollView(
        controller: scrollController,
        child: const CircularProgressIndicator(),
      ),
    );
  }

  Widget _itemBuilder(
      int index, BuildContext context, DocumentSnapshot documentSnapshot) {
    final doc =
        Yust.databaseService.transformDoc<T>(modelSetup, documentSnapshot);
    if (doc == null) {
      return const SizedBox.shrink();
    }
    if (hideItem != null && hideItem!(doc) == true) {
      return const SizedBox.shrink();
    }
    return listItemBuilder(context, doc, index);
  }
}
