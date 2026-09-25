import 'package:flutter/foundation.dart';

/// Every piece of user-facing text in the flow, so an app can translate it.
///
/// All values have English defaults. Construct one with only the fields you need changed; the
/// rest keep their defaults. Texts that carry a number or a word are functions.
@immutable
class MnemonicBackupStrings {
  const MnemonicBackupStrings({
    this.revealTitle = 'Your recovery phrase',
    this.revealWarning =
        'Anyone with these words can take everything in this wallet. Write them down in order, keep them offline, and never share them.',
    this.revealPreparing = 'Preparing a protected screen.',
    this.revealHidden = 'Hidden while the app is not in the foreground.',
    this.protectionFailed =
        'Screen protection could not be enabled. Go back and try again.',
    this.revealConfirm = 'I wrote it down',
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

  final String revealTitle;
  final String revealWarning;

  /// Shown until the screen protection has confirmed it is active.
  final String revealPreparing;

  /// Shown in place of the words while the app is inactive or in the background.
  final String revealHidden;

  /// Shown in place of the words or the input when the screen protection failed or timed out.
  final String protectionFailed;
  final String revealConfirm;
  final String copy;

  /// Confirmation after copying; receives the number of seconds until the clipboard is cleared.
  final String Function(int seconds) copiedFor;

  /// Shown when the clipboard write failed.
  final String copyFailed;

  final String verifyTitle;

  /// Progress through the challenges, for example "1 of 3".
  final String Function(int current, int total) verifyProgress;

  /// Asks for the word at a 1-based position.
  final String Function(int position) verifyPrompt;

  /// Shown after a wrong answer; receives the 1-based position.
  final String Function(int position) verifyWrong;

  final String importTitle;
  final String importInstruction;
  final String importHint;
  final String importPaste;

  /// Shown when the clipboard could not be read for a paste.
  final String pasteFailed;
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
