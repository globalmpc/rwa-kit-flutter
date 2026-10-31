import 'package:address_guard/address_guard.dart';
import 'package:address_guard_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const strings = AddressGuardStrings();

  testWidgets('the demo catches the look-alike planted in history', (
    tester,
  ) async {
    await tester.pumpWidget(const AddressGuardExample());

    await tester.tap(find.text('Look-alike from history'));
    await tester.pumpAndSettle();
    expect(find.text(strings.titleLookalike), findsOneWidget);
    expect(find.widgetWithText(FilledButton, strings.confirm), findsNothing);

    await tester.tap(find.text('New address'));
    await tester.pumpAndSettle();
    expect(find.text(strings.titleFirstTime), findsOneWidget);
  });

  testWidgets('the paid supplier confirms, and an edit afterwards is caught', (
    tester,
  ) async {
    await tester.pumpWidget(const AddressGuardExample());

    await tester.tap(find.text('Supplier you paid'));
    await tester.pumpAndSettle();
    expect(find.text(strings.titleKnown), findsOneWidget);

    await tester.ensureVisible(
      find.widgetWithText(FilledButton, strings.confirm),
    );
    await tester.tap(find.widgetWithText(FilledButton, strings.confirm));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ready to sign: 0x'), findsOneWidget);

    // A stray space typed and removed keeps the same address: still confirmed, not stuck.
    final field = find.byType(TextField);
    final text = tester.widget<TextField>(field).controller!.text;
    await tester.enterText(field, '$text ');
    await tester.pumpAndSettle();
    await tester.enterText(field, text);
    await tester.pumpAndSettle();
    expect(find.textContaining('Ready to sign: 0x'), findsOneWidget);

    // The same address in edited casing: judged again, and the confirmation is dropped.
    final altered = text.replaceFirst(
      RegExp('[a-f]'),
      text[text.indexOf(RegExp('[a-f]'), 2)].toUpperCase(),
    );
    await tester.enterText(field, altered);
    await tester.pumpAndSettle();
    expect(find.textContaining('Ready to sign'), findsNothing);
    expect(find.text(strings.titleBadChecksum), findsOneWidget);
    await tester.enterText(field, text);
    await tester.pumpAndSettle();

    // Same field, one character changed: the confirmation no longer applies.
    await tester.enterText(field, '${text.substring(0, 41)}0');
    await tester.pumpAndSettle();
    expect(find.textContaining('Ready to sign'), findsNothing);
  });

  testWidgets(
    'picking the same address again asks again, without getting stuck',
    (tester) async {
      await tester.pumpWidget(const AddressGuardExample());
      for (var round = 0; round < 2; round++) {
        await tester.tap(find.text('Supplier you paid'));
        await tester.pumpAndSettle();
        final confirm = find.widgetWithText(FilledButton, strings.confirm);
        await tester.ensureVisible(confirm);
        expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(find.textContaining('Ready to sign: 0x'), findsOneWidget);
      }
    },
  );
}
