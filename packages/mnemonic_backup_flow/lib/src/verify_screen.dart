import 'package:bip39_mnemonic/bip39_mnemonic.dart' show Language;
import 'package:flutter/material.dart';

import 'challenge.dart';
import 'mnemonic_words.dart';
import 'strings.dart';

/// Asks for the words at a few distinct positions, one at a time, as multiple choice.
///
/// A wrong answer shows [MnemonicBackupStrings.verifyWrong] and lets the user try again; the
/// app decides whether repeated failures should end the flow through [onWrongAnswer].
class MnemonicVerifyScreen extends StatefulWidget {
  const MnemonicVerifyScreen({
    super.key,
    required this.words,
    required this.onVerified,
    this.challenges,
    this.challengeCount = 3,
    this.choiceCount = 4,
    this.language = Language.english,
    this.onWrongAnswer,
    this.strings = const MnemonicBackupStrings(),
  });

  final MnemonicWords words;

  /// Called once every challenge has been answered correctly.
  final VoidCallback onVerified;

  /// Challenges to use, at least one. When null, [challengeCount] challenges are generated on
  /// first build.
  final List<VerificationChallenge>? challenges;

  final int challengeCount;
  final int choiceCount;

  /// The word list decoys are drawn from. Must match the language the phrase was generated in.
  final Language language;

  /// Receives the 1-based position after each wrong answer.
  final void Function(int position)? onWrongAnswer;

  final MnemonicBackupStrings strings;

  @override
  State<MnemonicVerifyScreen> createState() => _MnemonicVerifyScreenState();
}

class _MnemonicVerifyScreenState extends State<MnemonicVerifyScreen> {
  late final List<VerificationChallenge> _challenges =
      widget.challenges ??
      generateChallenges(
        widget.words.words,
        wordList: widget.language.list,
        count: widget.challengeCount,
        choiceCount: widget.choiceCount,
      );
  int _index = 0;
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    final given = widget.challenges;
    if (given != null && given.isEmpty) {
      // Said here, not as a RangeError on the first build.
      throw ArgumentError.value(given, 'challenges', 'must not be empty');
    }
  }

  void _answer(String choice) {
    final challenge = _challenges[_index];
    if (!challenge.accepts(choice)) {
      setState(() => _wrong = true);
      widget.onWrongAnswer?.call(challenge.position);
      return;
    }
    if (_index + 1 == _challenges.length) {
      widget.onVerified();
      return;
    }
    setState(() {
      _wrong = false;
      _index++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final theme = Theme.of(context);
    final challenge = _challenges[_index];
    return Scaffold(
      appBar: AppBar(title: Text(strings.verifyTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.verifyProgress(_index + 1, _challenges.length),
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Text(
                strings.verifyPrompt(challenge.position),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              for (final choice in challenge.choices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: () => _answer(choice),
                    child: Text(choice),
                  ),
                ),
              if (_wrong)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    strings.verifyWrong(challenge.position),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
