import 'package:bip39_mnemonic/bip39_mnemonic.dart';
import 'package:flutter/foundation.dart';

/// Why a typed or pasted phrase was rejected.
enum MnemonicFormatProblem {
  /// Not 12, 15, 18, 21 or 24 words.
  wordCount,

  /// A word is not in the language's word list.
  unknownWord,

  /// Every word exists, but the checksum in the last word does not match.
  checksum,
}

/// Thrown by [MnemonicWords.parse] and [MnemonicWords.fromList].
///
/// `toString` never includes the phrase or any of its words, so the exception can be logged.
/// The offending word of an [MnemonicFormatProblem.unknownWord] is on [word], for the UI.
@immutable
class MnemonicFormatException implements Exception {
  const MnemonicFormatException.wordCount(int count)
    : problem = MnemonicFormatProblem.wordCount,
      wordCount = count,
      word = null;

  const MnemonicFormatException.unknownWord(String unknown)
    : problem = MnemonicFormatProblem.unknownWord,
      wordCount = null,
      word = unknown;

  const MnemonicFormatException.checksum()
    : problem = MnemonicFormatProblem.checksum,
      wordCount = null,
      word = null;

  final MnemonicFormatProblem problem;

  /// The number of words entered, for [MnemonicFormatProblem.wordCount].
  final int? wordCount;

  /// The first word not in the word list, for [MnemonicFormatProblem.unknownWord].
  final String? word;

  @override
  String toString() =>
      'MnemonicFormatException(${problem.name}${wordCount == null ? '' : ', $wordCount words'})';
}

/// A recovery phrase held in memory.
///
/// The words are only reachable through [words] and [sentence]. `toString` reports the word
/// count and nothing else, so the phrase cannot reach a log through string interpolation, an
/// assertion message or a debugging aid.
@immutable
class MnemonicWords {
  MnemonicWords._(List<String> words) : words = List.unmodifiable(words);

  /// A new phrase from [Random.secure] entropy. [wordCount] is 12, 15, 18, 21 or 24.
  factory MnemonicWords.generate({
    int wordCount = 12,
    Language language = Language.english,
  }) {
    final MnemonicLength length;
    try {
      length = MnemonicLength.fromWords(wordCount);
    } on MnemonicException {
      throw ArgumentError.value(
        wordCount,
        'wordCount',
        'must be 12, 15, 18, 21 or 24',
      );
    }
    return MnemonicWords._(Mnemonic.generate(language, length: length).words);
  }

  /// Validates words the user typed or pasted.
  ///
  /// Whitespace of any kind separates the words and surrounding whitespace is ignored; the words
  /// are then validated by [fromList], which lower-cases them. Throws [MnemonicFormatException]
  /// for a wrong word count, a word that is not in the word list, or a checksum mismatch.
  factory MnemonicWords.parse(
    String text, {
    Language language = Language.english,
  }) {
    final words = text
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    return MnemonicWords.fromList(words, language: language);
  }

  /// Validates a list of words, without splitting.
  ///
  /// Blank entries are ignored and each word is trimmed and lower-cased before lookup, as
  /// [parse] does with text, so a phrase scanned or received with capitals is accepted; the held
  /// [words] are the normalised ones. Throws [MnemonicFormatException] for a wrong word count, a
  /// word that is not in the word list (reported as given, without surrounding whitespace), or a
  /// checksum mismatch.
  factory MnemonicWords.fromList(
    List<String> words, {
    Language language = Language.english,
  }) {
    final given = [
      for (final word in words)
        if (word.trim().isNotEmpty) word.trim(),
    ];
    if (!MnemonicLength.availableWords.contains(given.length)) {
      throw MnemonicFormatException.wordCount(given.length);
    }
    final normalised = [for (final word in given) word.toLowerCase()];
    for (var index = 0; index < given.length; index++) {
      if (!language.isValid(normalised[index])) {
        throw MnemonicFormatException.unknownWord(given[index]);
      }
    }
    try {
      Mnemonic.fromWords(words: normalised, language: language);
    } on MnemonicException {
      throw const MnemonicFormatException.checksum();
    }
    return MnemonicWords._(normalised);
  }

  /// The words in order. Unmodifiable.
  final List<String> words;

  int get length => words.length;

  /// The phrase as one line, words separated by a single space.
  String get sentence => words.join(' ');

  @override
  bool operator ==(Object other) =>
      other is MnemonicWords && listEquals(other.words, words);

  @override
  int get hashCode => Object.hashAll(words);

  @override
  String toString() => 'MnemonicWords(${words.length} words)';
}
