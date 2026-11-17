import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yust_ui/yust_ui.dart';

/// A button whose work is asynchronous (a save, a workflow start) stays
/// tappable until that work has visibly changed the UI. On a slow connection
/// that window is a few hundred milliseconds, long enough for a second tap to
/// start the same work twice. These tests pin down that `allowDoubleClick:
/// false` closes that window for callbacks that return a Future, and that
/// nothing changes for everyone else.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required FutureOr<void> Function()? onPressed,
    bool allowDoubleClick = true,
    YustButtonStyle buttonStyle = YustButtonStyle.primary,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: YustButtonTile(
          label: 'Buchen',
          onPressed: onPressed,
          allowDoubleClick: allowDoubleClick,
          buttonStyle: buttonStyle,
        ),
      ),
    ),
  );

  // The icon variants are private subclasses, so match on the base type.
  Finder button() => find.byWidgetPredicate((w) => w is ButtonStyleButton);

  bool isEnabled(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(button()).enabled;

  testWidgets('a second tap while the async callback is pending is ignored', (
    tester,
  ) async {
    var calls = 0;
    final work = Completer<void>();
    await pump(
      tester,
      allowDoubleClick: false,
      onPressed: () {
        calls++;
        return work.future;
      },
    );

    await tester.tap(button());
    await tester.pump();
    expect(isEnabled(tester), isFalse);

    await tester.tap(button(), warnIfMissed: false);
    await tester.pump();

    expect(calls, 1);
  });

  testWidgets('the button is usable again once the callback completes', (
    tester,
  ) async {
    var calls = 0;
    final work = Completer<void>();
    await pump(
      tester,
      allowDoubleClick: false,
      onPressed: () {
        calls++;
        return work.future;
      },
    );

    await tester.tap(button());
    await tester.pump();
    expect(isEnabled(tester), isFalse);

    work.complete();
    await tester.pump();
    expect(isEnabled(tester), isTrue);

    await tester.tap(button());
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('a failing callback releases the button as well', (tester) async {
    final work = Completer<void>();
    await pump(tester, allowDoubleClick: false, onPressed: () => work.future);

    await tester.tap(button());
    await tester.pump();
    expect(isEnabled(tester), isFalse);

    work.completeError(StateError('offline'));
    await tester.pump();
    expect(isEnabled(tester), isTrue);
    // The error is not swallowed: it is reported like any unhandled error.
    expect(tester.takeException(), isA<StateError>());
  });

  testWidgets('allowDoubleClick true keeps every tap', (tester) async {
    var calls = 0;
    final work = Completer<void>();
    await pump(
      tester,
      onPressed: () {
        calls++;
        return work.future;
      },
    );

    await tester.tap(button());
    await tester.pump();
    expect(isEnabled(tester), isTrue);
    await tester.tap(button());
    await tester.pump();

    expect(calls, 2);
  });

  testWidgets('a synchronous callback never locks the button', (tester) async {
    var calls = 0;
    await pump(tester, allowDoubleClick: false, onPressed: () => calls++);

    await tester.tap(button());
    await tester.pump();
    expect(isEnabled(tester), isTrue);
    await tester.tap(button());
    await tester.pump();

    expect(calls, 2);
  });

  testWidgets('a null callback renders a disabled button', (tester) async {
    await pump(tester, onPressed: null, allowDoubleClick: false);

    expect(isEnabled(tester), isFalse);
  });

  for (final style in YustButtonStyle.values) {
    testWidgets('the guard applies to the $style style', (tester) async {
      var calls = 0;
      final work = Completer<void>();
      await pump(
        tester,
        allowDoubleClick: false,
        buttonStyle: style,
        onPressed: () {
          calls++;
          return work.future;
        },
      );

      await tester.tap(button());
      await tester.pump();
      await tester.tap(button(), warnIfMissed: false);
      await tester.pump();

      expect(calls, 1);
    });
  }
}
