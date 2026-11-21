import 'package:flutter/foundation.dart';

import 'mnemonic_words.dart';
import 'secret_phase.dart';

/// Every piece of user-facing text in the flow, so an app can translate it.
///
/// All values have English defaults. Construct one with only the fields you need changed; the
/// rest keep their defaults. Texts that carry a number or a word are functions.
@immutable
class MnemonicBackupStrings {
  /// The English texts, with any of them replaced by the ones given.
  const MnemonicBackupStrings({
    this.revealTitle = 'Your recovery phrase',
    this.revealWarning =
        'Anyone with these words can take everything in this wallet. Write them down in order, keep them offline, and never share them.',
    this.revealPreparing = 'Preparing a protected screen.',
    this.revealHidden = 'Hidden while the app is not in the foreground.',
    this.protectionFailed =
        'Screen protection could not be enabled. Go back and try again.',
    this.revealCovered = 'The words stay hidden until you ask to see them.',
    this.revealShow = 'Show the words',
    this.revealConfirm = 'Continue',
    this.copy = 'Copy',
    this.copiedFor = _copiedFor,
    this.copyFailed = 'Could not copy. Write the words down instead.',
    this.verifyTitle = 'Confirm your backup',
    this.verifyProgress = _verifyProgress,
    this.verifyPrompt = _verifyPrompt,
    this.verifyWrong = _verifyWrong,
    this.importTitle = 'Import a recovery phrase',
    this.importInstruction =
        'Enter your 12, 15, 18, 21 or 24 words in order, separated by spaces.',
    this.importHint = 'word word word ...',
    this.importPaste = 'Paste',
    this.pasteFailed = 'Could not read the clipboard.',
    this.importConfirm = 'Import',
    this.importWrongCount = _importWrongCount,
    this.importUnknownWord = _importUnknownWord,
    this.importInvalid =
        'These words are not a valid recovery phrase. Check the order and the spelling.',
  });

  /// The title of the reveal step.
  final String revealTitle;

  /// The warning above the words: what the phrase is worth and how to keep it.
  final String revealWarning;

  /// Shown until the screen protection has confirmed it is active.
  final String revealPreparing;

  /// Shown in place of the words while the app is inactive or in the background.
  final String revealHidden;

  /// Shown in place of the words or the input when the screen protection failed or timed out.
  final String protectionFailed;

  /// Shown in place of the words until the user asks to see them.
  final String revealCovered;

  /// The button that uncovers the words.
  final String revealShow;

  /// The button that leaves the reveal step. It stays disabled until the words have been on screen.
  final String revealConfirm;

  /// The copy button, offered only when the app allows copying.
  final String copy;

  /// Confirmation after copying; receives the number of seconds until the clipboard is cleared.
  final String Function(int seconds) copiedFor;

  /// Shown when the clipboard write failed.
  final String copyFailed;

  /// The title of the verify step.
  final String verifyTitle;

  /// Progress through the challenges, for example "1 of 3".
  final String Function(int current, int total) verifyProgress;

  /// Asks for the word at a 1-based position.
  final String Function(int position) verifyPrompt;

  /// Shown after a wrong answer; receives the 1-based position.
  final String Function(int position) verifyWrong;

  /// The title of the import step.
  final String importTitle;

  /// Above the input: how many words to enter, and how.
  final String importInstruction;

  /// Shown in the empty input.
  final String importHint;

  /// The paste button.
  final String importPaste;

  /// Shown when the clipboard could not be read for a paste.
  final String pasteFailed;

  /// The button that checks the phrase and imports it.
  final String importConfirm;

  /// Receives the number of words that were entered.
  final String Function(int count) importWrongCount;

  /// Receives the first word that is not in the word list.
  final String Function(String word) importUnknownWord;

  /// The checksum did not match: the words exist but are not a valid phrase.
  final String importInvalid;

  static String _copiedFor(int seconds) =>
      'Copied. The clipboard clears in $seconds seconds.';
  static String _verifyProgress(int current, int total) => '$current of $total';
  static String _verifyPrompt(int position) => 'Select word #$position';
  static String _verifyWrong(int position) =>
      'That is not word #$position. Check your backup and try again.';
  static String _importWrongCount(int count) =>
      'A recovery phrase has 12, 15, 18, 21 or 24 words. You entered $count.';
  static String _importUnknownWord(String word) =>
      '"$word" is not in the word list.';
}

/// Texts for an app that draws the steps itself with the builders. An extension rather than
/// methods on the class, so a class that implements [MnemonicBackupStrings] keeps compiling.
extension MnemonicBackupStringsForBuilders on MnemonicBackupStrings {
  /// The text to show in place of the secret in [phase]: why it is not on screen. Null for
  /// [MnemonicSecretPhase.visible], when the secret itself is shown.
  String? placeholder(MnemonicSecretPhase phase) => switch (phase) {
    MnemonicSecretPhase.preparing => revealPreparing,
    MnemonicSecretPhase.protectionFailed => protectionFailed,
    MnemonicSecretPhase.hidden => revealHidden,
    MnemonicSecretPhase.visible => null,
  };

  /// Why a phrase was refused, for `MnemonicImportState.error`.
  String importError(MnemonicFormatException error) => switch (error.problem) {
    MnemonicFormatProblem.wordCount => importWrongCount(error.wordCount ?? 0),
    MnemonicFormatProblem.unknownWord => importUnknownWord(error.word ?? ''),
    MnemonicFormatProblem.checksum => importInvalid,
  };
}
