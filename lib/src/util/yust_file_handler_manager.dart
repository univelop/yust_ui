import 'dart:async';

import 'package:collection/collection.dart';
import 'package:yust/yust.dart';

import 'yust_file_handler.dart';

class YustFileHandlerManager {
  List<YustFileHandler> fileHandlers = [];

  YustFileHandler createFileHandler({
    required String storageFolderPath,
    String? linkedDocAttribute,
    String? linkedDocPath,
    bool newestFirst = false,
    void Function()? onFileUploaded,
  }) {
    var newFileHandler = getFileHandler(linkedDocAttribute, linkedDocPath);

    if (newFileHandler == null) {
      newFileHandler = YustFileHandler(
        storageFolderPath: storageFolderPath,
        linkedDocAttribute: linkedDocAttribute,
        linkedDocPath: linkedDocPath,
        onFileUploaded: onFileUploaded,
        newestFirst: newestFirst,
      );
      if (linkedDocAttribute != null && linkedDocPath != null) {
        fileHandlers.add(newFileHandler);
      }
    } else {
      newFileHandler.onFileUploaded = onFileUploaded ?? () {};
      newFileHandler.newestFirst = newestFirst;
    }

    return newFileHandler;
  }

  YustFileHandler? getFileHandler(
      String? linkedDocAttribute, String? linkedDocPath) {
    var newFileHandler = fileHandlers.firstWhereOrNull(
      (fileHandler) =>
          fileHandler.linkedDocAttribute == linkedDocAttribute &&
          fileHandler.linkedDocPath == linkedDocPath,
    );
    return newFileHandler;
  }

  /// Uploads all cached files. Should be started after device restart
  /// creates for each unique linkedDocPath + linkedDocAttribute address a fileHandler
  Future<void> uploadCachedFiles() async {
    var cachedFiles =
        await YustFileHandler.loadCachedFiles();
    while (cachedFiles.isNotEmpty) {
      var file = cachedFiles.first;
      var fileHandler = createFileHandler(
        storageFolderPath: file.storageFolderPath ?? '',
        linkedDocAttribute: file.linkedDocAttribute,
        linkedDocPath: file.linkedDocPath,
      );

      cachedFiles.removeWhere((YustFile f) =>
          f.linkedDocAttribute == file.linkedDocAttribute &&
          f.linkedDocPath == file.linkedDocPath);
      await fileHandler.updateFiles([]);
      fileHandler.startUploadingCachedFiles();
    }
  }
}