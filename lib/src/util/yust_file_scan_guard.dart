import 'package:yust/yust.dart';

import '../extensions/string_translate_extension.dart';
import '../generated/locale_keys.g.dart';
import '../yust_ui.dart';

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
Future<bool> confirmIfInfected(YustFile file) async {
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
  // Null is a dismissed dialog, which is not consent.
  return confirmed ?? false;
}
