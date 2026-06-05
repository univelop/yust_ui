/// Controls what happens when a file is tapped in a [YustFilePicker].
enum YustFileTapMode {
  /// Opens the file preview (Quick Look on iOS, system viewer on Android,
  /// browser tab on web).
  preview,

  /// Opens the file in the default app. On iOS 26+ uses the system default app
  /// preference, falling back to preview on older versions.
  defaultApp,

  /// Shows the share sheet (mobile) or triggers a file download (web).
  share,
}
