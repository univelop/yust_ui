import 'dart:io';
import 'dart:typed_data';

import 'package:yust/src/services/yust_file_service.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/util/offline/yust_file_operation_manager.dart';

/// What a [FakeFileService] is asked to do with a file.
enum FakeFileStepKind {
  upload,
  download,
  copy,
  delete,
  documentWrite,
  documentRemoval,
}

/// One request a [FakeFileService] receives.
class FakeFileStep {
  const FakeFileStep(this.kind, this.fileName);

  final FakeFileStepKind kind;
  final String fileName;
}

/// Storage and the linked document in memory, for driving a
/// [YustFileOperationManager] through its real operations.
///
/// Every request is recorded in [steps] and then awaits [onStep]: a throw fails
/// the request, a pending future holds it. Hand-rolled because
/// `YustFileServiceMocked` only runs without `dart:ui`.
class FakeFileService implements YustFileService {
  /// Bytes of the stored objects, by name.
  final Map<String, Uint8List> objectsByName = {};

  /// Every request received, in order.
  final List<FakeFileStep> steps = [];

  /// Runs before each request.
  Future<void> Function(FakeFileStep step)? onStep;

  /// Names of the stored objects.
  Set<String> get objectNames => objectsByName.keys.toSet();

  /// A document writer whose writes and removals run through [onStep].
  late final YustOfflineFileDocumentWriter documentWriter = _FakeDocumentWriter(
    this,
  );

  Future<void> _runStep(FakeFileStepKind kind, String fileName) async {
    final step = FakeFileStep(kind, fileName);
    steps.add(step);
    await onStep?.call(step);
  }

  @override
  Future<String> uploadFile({
    required String path,
    required String name,
    File? file,
    Uint8List? bytes,
    Map<String, String>? metadata,
    String? contentDisposition,
    String? bucketName,
    bool? createThumbnail,
    String? linkedDocPath,
    String? linkedDocAttribute,
  }) async {
    await _runStep(FakeFileStepKind.upload, name);
    objectsByName[name] =
        bytes ?? (file != null ? await file.readAsBytes() : Uint8List(0));
    return 'https://cdn.test/$name';
  }

  /// The stored bytes, or the name's bytes for an object the test never stored.
  @override
  Future<Uint8List> downloadFileOrThrow({
    required String path,
    required String name,
    int maxSize = YustFile.maxSizeInBytes,
    String? bucketName,
  }) async {
    await _runStep(FakeFileStepKind.download, name);
    return objectsByName[name] ?? Uint8List.fromList(name.codeUnits);
  }

  @override
  Future<String> copyFile({
    required String path,
    required String name,
    required String newName,
    String? bucketName,
    bool? createThumbnail,
    String? linkedDocPath,
    String? linkedDocAttribute,
  }) async {
    await _runStep(FakeFileStepKind.copy, name);
    objectsByName[newName] =
        objectsByName[name] ?? Uint8List.fromList(name.codeUnits);
    return 'https://cdn.test/$newName';
  }

  @override
  Future<void> deleteFile({
    required String path,
    String? name,
    String? bucketName,
  }) async {
    await _runStep(FakeFileStepKind.delete, name ?? '');
    objectsByName.remove(name);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDocumentWriter implements YustOfflineFileDocumentWriter {
  _FakeDocumentWriter(this._fileService);

  final FakeFileService _fileService;

  @override
  Future<void> writeFile(YustFile file) =>
      _fileService._runStep(FakeFileStepKind.documentWrite, file.name!);

  @override
  Future<void> removeFile(YustFile file) =>
      _fileService._runStep(FakeFileStepKind.documentRemoval, file.name!);
}
