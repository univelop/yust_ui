import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import 'yust_file_picker_base.dart';

/// How one verdict looks: the glyph, its colour, and the sentence that explains
/// it — which is also the screen reader label.
typedef YustFileScanVisuals = ({IconData icon, Color color, String tooltip});

/// Resolves a verdict to what is drawn for it.
///
/// Shared, so a file cannot look one way beside its name and another on its
/// thumbnail. Filled shields rather than outlined: at badge size an outline
/// loses its fill colour to the icon behind it.
YustFileScanVisuals yustFileScanVisuals(
  BuildContext context,
  YustFileScan scan,
) {
  final colors = Theme.of(context).colorScheme;

  return switch (scan.status) {
    YustFileScanStatus.clean => (
      icon: Icons.verified_user,
      color: colors.primary,
      tooltip: LocaleKeys.fileScanClean.tr(),
    ),
    YustFileScanStatus.infected => (
      icon: Icons.gpp_bad,
      color: colors.error,
      tooltip: _infectedTooltip(scan),
    ),
    YustFileScanStatus.pending => (
      icon: Icons.hourglass_top,
      color: colors.outline,
      tooltip: LocaleKeys.fileScanPending.tr(),
    ),
    YustFileScanStatus.skipped => (
      icon: Icons.gpp_maybe,
      color: colors.tertiary,
      tooltip: _skippedTooltip(scan),
    ),
    YustFileScanStatus.error => (
      icon: Icons.gpp_maybe,
      color: colors.outline,
      tooltip: LocaleKeys.fileScanError.tr(),
    ),
  };
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

/// Shows what is known about a file's virus scan, as a standalone icon.
///
/// Only [YustFileScanStatus.clean] gets a reassuring mark, and it gets a
/// *visible* one: a check on scanned files is what makes its absence on
/// unscanned ones mean something. A file with no verdict renders nothing — in
/// a workspace without scanning every file is in that state.
///
/// For a file list, see [YustFileScanBadgedIcon].
class YustFileScanIndicator extends StatelessWidget {
  const YustFileScanIndicator({
    super.key,
    required this.scan,
    this.size = YustFilePickerBase.indicatorIconSize,
  });

  /// The verdict, or null when the file has none.
  final YustFileScan? scan;

  final double size;

  @override
  Widget build(BuildContext context) {
    final scan = this.scan;
    if (scan == null) return const SizedBox.shrink();

    final visuals = yustFileScanVisuals(context, scan);

    return Tooltip(
      message: visuals.tooltip,
      child: Icon(
        visuals.icon,
        size: size,
        color: visuals.color,
        // Screen readers get the tooltip sentence, not an unlabelled icon.
        semanticLabel: visuals.tooltip,
      ),
    );
  }
}

/// A file's icon with its scan verdict hanging off the bottom-right corner.
///
/// On the file rather than beside it: a row already spends its trailing space
/// on actions, and a status column would be empty in most workspaces.
///
/// The badge sits on a disc of [backgroundColor] so it stays legible over the
/// glyph behind it; that has to match what the row is painted on, so pass the
/// real colour for a tinted or selected row.
///
/// With no verdict this is exactly [icon], at the same size, so a list does not
/// shift when one file gains a badge.
class YustFileScanBadgedIcon extends StatelessWidget {
  const YustFileScanBadgedIcon({
    super.key,
    required this.icon,
    required this.scan,
    this.iconColor,
    this.backgroundColor,
  });

  /// The file's own icon, e.g. `Icons.insert_drive_file`.
  final IconData icon;

  /// The verdict, or null when the file has none.
  final YustFileScan? scan;

  final Color? iconColor;

  /// What the badge's disc is filled with. Defaults to `colorScheme.surface`.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final scan = this.scan;
    final fileIcon = Icon(
      icon,
      size: YustFilePickerBase.fileIconSize,
      color: iconColor,
    );
    if (scan == null) return fileIcon;

    final visuals = yustFileScanVisuals(context, scan);

    return Tooltip(
      // On the whole group: a 20 px target is too small to hit.
      message: visuals.tooltip,
      child: SizedBox(
        width: YustFilePickerBase.fileIconSize + _badgeOverhangX,
        height: YustFilePickerBase.fileIconSize + _badgeOverhangY,
        // Sized to hold the overhang, so it cannot reach into the file name.
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(top: 0, left: 0, child: fileIcon),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: _badgeDiscSize,
                height: _badgeDiscSize,
                decoration: BoxDecoration(
                  color:
                      backgroundColor ?? Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    visuals.icon,
                    size: _badgeIconSize,
                    color: visuals.color,
                    semanticLabel: visuals.tooltip,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Glyph size of the badge itself.
  static const double _badgeIconSize = 16;

  /// Diameter of the disc behind the badge, leaving a ring of background
  /// between it and the file icon.
  static const double _badgeDiscSize = 20;

  /// How far the disc reaches past the file icon, kept small enough that the
  /// file icon stays recognisable underneath.
  static const double _badgeOverhangX = 6;
  static const double _badgeOverhangY = 4;
}
