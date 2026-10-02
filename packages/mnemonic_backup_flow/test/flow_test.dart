import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnemonic_backup_flow/mnemonic_backup_flow.dart';

import 'support.dart';

void main() {
  final words = MnemonicWords.parse(specVector12);

  /// A home screen with one button that starts the flow and records how it ended.
  Future<Captured<MnemonicBackupResult>> pumpFlow(
    WidgetTester tester, {
    required Future<bool> Function(BuildContext) authenticate,
    ScreenProtection? protection,
  }) async {
    final ScreenProtection chosen = protection ?? RecordingScreenProtection();
    final captured = Captured<MnemonicBackupResult>();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                captured.value = await showMnemonicBackupFlow(
                  context,
                  words: words,
                  authenticate: authenticate,
                  screenProtection: chosen,
                );
              },
              child: const Text('Back up'),
            ),
          ),
        ),
      ),
    );
    return captured;
  }

  Future<void> answerCurrentChallenge(WidgetTester tester) async {
    final prompt = tester
        .widget<Text>(find.textContaining('Select word #'))
        .data!;
    final position = int.parse(RegExp(r'#(\d+)').firstMatch(prompt)!.group(1)!);
    await tester.tap(
      find.widgetWithText(OutlinedButton, words.words[position - 1]),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows nothing and pushes no route when authentication fails', (
    tester,
  ) async {
    final protection = RecordingScreenProtection();
    final result = await pumpFlow(
      tester,
      authenticate: (_) async => false,
      protection: protection,
    );
    await tester.pump();

    await tester.tap(find.text('Back up'));
    await tester.pumpAndSettle();

    expect(result.value, MnemonicBackupResult.notAuthenticated);
    expect(find.text('Your recovery phrase'), findsNothing);
    expect(protection.events, isEmpty);
  });

  testWidgets('waits for authentication before revealing', (tester) async {
    final gate = Completer<bool>();
    await pumpFlow(tester, authenticate: (_) => gate.future);
    await tester.pump();

    await tester.tap(find.text('Back up'));
    await tester.pump();
    expect(find.text('Your recovery phrase'), findsNothing);

    gate.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Your recovery phrase'), findsOneWidget);
    expect(find.text('1. abandon'), findsOneWidget);
  });

  testWidgets('reports abandoned when the user backs out of the reveal', (
    tester,
  ) async {
    final protection = RecordingScreenProtection();
    final result = await pumpFlow(
      tester,
      authenticate: (_) async => true,
      protection: protection,
    );
    await tester.pump();
    await tester.tap(find.text('Back up'));
    await tester.pumpAndSettle();

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(result.value, MnemonicBackupResult.abandoned);
    expect(protection.events, ['protect', 'release']);
  });

  testWidgets(
    'reports verified after the reveal and every challenge, holding the protection once',
    (tester) async {
      final protection = RecordingScreenProtection();
      final result = await pumpFlow(
        tester,
        authenticate: (_) async => true,
        protection: protection,
      );
      await tester.pump();
      await tester.tap(find.text('Back up'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('I wrote it down'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm your backup'), findsOneWidget);

      for (var i = 0; i < 3; i++) {
        await answerCurrentChallenge(tester);
      }

      expect(result.value, MnemonicBackupResult.verified);
      expect(find.text('Back up'), findsOneWidget);
      // One route hosts both steps: the plugin is switched on once and off once, never off in between.
      expect(protection.events, ['protect', 'release']);
    },
  );

  testWidgets(
    'reports abandoned when the user backs out of the verify screen, releasing once',
    (tester) async {
      final protection = RecordingScreenProtection();
      final result = await pumpFlow(
        tester,
        authenticate: (_) async => true,
        protection: protection,
      );
      await tester.pump();
      await tester.tap(find.text('Back up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I wrote it down'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm your backup'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNWidgets(4));

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(result.value, MnemonicBackupResult.abandoned);
      expect(protection.events, ['protect', 'release']);
    },
  );

  testWidgets('shows neither step until the protection is active', (
    tester,
  ) async {
    final held = RecordingScreenProtection(holdProtect: true);
    await pumpFlow(tester, authenticate: (_) async => true, protection: held);
    await tester.pump();
    await tester.tap(find.text('Back up'));
    await tester.pumpAndSettle();
    expect(find.text('Your recovery phrase'), findsOneWidget);
    expect(find.text('Preparing a protected screen.'), findsOneWidget);
    expect(find.text('1. abandon'), findsNothing);

    held.completeProtect();
    await tester.pumpAndSettle();
    expect(find.text('1. abandon'), findsOneWidget);
    expect(find.text('Preparing a protected screen.'), findsNothing);
  });

  testWidgets(
    'shows the failure text when the protection fails, and ends as abandoned',
    (tester) async {
      final failing = RecordingScreenProtection(failProtect: true);
      final result = await pumpFlow(
        tester,
        authenticate: (_) async => true,
        protection: failing,
      );
      await tester.pump();
      await tester.tap(find.text('Back up'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isA<StateError>());
      expect(
        find.text(
          'Screen protection could not be enabled. Go back and try again.',
        ),
        findsOneWidget,
      );
      expect(find.text('1. abandon'), findsNothing);

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(result.value, MnemonicBackupResult.abandoned);
      expect(failing.events, ['protect', 'release']);
    },
  );

  testWidgets(
    'the verify step shows its choices at once and hides them while the app is not in the foreground',
    (tester) async {
      await pumpFlow(tester, authenticate: (_) async => true);
      await tester.pump();
      await tester.tap(find.text('Back up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I wrote it down'));
      await tester.pump();
      expect(
        find.byType(OutlinedButton),
        findsNWidgets(4),
        reason: 'no placeholder frame inside the flow',
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.byType(OutlinedButton), findsNothing);
      expect(
        find.text('Hidden while the app is not in the foreground.'),
        findsOneWidget,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byType(OutlinedButton), findsNWidgets(4));
    },
  );
}
