import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';

/// Shows what is known about a file's virus scan.
///
/// Only [YustFileScanStatus.clean] gets a reassuring mark, and it gets a
/// *visible* one: a check on scanned files is what makes its absence on
/// unscanned ones mean something. Rendering nothing for both would make
/// "checked and fine" and "never checked" look identical.
///
/// A file with no verdict at all renders nothing — in a workspace without
/// scanning every file is in that state, and a row of grey marks is noise.
class YustFileScanIndicator extends StatelessWidget {
  const YustFileScanIndicator({super.key, required this.scan, this.size = 20});

  /// The verdict, or null when the file has none.
  final YustFileScan? scan;

  final double size;

  @override
  Widget build(BuildContext context) {
    final scan = this.scan;
    if (scan == null) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;

    final (IconData icon, Color color, String tooltip) = switch (scan.status) {
      YustFileScanStatus.clean => (
        Icons.verified_user_outlined,
        colors.primary,
        LocaleKeys.fileScanClean.tr(),
      ),
      YustFileScanStatus.infected => (
        Icons.gpp_bad,
        colors.error,
        _infectedTooltip(scan),
      ),
      YustFileScanStatus.pending => (
        Icons.hourglass_empty,
        colors.outline,
        LocaleKeys.fileScanPending.tr(),
      ),
      YustFileScanStatus.skipped => (
        Icons.gpp_maybe_outlined,
        colors.tertiary,
        _skippedTooltip(scan),
      ),
      YustFileScanStatus.error => (
        Icons.gpp_maybe_outlined,
        colors.outline,
        LocaleKeys.fileScanError.tr(),
      ),
    };

    return Tooltip(
      message: tooltip,
      child: Icon(
        icon,
        size: size,
        color: color,
        // Screen readers get the tooltip sentence, not an unlabelled icon.
        semanticLabel: tooltip,
      ),
    );
  }

  /// The signature is a vendor string, so it is interpolated, never translated.
  String _infectedTooltip(YustFileScan scan) {
    final signature = scan.signature;
    if (signature == null || signature.isEmpty) {
      return LocaleKeys.fileScanInfected.tr();
    }
    return LocaleKeys.fileScanInfectedDetail.tr(
      namedArgs: {'signature': signature},
    );
  }

  /// A missing reason still says "could not be checked", never anything
  /// reassuring.
  String _skippedTooltip(YustFileScan scan) => switch (scan.reason) {
    YustFileScanReason.tooLarge => LocaleKeys.fileScanSkippedTooLarge.tr(),
    YustFileScanReason.encrypted => LocaleKeys.fileScanSkippedEncrypted.tr(),
    YustFileScanReason.limitsExceeded =>
      LocaleKeys.fileScanSkippedLimitsExceeded.tr(),
    null => LocaleKeys.fileScanSkipped.tr(),
  };
}
