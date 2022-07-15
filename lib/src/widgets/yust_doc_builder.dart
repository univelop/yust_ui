import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

class YustBuilderInsights {
  bool? waiting;

  YustBuilderInsights({this.waiting});
}

class YustDocBuilder<T extends YustDoc> extends StatefulWidget {
  final YustDocSetup<T> modelSetup;
  final String? id;
  final List<YustFilter>? filters;
  final List<String>? orderBy;
  final bool showLoadingSpinner;
  final bool createIfNull;
  final Widget Function(T?, YustBuilderInsights, BuildContext) builder;

  YustDocBuilder({
    Key? key,
    required this.modelSetup,
    this.id,
    this.filters,
    this.orderBy,
    bool? doNotWait,
    this.showLoadingSpinner = false,
    this.createIfNull = false,
    required this.builder,
  }) : super(key: key);

  @override
  YustDocBuilderState<T> createState() => YustDocBuilderState<T>();
}

class YustDocBuilderState<T extends YustDoc> extends State<YustDocBuilder<T>> {
  /// May not be null.
  Stream<T?>? _docStream;

  void initStream() {
    if (widget.id != null) {
      _docStream = Yust.databaseService.getDoc<T>(
        widget.modelSetup,
        widget.id!,
      );
    } else {
      _docStream = Yust.databaseService.getFirstDoc<T>(
        widget.modelSetup,
        filters: widget.filters,
        orderByList: widget.orderBy,
      );
    }
  }

  bool updateStreamConditionally(YustDocBuilder oldWidget) {
    var updated = false;

    if (widget.modelSetup != oldWidget.modelSetup ||
        widget.id != oldWidget.id ||
        !ListEquality<dynamic>().equals(widget.filters, oldWidget.filters) ||
        !ListEquality<dynamic>().equals(widget.orderBy, oldWidget.orderBy)) {
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
    return StreamBuilder<T?>(
      stream: _docStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          throw snapshot.error!;
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            widget.showLoadingSpinner) {
          return Center(child: CircularProgressIndicator());
        }
        var doc = snapshot.data;
        if (doc == null && widget.createIfNull) {
          doc = Yust.databaseService.initDoc<T>(widget.modelSetup);
        }
        final opts = YustBuilderInsights(
          waiting: snapshot.connectionState == ConnectionState.waiting,
        );
        return widget.builder(doc, opts, context);
      },
    );
  }
}
