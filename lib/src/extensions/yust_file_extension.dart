import 'package:yust/yust.dart';

extension YustFileExtension on YustFile {
  /// Returns a signed url with the optional signed query parameters.
  ///
  /// If no signed url query parameters are provided, the original url is returned.
  String? getSignedUrl(String? signedUrlQueryParameters) {
    if (url == null) return null;
    if (signedUrlQueryParameters == null) return url;

    final hasQueryParameters = Uri.parse(url!).queryParameters.isNotEmpty;

    return '$url${hasQueryParameters ? '&' : '?'}$signedUrlQueryParameters';
  }
}
