import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import 'yust_doc_builder.dart';

class YustStreamBuilder<T extends YustDoc> extends StatefulWidget {
  final Stream<T?> stream;
  final bool showLoadingSpinner;
  final bool createIfNull;
  final T Function() init;
  final Widget Function(T?, YustBuilderInsights, BuildContext) builder;

  const YustStreamBuilder({
    Key? key,
    required this.stream,
    this.showLoadingSpinner = false,
    this.createIfNull = false,
    required this.init,
    required this.builder,
  }) : super(key: key);

  @override
  YustStreamBuilderState<T> createState() => YustStreamBuilderState<T>();
}

class YustStreamBuilderState<T extends YustDoc>
    extends State<YustStreamBuilder<T>> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T?>(
      stream: widget.stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          throw snapshot.error!;
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            widget.showLoadingSpinner) {
          return const Center(child: CircularProgressIndicator());
        }
        var doc = snapshot.data;
        if (doc == null && widget.createIfNull) {
          doc = widget.init();
        }
        final opts = YustBuilderInsights(
          waiting: snapshot.connectionState == ConnectionState.waiting,
        );
        return widget.builder(doc, opts, context);
      },
    );
  }
}
