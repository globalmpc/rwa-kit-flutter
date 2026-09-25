import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mnemonic_backup_flow/mnemonic_backup_flow.dart';

import 'support.dart';

void main() {
  final words = MnemonicWords.parse(specVector12);
  const challenges = [
    VerificationChallenge(
      position: 2,
      answer: 'abandon',
      choices: ['zoo', 'abandon', 'able'],
    ),
    VerificationChallenge(
      position: 12,
      answer: 'about',
      choices: ['about', 'zoo', 'able'],
    ),
  ];

  testWidgets('walks through the challenges and reports success once', (
    tester,
  ) async {
    var verified = 0;
    await tester.pumpWidget(
      wrap(
        MnemonicVerifyScreen(
          words: words,
          challenges: challenges,
          onVerified: () => verified++,
        ),
      ),
    );

    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Select word #2'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'abandon'));
    await tester.pump();

    expect(find.text('2 of 2'), findsOneWidget);
    expect(find.text('Select word #12'), findsOneWidget);
    expect(verified, 0);
    await tester.tap(find.widgetWithText(OutlinedButton, 'about'));
    await tester.pump();

    expect(verified, 1);
  });

  testWidgets(
    'a wrong answer shows the message, reports the position, and allows a retry',
    (tester) async {
      final wrong = <int>[];
      var verified = 0;
      await tester.pumpWidget(
        wrap(
          MnemonicVerifyScreen(
            words: words,
            challenges: challenges,
            onVerified: () => verified++,
            onWrongAnswer: wrong.add,
          ),
        ),
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'zoo'));
      await tester.pump();

      expect(
        find.text('That is not word #2. Check your backup and try again.'),
        findsOneWidget,
      );
      expect(wrong, [2]);
      expect(find.text('1 of 2'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'abandon'));
      await tester.pump();

      expect(find.textContaining('That is not word'), findsNothing);
      expect(find.text('2 of 2'), findsOneWidget);
      expect(verified, 0);
    },
  );

  testWidgets('rejects an empty list of challenges with a clear error', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MnemonicVerifyScreen(
          words: MnemonicWords.parse(specVector12),
          challenges: const [],
          onVerified: () {},
        ),
      ),
    );

    expect(
      tester.takeException(),
      isA<ArgumentError>().having((e) => e.name, 'name', 'challenges'),
    );
  });

  testWidgets('generates challenges from the phrase when none are given', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        MnemonicVerifyScreen(
          words: words,
          challengeCount: 3,
          choiceCount: 4,
          onVerified: () {},
        ),
      ),
    );

    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNWidgets(4));
    final prompt = tester
        .widget<Text>(find.textContaining('Select word #'))
        .data!;
    final position = int.parse(RegExp(r'#(\d+)').firstMatch(prompt)!.group(1)!);
    expect(
      find.widgetWithText(OutlinedButton, words.words[position - 1]),
      findsOneWidget,
    );
  });
}
