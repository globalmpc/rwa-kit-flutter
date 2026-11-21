import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnemonic_backup_flow/mnemonic_backup_flow.dart';
import 'package:mnemonic_backup_flow_example/main.dart';

void main() {
  const strings = MnemonicBackupStrings();

  /// The BIP39 specification's own test vector for all-zero entropy: a published constant.
  const specVector12 =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

  Future<void> enterPin(WidgetTester tester, String pin) async {
    await tester.enterText(find.byType(TextField), pin);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
  }

  /// The words on screen, by their 1-based position, read from the "1. word" lines.
  Map<int, String> readWords(WidgetTester tester) {
    final words = <int, String>{};
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final match = RegExp(r'^(\d+)\. (\S+)$').firstMatch(text.data ?? '');
      if (match != null) {
        words[int.parse(match.group(1)!)] = match.group(2)!;
      }
    }
    return words;
  }

  /// Answers every challenge with the word at the position asked.
  Future<void> answerAll(WidgetTester tester, Map<int, String> words) async {
    for (var step = 0; step < 3; step++) {
      final prompt = tester
          .widget<Text>(find.textContaining('Select word #'))
          .data!;
      final position = int.parse(prompt.split('#').last);
      await tester.tap(find.text(words[position]!).last);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('a backup with the demo PIN ends verified', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    await tester.tap(find.text('Back up a new phrase'));
    await tester.pumpAndSettle();
    await enterPin(tester, '1234');

    expect(find.text(strings.revealCovered), findsOneWidget);
    expect(readWords(tester), isEmpty);
    await tester.tap(find.text(strings.revealShow));
    await tester.pumpAndSettle();
    final words = readWords(tester);
    expect(words, hasLength(12));

    await tester.tap(find.text(strings.revealConfirm));
    await tester.pumpAndSettle();
    await answerAll(tester, words);

    expect(find.text('Backup of a 12-word phrase: verified'), findsOneWidget);
  });

  testWidgets('a wrong PIN shows nothing', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    await tester.tap(find.text('Back up a new phrase'));
    await tester.pumpAndSettle();
    await enterPin(tester, '12');

    expect(find.text(strings.revealTitle), findsNothing);
    expect(
      find.text('Backup of a 12-word phrase: notAuthenticated'),
      findsOneWidget,
    );
  });

  testWidgets('an imported phrase comes back to the app', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    await tester.tap(find.text('Import a phrase'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), specVector12);
    await tester.tap(find.text(strings.importConfirm));
    await tester.pumpAndSettle();

    expect(find.text('Imported a 12-word phrase.'), findsOneWidget);
  });

  testWidgets('the same backup in a look of its own ends verified', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    await tester.tap(find.text('Back up in your own look'));
    await tester.pumpAndSettle();
    await enterPin(tester, '1234');

    // No Material page draws the step: the builder only hands over what to draw.
    expect(find.byType(Scaffold), findsNothing);
    expect(find.text(strings.revealWarning), findsOneWidget);
    // Its own text style, not the framework's fallback for text with no Material above it.
    expect(
      DefaultTextStyle.of(
        tester.element(find.text(strings.revealWarning)),
      ).style.decoration,
      TextDecoration.none,
    );
    expect(readWords(tester), isEmpty);
    await tester.tap(find.text(strings.revealShow));
    await tester.pumpAndSettle();
    final words = readWords(tester);
    expect(words, hasLength(12));

    await tester.tap(find.text(strings.revealConfirm));
    await tester.pumpAndSettle();
    await answerAll(tester, words);

    expect(find.text('Own-look backup: verified'), findsOneWidget);
  });

  testWidgets('the own-look backup can be left at any step', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    await tester.tap(find.text('Back up in your own look'));
    await tester.pumpAndSettle();
    await enterPin(tester, '1234');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Own-look backup: abandoned'), findsOneWidget);
  });
}
