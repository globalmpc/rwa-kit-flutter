import 'dart:math';

import 'package:flutter/foundation.dart';

/// One question in the backup check: which word sits at [position]?
@immutable
class VerificationChallenge {
  const VerificationChallenge({
    required this.position,
    required this.answer,
    required this.choices,
  });

  /// 1-based position of the word in the phrase, the number the user wrote next to it.
  final int position;

  final String answer;

  /// Shuffled, and contains [answer] exactly once.
  final List<String> choices;

  bool accepts(String candidate) => candidate.trim() == answer;

  /// Never includes the answer, so a challenge can be logged.
  @override
  String toString() =>
      'VerificationChallenge(#$position, ${choices.length} choices)';
}

/// Picks [count] distinct positions of the phrase and builds a multiple-choice challenge for
/// each, with decoys drawn from [wordList] that do not appear in the phrase.
///
/// Positions are chosen with [random], which defaults to [Random.secure], and returned in
/// ascending order. Checkbox-style "I have written it down" confirmations prove nothing; a
/// distinct-position check proves the words were written in order.
List<VerificationChallenge> generateChallenges(
  List<String> words, {
  required List<String> wordList,
  int count = 3,
  int choiceCount = 4,
  Random? random,
}) {
  if (words.isEmpty) {
    throw ArgumentError.value(words, 'words', 'must not be empty');
  }
  if (count < 1 || count > words.length) {
    throw ArgumentError.value(
      count,
      'count',
      'must be between 1 and ${words.length}',
    );
  }
  if (choiceCount < 2) {
    throw ArgumentError.value(choiceCount, 'choiceCount', 'must be at least 2');
  }
  final inPhrase = words.toSet();
  final decoyPool = wordList
      .where((word) => !inPhrase.contains(word))
      .toList(growable: false);
  if (decoyPool.length < choiceCount - 1) {
    throw ArgumentError.value(
      wordList,
      'wordList',
      'needs at least ${choiceCount - 1} words that are not in the phrase',
    );
  }
  final rng = random ?? Random.secure();
  final positions = List<int>.generate(words.length, (index) => index)
    ..shuffle(rng);
  final chosen = positions.take(count).toList()..sort();
  return [
    for (final index in chosen)
      VerificationChallenge(
        position: index + 1,
        answer: words[index],
        choices: _choices(words[index], decoyPool, choiceCount, rng),
      ),
  ];
}

List<String> _choices(
  String answer,
  List<String> decoyPool,
  int choiceCount,
  Random rng,
) {
  final decoys = <String>{};
  while (decoys.length < choiceCount - 1) {
    decoys.add(decoyPool[rng.nextInt(decoyPool.length)]);
  }
  return [answer, ...decoys]..shuffle(rng);
}
