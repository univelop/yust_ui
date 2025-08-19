import '../../yust_ui.dart';

extension StringTranslateExtension on String {
  String tr({
    String? localeOverride,
    List<String>? args,
    Map<String, String>? namedArgs,
    String? gender,
  }) => YustUi.trCallback(
    this,
    localeOverride: localeOverride,
    args: args,
    namedArgs: namedArgs,
    gender: gender,
  );
}
