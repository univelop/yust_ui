import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import 'yust_doc_builder.dart';

class YustDocsBuilder<T extends YustDoc> extends StatefulWidget {
  final YustDocSetup<T> modelSetup;
  final List<YustFilter>? filters;
  final List<String>? orderBy;
  final bool showLoadingSpinner;
  final Widget? loadingIndicator;
  final int? limit;

  /// There will never be a null for the list given.
  final Widget Function(List<T>, YustBuilderInsights, BuildContext) builder;

  const YustDocsBuilder({
    Key? key,
    required this.modelSetup,
    this.filters,
    this.orderBy,
    bool? doNotWait,
    this.showLoadingSpinner = false,
    this.loadingIndicator,
    this.limit,
    required this.builder,
  }) : super(key: key);

  @override
  YustDocsBuilderState<T> createState() => YustDocsBuilderState<T>();
}

class YustDocsBuilderState<T extends YustDoc>
    extends State<YustDocsBuilder<T>> {
  late Stream<List<T>> _docStream;

  void initStream() {
    _docStream = Yust.databaseService.getDocs<T>(
      widget.modelSetup,
      filters: widget.filters,
      orderByList: widget.orderBy,
      limit: widget.limit,
    );
  }

  void updateStreamConditionally(YustDocsBuilder oldWidget) {
    if (widget.modelSetup != oldWidget.modelSetup ||
        !const ListEquality<YustFilter>()
            .equals(widget.filters, oldWidget.filters) ||
        !const ListEquality<dynamic>()
            .equals(widget.orderBy, oldWidget.orderBy)) {
      initStream();
    }
  }

  @override
  void initState() {
    super.initState();

    initStream();
  }

  @override
  void didUpdateWidget(YustDocsBuilder oldWidget) {
    super.didUpdateWidget(oldWidget as YustDocsBuilder<T>);

    updateStreamConditionally(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<T>>(
      stream: _docStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          throw snapshot.error!;
        }
        final opts = YustBuilderInsights(
          waiting: snapshot.connectionState == ConnectionState.waiting,
        );
        if (opts.waiting! && widget.showLoadingSpinner) {
          return widget.loadingIndicator != null
              ? widget.loadingIndicator!
              : const Center(child: CircularProgressIndicator());
        }
        return widget.builder(snapshot.data ?? [], opts, context);
      },
    );
  }
}
