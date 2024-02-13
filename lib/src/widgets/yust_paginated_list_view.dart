import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ui_firestore/firebase_ui_firestore.dart';
import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

class YustPaginatedListView<T extends YustDoc> extends StatelessWidget {
  final YustDocSetup<T> modelSetup;
  final Widget Function(BuildContext, T?) listItemBuilder;
  final List<YustOrderBy> orderBy;
  final List<YustFilter>? filters;
  final bool Function(T doc)? hideItem;
  final ScrollController? scrollController;
  final Widget? emptyInfo;
  final bool reverse;

  const YustPaginatedListView({
    super.key,
    required this.modelSetup,
    required this.listItemBuilder,
    required this.orderBy,
    this.filters,
    this.hideItem,
    this.scrollController,
    this.emptyInfo,
    this.reverse = false,
  });

  @override
  Widget build(BuildContext context) {
    final query = Yust.databaseService
        .getQuery(modelSetup, filters: filters, orderBy: orderBy) as Query;

    return FirestoreListView(
      key: key,
      controller: scrollController,
      emptyBuilder: (_) => emptyInfo ?? const SizedBox(),
      itemBuilder: (context, documentSnapshot) =>
          _itemBuilder(context, documentSnapshot),
      // orderBy is compulsory to enable pagination
      query: query,
      reverse: reverse,
      pageSize: 50,
      loadingBuilder: (_) => SingleChildScrollView(
        controller: scrollController,
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Widget _itemBuilder(
      BuildContext context, QueryDocumentSnapshot<Object?> documentSnapshot) {
    final doc =
        Yust.databaseService.transformDoc<T>(modelSetup, documentSnapshot);
    if (doc == null) {
      return const SizedBox.shrink();
    }
    if (hideItem != null && hideItem!(doc) == true) {
      return const SizedBox.shrink();
    }
    return listItemBuilder(context, doc);
  }
}
