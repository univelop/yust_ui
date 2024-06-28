import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import 'yust_doc_builder.dart';

class YustStreamBuilder<T extends YustDoc> extends StatefulWidget {
  final Stream<T?> stream;
  final bool showLoadingSpinner;
  final bool showErrorScreen;
  final bool createIfNull;
  final T Function() init;
  final Widget Function(T?, YustBuilderInsights, BuildContext) builder;

  const YustStreamBuilder({
    super.key,
    required this.stream,
    this.showLoadingSpinner = false,
    this.showErrorScreen = true,
    this.createIfNull = false,
    required this.init,
    required this.builder,
  });

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
        final insights = YustBuilderInsights.fromSnapshot(snapshot);
        if (insights.status == YustBuilderStatus.waiting &&
            widget.showLoadingSpinner) {
          return const Center(child: CircularProgressIndicator());
        }
        if (insights.status == YustBuilderStatus.error &&
            widget.showLoadingSpinner) {
          return Center(child: Text(LocaleKeys.errorDuringLoading.tr(), style: const TextStyle(color: Colors.red)));
        }
        var doc = snapshot.data;
        if (doc == null && widget.createIfNull) {
          doc = widget.init();
        }
        return widget.builder(doc, insights, context);
      },
    );
  }
}
