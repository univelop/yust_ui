import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yust/yust.dart';
import 'package:yust_ui/src/generated/locale_keys.g.dart';
import 'package:yust_ui/yust_ui.dart';

/// The indicator's whole job is that "checked and fine" and "never checked"
/// never look the same, so these lock in which states get a reassuring mark
/// and which do not. The default `trCallback` returns the key, so the tooltips
/// assert on LocaleKeys rather than on German copy.
void main() {
  Future<void> pump(WidgetTester tester, YustFileScan? scan) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: YustFileScanIndicator(scan: scan)),
        ),
      );

  Tooltip tooltip(WidgetTester tester) =>
      tester.widget<Tooltip>(find.byType(Tooltip));

  testWidgets('renders nothing for a file with no verdict', (tester) async {
    // In a workspace without scanning every file is in this state, and a
    // permanent row of grey marks is noise.
    await pump(tester, null);

    expect(find.byType(Icon), findsNothing);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('gives a clean file a visible mark, not nothing', (
    tester,
  ) async {
    // The point of the widget: a check on scanned files is what makes its
    // absence on unscanned ones mean anything.
    await pump(tester, YustFileScan(status: YustFileScanStatus.clean));

    expect(find.byIcon(Icons.verified_user), findsOneWidget);
    expect(tooltip(tester).message, LocaleKeys.fileScanClean);
  });

  testWidgets('names the signature on an infected file', (tester) async {
    await pump(
      tester,
      YustFileScan(
        status: YustFileScanStatus.infected,
        signature: 'Win.Trojan.Agent-1774751',
      ),
    );

    expect(find.byIcon(Icons.gpp_bad), findsOneWidget);
    expect(tooltip(tester).message, LocaleKeys.fileScanInfectedDetail);
  });

  testWidgets('falls back to the plain infected message with no signature', (
    tester,
  ) async {
    await pump(tester, YustFileScan(status: YustFileScanStatus.infected));

    expect(tooltip(tester).message, LocaleKeys.fileScanInfected);
  });

  testWidgets('a skipped file with no reason still says it was not checked', (
    tester,
  ) async {
    // Never anything reassuring: an unrecognised reason deserializes to null,
    // and this is the state that lands in.
    await pump(tester, YustFileScan(status: YustFileScanStatus.skipped));

    expect(tooltip(tester).message, LocaleKeys.fileScanSkipped);
  });

  testWidgets('names why a skipped file was skipped', (tester) async {
    await pump(
      tester,
      YustFileScan(
        status: YustFileScanStatus.skipped,
        reason: YustFileScanReason.encrypted,
      ),
    );

    expect(tooltip(tester).message, LocaleKeys.fileScanSkippedEncrypted);
  });

  testWidgets('shows pending as in progress', (tester) async {
    await pump(tester, YustFileScan.pending());

    expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    expect(tooltip(tester).message, LocaleKeys.fileScanPending);
  });

  testWidgets('shows error as unchecked, never as safe', (tester) async {
    await pump(tester, YustFileScan(status: YustFileScanStatus.error));

    expect(find.byIcon(Icons.verified_user), findsNothing);
    expect(tooltip(tester).message, LocaleKeys.fileScanError);
  });

  group('YustFileScanBadgedIcon', badgeTests);

  testWidgets('labels the icon for screen readers', (tester) async {
    await pump(tester, YustFileScan(status: YustFileScanStatus.clean));

    expect(
      tester.widget<Icon>(find.byType(Icon)).semanticLabel,
      LocaleKeys.fileScanClean,
    );
  });
}

/// The badge form used in file lists: the verdict hangs off the file's own
/// icon instead of taking a column of its own.
void badgeTests() {
  Future<void> pumpBadge(WidgetTester tester, YustFileScan? scan) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: YustFileScanBadgedIcon(
              icon: Icons.insert_drive_file,
              scan: scan,
            ),
          ),
        ),
      );

  testWidgets('is just the file icon when there is no verdict', (tester) async {
    // A list in a workspace without scanning must not shift its layout the
    // moment one file gains a badge.
    await pumpBadge(tester, null);

    expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
    // Exactly the footprint of the bare icon, so nothing reflows when a file
    // later gains a verdict.
    expect(
      tester.getSize(find.byType(YustFileScanBadgedIcon)),
      const Size(
        YustFilePickerBase.fileIconSize,
        YustFilePickerBase.fileIconSize,
      ),
    );
  });

  testWidgets('keeps the file icon and adds the verdict beside it', (
    tester,
  ) async {
    await pumpBadge(tester, YustFileScan(status: YustFileScanStatus.infected));

    expect(find.byIcon(Icons.insert_drive_file), findsOneWidget);
    expect(find.byIcon(Icons.gpp_bad), findsOneWidget);
  });

  testWidgets('puts the tooltip on the whole group, not just the badge', (
    tester,
  ) async {
    // A 20 px target is too small to hit, and the file and its verdict are one
    // thing to ask about.
    await pumpBadge(tester, YustFileScan(status: YustFileScanStatus.clean));

    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(tooltip.message, LocaleKeys.fileScanClean);
    expect(
      find.descendant(
        of: find.byType(Tooltip),
        matching: find.byIcon(Icons.insert_drive_file),
      ),
      findsOneWidget,
    );
  });

  testWidgets('does not make the badge wider than its own footprint', (
    tester,
  ) async {
    // The badge overhangs the file icon, so the box has to be sized to hold it
    // rather than let it reach into the file name beside it.
    await pumpBadge(tester, YustFileScan(status: YustFileScanStatus.clean));

    final size = tester.getSize(find.byType(YustFileScanBadgedIcon));
    expect(size.width, lessThanOrEqualTo(32));
    expect(size.height, lessThanOrEqualTo(32));
  });
}
