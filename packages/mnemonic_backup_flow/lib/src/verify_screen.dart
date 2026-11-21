import 'package:bip39_mnemonic/bip39_mnemonic.dart' show Language;

import 'challenge.dart';
import 'material_import.dart';
import 'mnemonic_words.dart';
import 'screen_protection.dart';
import 'strings.dart';
import 'verify_builder.dart';

/// Asks for the words at a few distinct positions, one at a time, as multiple choice.
///
/// Every list of choices holds a real word of the phrase, so the choices appear only once the
/// screen protection is active and are hidden while the app is not in the foreground, as the
/// words are on the reveal screen. A wrong answer shows
/// [MnemonicBackupStrings.verifyWrong] and lets the user try again; the app decides whether
/// repeated failures should end the flow through [onWrongAnswer]. For a look of your own with the
/// same rules, use [MnemonicVerifyBuilder].
class MnemonicVerifyScreen extends StatefulWidget {
  /// The verify screen, in Material.
  const MnemonicVerifyScreen({
    super.key,
    required this.words,
    required this.screenProtection,
    required this.onVerified,
    this.challenges,
    this.challengeCount = 3,
    this.choiceCount = 4,
    this.language = Language.english,
    this.onWrongAnswer,
    this.strings = const MnemonicBackupStrings(),
    this.protectionTimeout = const Duration(seconds: 15),
  });

  /// The phrase being verified.
  final MnemonicWords words;

  /// Switched on before the choices are shown, and off when the screen goes away.
  final ScreenProtection screenProtection;

  /// Called once, when every challenge has been answered correctly. Further taps are ignored, so
  /// a double tap on the last answer cannot call it twice.
  final VoidCallback onVerified;

  /// Challenges to use, at least one. When null, [challengeCount] challenges are generated when the
  /// screen is created; an unusable count throws then, before the protection is switched on.
  final List<VerificationChallenge>? challenges;

  /// How many positions to ask for, when [challenges] is null.
  final int challengeCount;

  /// How many choices each challenge offers, the right word included, when [challenges] is null.
  final int choiceCount;

  /// The word list decoys are drawn from. Must match the language the phrase was generated in.
  final Language language;

  /// Receives the 1-based position after each wrong answer.
  final void Function(int position)? onWrongAnswer;

  /// The texts of the screen.
  final MnemonicBackupStrings strings;

  /// How long to wait for the screen protection before giving up. Null waits without limit.
  final Duration? protectionTimeout;

  @override
  State<MnemonicVerifyScreen> createState() => _MnemonicVerifyScreenState();
}

// A State only so the widget's public type stays what earlier versions shipped; the rules live in
// MnemonicVerifyBuilder.
class _MnemonicVerifyScreenState extends State<MnemonicVerifyScreen> {
  @override
  Widget build(BuildContext context) => MnemonicVerifyBuilder(
    words: widget.words,
    screenProtection: widget.screenProtection,
    onVerified: widget.onVerified,
    challenges: widget.challenges,
    challengeCount: widget.challengeCount,
    choiceCount: widget.choiceCount,
    language: widget.language,
    onWrongAnswer: widget.onWrongAnswer,
    protectionTimeout: widget.protectionTimeout,
    builder: (context, state) =>
        materialVerifyView(context, state, widget.strings),
  );
}

/// The Material look of the verify step, shared by [MnemonicVerifyScreen] and
/// [showMnemonicBackupFlow]. Not exported.
Widget materialVerifyView(
  BuildContext context,
  MnemonicVerifyState state,
  MnemonicBackupStrings strings,
) {
  final theme = Theme.of(context);
  final challenge = state.challenge;
  final onAnswer = state.onAnswer;
  return Scaffold(
    appBar: AppBar(title: Text(strings.verifyTitle)),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.verifyProgress(state.step, state.stepCount),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            if (challenge != null) ...[
              Text(
                strings.verifyPrompt(challenge.position),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              for (final choice in challenge.choices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: onAnswer == null ? null : () => onAnswer(choice),
                    child: Text(choice),
                  ),
                ),
              if (state.wrong)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    strings.verifyWrong(challenge.position),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ] else
              Text(
                strings.placeholder(state.phase) ?? '',
                style: theme.textTheme.bodyLarge,
              ),
          ],
        ),
      ),
    ),
  );
}
