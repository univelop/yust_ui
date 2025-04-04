import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../yust_ui.dart';

class YustFileHandler {
  /// Path to the storage folder.
  final String storageFolderPath;

  /// Path to the Firebase document.
  final String? linkedDocPath;

  /// Attribute of the Firebase document.
  final String? linkedDocAttribute;

  bool newestFirst;

  /// shows if the _uploadFiles-process is currently running
  bool _uploadingCachedFiles = false;

  /// Steadily increasing by the [_reuploadFactor]. Indicates the next upload attempt.
  /// [_reuploadTime] is reset for each upload
  final Duration _reuploadTime = const Duration(milliseconds: 250);
  final double _reuploadFactor = 1.25;

  final List<YustFile> _yustFiles = [];

  final List<YustFile> _recentlyUploadedFiles = [];

  final List<String> _recentlyDeletedFileUrls = [];

  /// gets triggered after successful upload
  void Function()? onFileUploaded;

  YustFileHandler({
    required this.storageFolderPath,
    this.linkedDocAttribute,
    this.linkedDocPath,
    this.onFileUploaded,
    this.newestFirst = false,
  });

  List<YustFile> getFiles() {
    return _reverseListIfNewestFirst(_yustFiles);
  }

  List<YustFile> getOnlineFiles() {
    return _yustFiles.where((f) => f.url != null).toList();
  }

  List<YustFile> getCachedFiles() {
    return _yustFiles.where((f) => f.cached == true).toList();
  }

  List<YustFile> _reverseListIfNewestFirst(List<YustFile> list) {
    return newestFirst ? list.reversed.toList() : list;
  }

  Future<void> updateFiles(List<YustFile> onlineFiles,
      {bool loadFiles = false}) async {
    final copyOnlineFiles = List<YustFile>.from(onlineFiles);
    _removeLocalDeletedFiles(copyOnlineFiles);
    _removeOnlineDeletedFiles(copyOnlineFiles);

    _mergeOnlineFiles(_yustFiles, copyOnlineFiles, storageFolderPath);
    await _mergeCachedFiles(_yustFiles, linkedDocPath, linkedDocAttribute);

    if (loadFiles) _loadFiles();
  }

  void _removeOnlineDeletedFiles(List<YustFile> onlineFiles) {
    // to be up to date with the storage files, onlineFiles get merged which file that are:
    // 1. cached
    // 2. recently uploaded and not in the [onlineFiles]
    // 3. recently added and not cached (url == null)
    getOnlineFiles().forEach((file) {
      if (onlineFiles.any((oFile) => oFile.name == file.name)) {
        _recentlyUploadedFiles.remove(file);
      } else if (!file.cached &&
          file.url != null &&
          !_recentlyUploadedFiles.contains(file)) {
        _yustFiles.remove(file);
      }
    });
  }

  void _removeLocalDeletedFiles(List<YustFile> onlineFiles) {
    final copyRecentlyDeletedFiles = List.from(_recentlyDeletedFileUrls);
    onlineFiles.removeWhere((f) {
      if (_recentlyDeletedFileUrls.contains(f.url)) {
        copyRecentlyDeletedFiles.remove(f.url);
        return true;
      }
      return false;
    });
    _recentlyDeletedFileUrls
        .removeWhere((f) => !copyRecentlyDeletedFiles.contains(f));
  }

  void _loadFiles() {
    for (var yustFile in _yustFiles) {
      if (yustFile.cached) {
        yustFile.file = File(yustFile.devicePath!);
      }
    }
  }

  void _mergeOnlineFiles(List<YustFile> yustFiles, List<YustFile> onlineFiles,
      String storageFolderPath) async {
    for (var f in onlineFiles) {
      f.storageFolderPath = storageFolderPath;
    }
    _updateCachedFiles(yustFiles, onlineFiles);
    _mergeIntoYustFiles(yustFiles, onlineFiles);
  }

  void _updateCachedFiles(
      List<YustFile> yustFiles, List<YustFile> newYustFiles) {
    for (var newYustFile in newYustFiles) {
      var matchingFile = yustFiles
          .firstWhereOrNull((yustFile) => _equalFiles(yustFile, newYustFile));
      if (matchingFile != null) {
        matchingFile.update(newYustFile);
      }
    }
  }

  Future<void> _mergeCachedFiles(List<YustFile> yustFiles,
      String? linkedDocPath, String? linkedDocAttribute) async {
    if (linkedDocPath != null && linkedDocAttribute != null) {
      var cachedFiles = await loadCachedFiles();
      cachedFiles = cachedFiles
          .where((yustFile) =>
              yustFile.linkedDocPath == linkedDocPath &&
              yustFile.linkedDocAttribute == linkedDocAttribute)
          .toList();

      _mergeIntoYustFiles(yustFiles, cachedFiles);
    }
  }

  Future<void> addFile(YustFile yustFile) async {
    if (yustFile.name == null || yustFile.storageFolderPath == null) {
      throw (LocaleKeys.exceptionMissingNameOrStorageFolderPath.tr());
    }
    _yustFiles.add(yustFile);
    await _uploadFile(yustFile);
  }

  Future<void> updateFile(YustFile yustFile,
      {Uint8List? bytes, File? file}) async {
    yustFile.bytes = bytes;
    yustFile.file = file;
    await _uploadFile(yustFile);
  }

  Future<void> _uploadFile(YustFile yustFile) async {
    if (!kIsWeb && yustFile.cacheable) {
      await _saveFileOnDevice(yustFile);
      startUploadingCachedFiles();
    } else {
      await _uploadFileToStorage(yustFile);
    }
  }

  /// if online files get deleted while the device is offline, error is thrown
  Future<void> deleteFile(YustFile yustFile) async {
    if (yustFile.cached) {
      await _deleteCachedInformations(yustFile);
    } else {
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        throw (LocaleKeys.missingConnection.tr());
      }
      try {
        await _deleteFileFromStorage(yustFile);
        _recentlyDeletedFileUrls.add(yustFile.url!);
        // ignore: empty_catches
      } catch (e) {}
    }
    _yustFiles.removeWhere((f) => f.name == yustFile.name);
  }

  void startUploadingCachedFiles() {
    if (!_uploadingCachedFiles) {
      _uploadingCachedFiles = true;
      _uploadCachedFiles(_reuploadTime);
    }
  }

  Future<void> _uploadCachedFiles(Duration reuploadTime) async {
    await _validateCachedFiles();
    var cachedFiles = getCachedFiles();
    var length = cachedFiles.length;
    var uploadedFiles = 0;
    var uploadError = false;
    for (final yustFile in cachedFiles) {
      yustFile.lastError = null;
      try {
        _recentlyUploadedFiles.add(yustFile);
        await _uploadFileToStorage(yustFile);
        uploadedFiles++;
        await _deleteCachedInformations(yustFile);
        if (onFileUploaded != null) onFileUploaded!();
      } catch (error) {
        _recentlyUploadedFiles.remove(yustFile);
        yustFile.lastError = error.toString();
        uploadError = true;
      }
    }

    if (length < uploadedFiles + getCachedFiles().length) {
      // retry upload with reseted uploadTime, because new files where added
      uploadError = true;
      reuploadTime = _reuploadTime;
    }

    if (!uploadError) {
      _uploadingCachedFiles = false;
    } else {
      // saving cachedFiles, to store error log messages
      await _saveCachedFiles();

      Future.delayed(reuploadTime, () {
        reuploadTime = _incReuploadTime(reuploadTime);
        _uploadCachedFiles(reuploadTime);
      });
    }
  }

  Future<void> showFile(BuildContext context, YustFile yustFile) async {
    await EasyLoading.show(status: LocaleKeys.loadingFile.tr());
    try {
      if (!kIsWeb) {
        String filePath;
        if (yustFile.cached) {
          filePath = yustFile.devicePath!;
        } else if (yustFile.url == null) {
          throw YustException(LocaleKeys.exceptionFileNotFound.tr());
        } else {
          await EasyLoading.show(status: LocaleKeys.loadingFile.tr());
          filePath = '${await _getDirectory(yustFile)}${yustFile.name}';

          await Dio().download(yustFile.url!, filePath);
          await EasyLoading.dismiss();
        }
        var result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done) {
          await _launchBrowser(yustFile);
        }
      } else {
        await _launchBrowser(yustFile);
      }
      await EasyLoading.dismiss();
    } catch (e) {
      await EasyLoading.dismiss();
      await YustUi.alertService.showAlert(
          LocaleKeys.oops.tr(),
          LocaleKeys.alertCannotOpenFileWithError
              .tr(namedArgs: {'error': e.toString()}));
    }
  }

  List<YustFile> yustFilesFromJson(
      List<Map<String, String?>> jsonFiles, String storageFolderPath) {
    return jsonFiles
        .map((f) => YustFile.fromJson(f)..storageFolderPath = storageFolderPath)
        .toList();
  }

  /// works for cacheable and non-cacheable files
  void _mergeIntoYustFiles(List<YustFile> yustFiles, List<YustFile> newFiles) {
    for (final newFile in newFiles) {
      if (!yustFiles.any((yustFile) => _equalFiles(yustFile, newFile))) {
        yustFiles.add(newFile);
      }
    }
  }

  bool _equalFiles(YustFile yustFile, YustFile newFile) {
    var nameEQ = yustFile.name == newFile.name;
    if (yustFile.cacheable && newFile.cacheable) {
      return nameEQ &&
          yustFile.linkedDocPath == newFile.linkedDocPath &&
          yustFile.linkedDocAttribute == newFile.linkedDocAttribute;
    }
    return nameEQ;
  }

  Future<void> _saveFileOnDevice(YustFile yustFile) async {
    var devicePath = await _getDirectory(yustFile);

    yustFile.devicePath = '$devicePath${yustFile.name}';

    if (yustFile.bytes != null) {
      yustFile.file =
          await File(yustFile.devicePath!).writeAsBytes(yustFile.bytes!);
    } else if (yustFile.file != null) {
      await yustFile.file!.copy(yustFile.devicePath!);
    }

    await _saveCachedFiles();
  }

  Future<String> _getDirectory(YustFile yustFile) async {
    final tempDir = await getTemporaryDirectory();

    var devicePath = '${tempDir.path}/${yustFile.storageFolderPath}/';

    if (!Directory(devicePath).existsSync()) {
      await Directory(devicePath).create(recursive: true);
    }

    return devicePath;
  }

  Future<void> _uploadFileToStorage(YustFile yustFile) async {
    if (yustFile.storageFolderPath == null) {
      throw (YustException(LocaleKeys.exceptionMissingStorageFolderPath.tr()));
    }
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      throw (LocaleKeys.missingConnection.tr());
    }

    if (yustFile.cached) {
      if (await _isFileInCache(yustFile)) {
        yustFile.file = File(yustFile.devicePath!);
      } else {
        //returns without upload, because file is missing in cache
        return;
      }
    }

    final url = await Yust.fileService.uploadFile(
      path: yustFile.storageFolderPath!,
      name: yustFile.name!,
      file: yustFile.file,
      bytes: yustFile.bytes,
    );
    yustFile.url = url;
    await _addFileHash(yustFile);
    if (yustFile.cached) {
      await _updateDocAttribute(yustFile);
    }
  }

  Future<void> _addFileHash(YustFile yustFile) async {
    if (yustFile.file != null) {
      yustFile.hash =
          (await yustFile.file?.openRead().transform(md5).first).toString();
    } else {
      yustFile.hash = md5.convert(yustFile.bytes!.toList()).toString();
    }
  }

  Future<void> _updateDocAttribute(YustFile cachedFile) async {
    var firestoreData = await _getDocAttribute(cachedFile);

    var fileData = _tryGetExistingFileMap(cachedFile.name!, firestoreData);

    // If the file does not exist, we can just use the new cachedFile
    fileData ??= cachedFile.toJson();

    // Update all attributes, that may have changed for an updated
    fileData['name'] = cachedFile.name;
    fileData['modifiedAt'] = cachedFile.modifiedAt;
    fileData['url'] = cachedFile.url;
    fileData['hash'] = cachedFile.hash;

    if (firestoreData is Map) {
      firestoreData = fileData;
    }
    if (firestoreData is List) {
      firestoreData.removeWhere((f) => f['name'] == fileData['name']);
      firestoreData.add(fileData);
    }

    firestoreData ??= [fileData];

    await FirebaseFirestore.instance
        .doc(cachedFile.linkedDocPath!)
        .update({cachedFile.linkedDocAttribute!: firestoreData});
  }

  /// Get the existing file map for the given name (if it exists).
  /// If it doesn't exist, return null.
  dynamic _tryGetExistingFileMap(String fileName, dynamic yustFileOrYustFiles) {
    dynamic result;
    if (yustFileOrYustFiles is Map) {
      result = yustFileOrYustFiles;
    } else if (yustFileOrYustFiles is List) {
      result =
          yustFileOrYustFiles.firstWhereOrNull((f) => f['name'] == fileName);
    }
    if (result is Map) {
      return {...result};
    }
    return null;
  }

  Future<dynamic> _getDocAttribute(YustFile yustFile) async {
    // ignore: inference_failure_on_uninitialized_variable
    dynamic attribute;
    final doc = await getFirebaseDoc(yustFile.linkedDocPath!);

    if (existsDocData(doc)) {
      try {
        attribute = doc.get(yustFile.linkedDocAttribute!);
      } catch (e) {
        // edge case, image picker allows only one image, attribute must be initialized manually
        attribute = {'name': yustFile.name, 'url': null};
      }
    }
    return attribute;
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> getFirebaseDoc(
      String linkedDocPath) async {
    return await FirebaseFirestore.instance
        .doc(linkedDocPath)
        .get(const GetOptions(source: Source.server));
  }

  bool existsDocData(DocumentSnapshot<Map<String, dynamic>> doc) {
    return doc.exists && doc.data() != null;
  }

  Future<void> _deleteFileFromStorage(YustFile yustFile) async {
    if (yustFile.storageFolderPath != null) {
      await Yust.fileService
          .deleteFile(path: yustFile.storageFolderPath!, name: yustFile.name!);
    }
  }

  /// deletes cached file and device path. File is no longer cached
  Future<void> _deleteCachedInformations(YustFile yustFile) async {
    if (yustFile.devicePath != null &&
        File(yustFile.devicePath!).existsSync()) {
      await File(yustFile.devicePath!).delete();
    }
    yustFile.devicePath = null;
    yustFile.file = null;
    yustFile.bytes = null;

    await _saveCachedFiles();
  }

  /// Loads a list of all cached [YustFile]s.
  static Future<List<YustFile>> loadCachedFiles() async {
    var preferences = await SharedPreferences.getInstance();
    var temporaryJsonFiles = preferences.getString('YustCachedFiles') ?? '[]';

    var cachedFiles = <YustFile>[];
    jsonDecode(temporaryJsonFiles).forEach((dynamic fileJson) =>
        cachedFiles.add((fileJson is Map<String, dynamic> &&
                fileJson['type'] == YustImage.type)
            ? YustImage.fromLocalJson(fileJson)
            : YustFile.fromLocalJson(fileJson)));

    return cachedFiles;
  }

  /// Saves all cached [YustFile]s.
  Future<void> _saveCachedFiles() async {
    var yustFiles = getCachedFiles();
    var cachedFiles = await loadCachedFiles();

    // only change the files from THIS file handler (identity: linkedDocPath and -Attribute)
    cachedFiles.removeWhere(((yustFile) =>
        yustFile.linkedDocPath == linkedDocPath &&
        yustFile.linkedDocAttribute == linkedDocAttribute));
    cachedFiles.addAll(yustFiles);

    var jsonFiles = cachedFiles.map((file) => file.toLocalJson()).toList();

    var preferences = await SharedPreferences.getInstance();
    await preferences.setString('YustCachedFiles', jsonEncode(jsonFiles));
  }

  Future<void> _launchBrowser(YustFile file) async {
    final uri = Uri.parse(file.url ?? '');
    if (file.url != null && await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw YustException(LocaleKeys.alertCannotOpenFile.tr());
    }
  }

  /// Checks the cached files for corruption and deletes them if necessary.
  Future<void> _validateCachedFiles() async {
    var cachedFiles = getCachedFiles();
    // Checks if all required database addresses are initialized.
    for (var cachedFile in cachedFiles) {
      final doc =
          await FirebaseFirestore.instance.doc(cachedFile.linkedDocPath!).get();
      if (!doc.exists || doc.data() == null) {
        await deleteFile(cachedFile);
      }
    }
  }

  /// Limits [reuploadTime] to 10 minutes
  Duration _incReuploadTime(Duration reuploadTime) {
    return (reuploadTime * _reuploadFactor) > const Duration(minutes: 10)
        ? const Duration(minutes: 10)
        : reuploadTime * _reuploadFactor;
  }

  Future<bool> _isFileInCache(YustFile yustFile) async {
    return yustFile.devicePath != null &&
        await File(yustFile.devicePath!).exists();
  }
}
