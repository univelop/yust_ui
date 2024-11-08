import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import 'yust_doc_builder.dart';

class YustDocsBuilder<T extends YustDoc> extends StatefulWidget {
  final YustDocSetup<T> modelSetup;
  final List<YustFilter>? filters;
  final List<YustOrderBy>? orderBy;
  final bool showLoadingSpinner;
  final bool showErrorScreen;
  final Widget? loadingIndicator;
  final int? limit;

  /// There will never be a null for the list given.
  final Widget Function(List<T>, YustBuilderInsights, BuildContext) builder;

  const YustDocsBuilder({
    super.key,
    required this.modelSetup,
    this.filters,
    this.orderBy,
    this.showLoadingSpinner = false,
    this.showErrorScreen = true,
    this.loadingIndicator,
    this.limit,
    required this.builder,
  });

  @override
  YustDocsBuilderState<T> createState() => YustDocsBuilderState<T>();
}

class YustDocsBuilderState<T extends YustDoc> extends State<YustDocsBuilder<T>>
    with AutomaticKeepAliveClientMixin {
  late Stream<List<T>> _docStream;

  void initStream() {
    _docStream = Yust.databaseService.getListStream<T>(
      widget.modelSetup,
      filters: widget.filters,
      orderBy: widget.orderBy,
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
    super.build(context);
    return StreamBuilder<List<T>>(
      stream: _docStream,
      builder: (context, snapshot) {
        final insights = YustBuilderInsights.fromSnapshot(snapshot);
        if (insights.status == YustBuilderStatus.waiting &&
            widget.showLoadingSpinner) {
          return widget.loadingIndicator != null
              ? widget.loadingIndicator!
              : const Center(child: CircularProgressIndicator());
        }
        if (insights.status == YustBuilderStatus.error &&
            widget.showLoadingSpinner) {
          return Center(
              child: Text(LocaleKeys.errorDuringLoading.tr(),
                  style: const TextStyle(color: Colors.red)));
        }
        return widget.builder(snapshot.data ?? [], insights, context);
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}
