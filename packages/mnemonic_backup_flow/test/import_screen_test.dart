import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnemonic_backup_flow/mnemonic_backup_flow.dart';

import 'support.dart';

void main() {
  Future<Captured<MnemonicWords>> pumpImport(
    WidgetTester tester, {
    ScreenProtection? protection,
    bool allowPaste = true,
  }) async {
    final ScreenProtection chosen = protection ?? RecordingScreenProtection();
    final captured = Captured<MnemonicWords>();
    await tester.pumpWidget(
      wrap(
        MnemonicImportScreen(
          screenProtection: chosen,
          allowPaste: allowPaste,
          onImported: (words) => captured.value = words,
        ),
      ),
    );
    return captured;
  }

  testWidgets('imports a typed phrase', (tester) async {
    final imported = await pumpImport(tester);
    await tester.pump();

    await tester.enterText(find.byType(TextField), '  $specVector12 \n');
    await tester.tap(find.text('Import'));
    await tester.pump();

    expect(imported.value?.length, 12);
  });

  testWidgets(
    'explains a wrong word count, an unknown word, and a checksum mismatch',
    (tester) async {
      final imported = await pumpImport(tester);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'abandon abandon abandon');
      await tester.tap(find.text('Import'));
      await tester.pump();
      expect(
        find.text(
          'A recovery phrase has 12, 15, 18, 21 or 24 words. You entered 3.',
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byType(TextField),
        specVector12.replaceFirst('abandon', 'abandom'),
      );
      await tester.tap(find.text('Import'));
      await tester.pump();
      expect(find.text('"abandom" is not in the word list.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), specVector12BadChecksum);
      await tester.tap(find.text('Import'));
      await tester.pump();
      expect(
        find.text(
          'These words are not a valid recovery phrase. Check the order and the spelling.',
        ),
        findsOneWidget,
      );

      expect(imported.value, isNull);
    },
  );

  testWidgets('pastes from the clipboard and empties it afterwards', (
    tester,
  ) async {
    final clipboard = FakeClipboard()..install(tester);
    clipboard.text = specVector12;
    final imported = await pumpImport(tester);
    await tester.pump();

    await tester.tap(find.text('Paste'));
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      specVector12,
    );
    expect(clipboard.text, '');

    await tester.tap(find.text('Import'));
    await tester.pump();
    expect(imported.value?.length, 12);
  });

  testWidgets(
    'keeps the field hidden until the screen protection is active, and releases it on leave',
    (tester) async {
      final protection = RecordingScreenProtection(holdProtect: true);
      await pumpImport(tester, protection: protection);
      await tester.pump();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Preparing a protected screen.'), findsOneWidget);

      protection.completeProtect();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.pumpWidget(wrap(const SizedBox()));
      expect(protection.events, ['protect', 'release']);
    },
  );

  testWidgets(
    'releases only after a protect that was still running has settled',
    (tester) async {
      final protection = RecordingScreenProtection(holdProtect: true);
      await pumpImport(tester, protection: protection);
      await tester.pump();

      await tester.pumpWidget(wrap(const SizedBox()));
      expect(protection.events, ['protect']);

      protection.completeProtect();
      await tester.pumpAndSettle();
      expect(protection.events, ['protect', 'release']);
    },
  );

  testWidgets(
    'a protect that throws shows the failure text and offers no field',
    (tester) async {
      final protection = RecordingScreenProtection(failProtect: true);
      await pumpImport(tester, protection: protection);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isA<StateError>());
      expect(
        find.text(
          'Screen protection could not be enabled. Go back and try again.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets('a paste that fails tells the user and is reported', (
    tester,
  ) async {
    final clipboard = FakeClipboard()..install(tester);
    await pumpImport(tester);
    await tester.pumpAndSettle();

    clipboard.failNextGetData = true;
    await tester.tap(find.text('Paste'));
    await tester.pump();

    expect(find.text('Could not read the clipboard.'), findsOneWidget);
    expect(tester.takeException(), isA<PlatformException>());
  });

  testWidgets(
    'a paste whose clearing fails still fills the field and is reported',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      await pumpImport(tester);
      await tester.pumpAndSettle();

      clipboard.text = specVector12;
      clipboard.failNextSetData = true;
      await tester.tap(find.text('Paste'));
      await tester.pump();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        specVector12,
      );
      expect(clipboard.text, specVector12);
      expect(tester.takeException(), isA<PlatformException>());
    },
  );

  testWidgets(
    'a paste read after the screen has gone still empties the clipboard',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      clipboard.text = specVector12;
      await pumpImport(tester);
      await tester.pumpAndSettle();

      final gate = clipboard.gateNextGetData = Completer<void>();
      await tester.tap(find.text('Paste'));
      await tester.pumpWidget(wrap(const SizedBox()));
      gate.complete();
      await tester.pump();

      expect(clipboard.text, '');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a second tap on Paste while a read is pending starts no second read',
    (tester) async {
      final clipboard = FakeClipboard()..install(tester);
      clipboard.text = specVector12;
      await pumpImport(tester);
      await tester.pumpAndSettle();

      final gate = clipboard.gateNextGetData = Completer<void>();
      await tester.tap(find.text('Paste'));
      await tester.pump();
      await tester.tap(find.text('Paste'), warnIfMissed: false);
      await tester.pump();
      expect(clipboard.reads, 1);

      gate.complete();
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        specVector12,
      );
      expect(clipboard.text, '');
    },
  );

  testWidgets('offers no paste button when pasting is not allowed', (
    tester,
  ) async {
    await pumpImport(tester, allowPaste: false);
    await tester.pump();

    expect(find.text('Paste'), findsNothing);
  });
}
