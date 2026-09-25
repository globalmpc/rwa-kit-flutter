import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mnemonic_backup_flow/mnemonic_backup_flow.dart';

import 'support.dart';

void main() {
  final words = MnemonicWords.parse(specVector12).words;
  final wordList = Language.english.list;

  test(
    'picks distinct positions in ascending order with the right answers',
    () {
      final challenges = generateChallenges(
        words,
        wordList: wordList,
        count: 3,
        random: Random(1),
      );

      expect(challenges, hasLength(3));
      final positions = challenges.map((c) => c.position).toList();
      expect(positions.toSet(), hasLength(3));
      expect(positions, [...positions]..sort());
      for (final challenge in challenges) {
        expect(challenge.position, inInclusiveRange(1, 12));
        expect(challenge.answer, words[challenge.position - 1]);
      }
    },
  );

  test('offers the answer once among decoys that are not in the phrase', () {
    final challenges = generateChallenges(
      words,
      wordList: wordList,
      count: 12,
      choiceCount: 4,
      random: Random(2),
    );

    for (final challenge in challenges) {
      expect(challenge.choices, hasLength(4));
      expect(
        challenge.choices.where((c) => c == challenge.answer),
        hasLength(1),
      );
      expect(challenge.choices.toSet(), hasLength(4));
      for (final choice in challenge.choices.where(
        (c) => c != challenge.answer,
      )) {
        expect(words, isNot(contains(choice)));
      }
    }
  });

  test(
    'is reproducible for a seeded random source and different otherwise',
    () {
      final a = generateChallenges(
        words,
        wordList: wordList,
        random: Random(7),
      );
      final b = generateChallenges(
        words,
        wordList: wordList,
        random: Random(7),
      );
      expect(a.map((c) => c.position), b.map((c) => c.position));
      expect(a.map((c) => c.choices), b.map((c) => c.choices));
    },
  );

  test('accepts an answer with surrounding whitespace', () {
    const challenge = VerificationChallenge(
      position: 1,
      answer: 'abandon',
      choices: ['abandon', 'zoo'],
    );
    expect(challenge.accepts(' abandon '), isTrue);
    expect(challenge.accepts('zoo'), isFalse);
  });

  test('never prints the answer', () {
    const challenge = VerificationChallenge(
      position: 4,
      answer: 'abandon',
      choices: ['abandon', 'zoo'],
    );
    expect(challenge.toString(), 'VerificationChallenge(#4, 2 choices)');
  });

  test('rejects unusable arguments', () {
    expect(
      () => generateChallenges([], wordList: wordList),
      throwsArgumentError,
    );
    expect(
      () => generateChallenges(words, wordList: wordList, count: 0),
      throwsArgumentError,
    );
    expect(
      () => generateChallenges(words, wordList: wordList, count: 13),
      throwsArgumentError,
    );
    expect(
      () => generateChallenges(words, wordList: wordList, choiceCount: 1),
      throwsArgumentError,
    );
    expect(
      () => generateChallenges(
        words,
        wordList: ['abandon', 'about', 'zoo'],
        choiceCount: 4,
      ),
      throwsArgumentError,
    );
  });
}
