import 'package:yust/yust.dart';

/// Persists a single file's metadata to its linked document.
///
/// yust_ui's offline managers are generic and deliberately do NOT write records
/// directly — a raw Firestore write would bypass the app's permission,
/// workspace-lock and trigger pipeline. The app layer implements this interface
/// (typically via `RecordService.save` with a field mask scoped to the file's
/// own key, e.g. `brickValues.<brickId>.<hash>`) so every file write — online
/// or offline-completed — funnels through one sanctioned, conflict-free path.
abstract interface class OfflineFileDocumentWriter {
  /// Writes [file]'s metadata to its linked document, scoped to its own key.
  Future<void> writeFile(YustFile file);

  /// Removes [file]'s metadata from its linked document.
  Future<void> removeFile(YustFile file);
}
