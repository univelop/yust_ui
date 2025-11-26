import 'package:yust/yust.dart';

extension YustFileExtension on YustFile {
  bool hasThumbnail() => thumbnails?.isNotEmpty ?? false;

  String? getOriginalUrl(String? baseUrl, String? signedUrlPart) {
    if (baseUrl == null || signedUrlPart == null) return url;
    return '${_tryAppendSlash(baseUrl)}$path?$signedUrlPart';
  }

  String? getThumbnailUrl(String baseUrl, String signedUrlPart) {
    if (thumbnails == null) return null;
    final thumbnailPath = thumbnails![YustFileThumbnailSize.small];

    return '${_tryAppendSlash(baseUrl)}$thumbnailPath?$signedUrlPart';
  }

  String? _tryAppendSlash(String baseUrl) =>
      baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
}
