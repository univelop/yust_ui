import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import 'yust_stream_builder.dart';

enum YustBuilderStatus {
  waiting,
  done,
  error;
}

class YustBuilderInsights {
  final YustBuilderStatus status;
  final Object? error;

  YustBuilderInsights(
    this.status, [
    this.error,
  ]);

  static YustBuilderInsights fromSnapshot(AsyncSnapshot snapshot) {
    return YustBuilderInsights(
      snapshot.hasError
          ? YustBuilderStatus.error
          : snapshot.connectionState == ConnectionState.waiting
              ? YustBuilderStatus.waiting
              : YustBuilderStatus.done,
      snapshot.error,
    );
  }
}

class YustDocBuilder<T extends YustDoc> extends StatefulWidget {
  final YustDocSetup<T> modelSetup;
  final String? id;
  final List<YustFilter>? filters;
  final List<YustOrderBy>? orderBy;
  final bool showLoadingSpinner;
  final bool showErrorScreen;
  final bool createIfNull;
  final Widget Function(T?, YustBuilderInsights, BuildContext) builder;

  const YustDocBuilder({
    super.key,
    required this.modelSetup,
    this.id,
    this.filters,
    this.orderBy,
    this.showLoadingSpinner = false,
    this.showErrorScreen = true,
    this.createIfNull = false,
    required this.builder,
  });

  @override
  YustDocBuilderState<T> createState() => YustDocBuilderState<T>();
}

class YustDocBuilderState<T extends YustDoc> extends State<YustDocBuilder<T>>
    with AutomaticKeepAliveClientMixin {
  // May not be null.
  Stream<T?>? _docStream;

  void initStream() {
    if (widget.id != null) {
      _docStream = Yust.databaseService.getStream<T>(
        widget.modelSetup,
        widget.id!,
      );
    } else {
      _docStream = Yust.databaseService.getFirstStream<T>(
        widget.modelSetup,
        filters: widget.filters,
        orderBy: widget.orderBy,
      );
    }
  }

  bool updateStreamConditionally(YustDocBuilder oldWidget) {
    var updated = false;

    if (widget.modelSetup != oldWidget.modelSetup ||
        widget.id != oldWidget.id ||
        !const ListEquality<dynamic>()
            .equals(widget.filters, oldWidget.filters) ||
        !const ListEquality<dynamic>()
            .equals(widget.orderBy, oldWidget.orderBy)) {
      updated = true;
      initStream();
    }

    return updated;
  }

  @override
  void initState() {
    super.initState();

    initStream();
  }

  @override
  void didUpdateWidget(YustDocBuilder oldWidget) {
    super.didUpdateWidget(oldWidget as YustDocBuilder<T>);

    updateStreamConditionally(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return YustStreamBuilder(
      stream: _docStream!,
      showLoadingSpinner: widget.showLoadingSpinner,
      showErrorScreen: widget.showErrorScreen,
      createIfNull: widget.createIfNull,
      init: () => Yust.databaseService.initDoc<T>(widget.modelSetup),
      builder: widget.builder,
    );
  }

  @override
  bool get wantKeepAlive => true;
}
