import 'package:flutter/material.dart';
import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../yust_ui.dart';

/// How one verdict looks: the glyph, its colour, and the sentence that explains
/// it — which is also the screen reader label.
typedef YustFileScanVisuals = ({IconData icon, Color color, String tooltip});

class YustFileScanHelpers {
  YustFileScanHelpers();

  /// Resolves a verdict to what is drawn for it.
  ///
  /// Shared, so a file cannot look one way beside its name and another on its
  /// thumbnail. Filled shields rather than outlined: at badge size an outline
  /// loses its fill colour to the icon behind it.
  static YustFileScanVisuals visualsFor(
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

  /// Asks before handing an infected file to the device, and returns whether to
  /// go ahead.
  ///
  /// Deliberately a confirmation and not a block. The verdict can be wrong, the
  /// file may be the user's own, and a product that silently refuses to open an
  /// attachment teaches people to route around it. What it must not do is let
  /// the file open without the user knowing what the scan found.
  ///
  /// Every other verdict — clean, pending, skipped, error, or none at all —
  /// passes straight through. Only [YustFileScanStatus.infected] is a statement
  /// about the file's contents; the rest are statements about the scan.
  static Future<bool> confirmIfInfected(YustFile file) async {
    if (!file.isScannedInfected) return true;

    final signature = file.virusScanResult?.signature;
    final warning = signature == null || signature.isEmpty
        ? LocaleKeys.fileScanInfectedOpenWarning.tr()
        : LocaleKeys.fileScanInfectedOpenWarningDetail.tr(
            namedArgs: {'signature': signature},
          );

    final confirmed = await YustUi.alertService.showConfirmation(
      LocaleKeys.fileScanInfected.tr(),
      LocaleKeys.fileScanInfectedOpenConfirm.tr(),
      description: warning,
    );
    return confirmed ?? false;
  }

  /// The signature is a vendor string, so it is interpolated, never translated.
  static String _infectedTooltip(YustFileScan scan) {
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
  static String _skippedTooltip(YustFileScan scan) => switch (scan.reason) {
    YustFileScanReason.tooLarge => LocaleKeys.fileScanSkippedTooLarge.tr(),
    YustFileScanReason.encrypted => LocaleKeys.fileScanSkippedEncrypted.tr(),
    YustFileScanReason.limitsExceeded =>
      LocaleKeys.fileScanSkippedLimitsExceeded.tr(),
    null => LocaleKeys.fileScanSkipped.tr(),
  };
}
