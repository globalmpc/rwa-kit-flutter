import 'package:bip39_mnemonic/bip39_mnemonic.dart' show Language;
import 'package:flutter/widgets.dart';

import 'challenge.dart';
import 'mnemonic_words.dart';
import 'protected_screen.dart';
import 'reveal_builder.dart';
import 'screen_protection.dart';
import 'secret_phase.dart';
import 'verify_builder.dart';

/// The reveal step, then the verify step, behind one hold on the app's screen protection, drawn
/// by the app: what [showMnemonicBackupFlow] shows, without its look.
///
/// [screenProtection] is switched on before anything is drawn and off when this widget goes away,
/// so the two steps never hold the plugin twice and it is never off between them. Until it is
/// active, [waitingBuilder] draws the step with [MnemonicSecretPhase.preparing] or
/// [MnemonicSecretPhase.protectionFailed]. Then [revealBuilder] draws the reveal step, and once
/// the user confirms the phrase is written down, [verifyBuilder] draws the verify step.
/// [onVerified] is called once, when every challenge has been answered correctly.
///
/// Show it on a route of its own, after the app's own authentication, as [showMnemonicBackupFlow]
/// does. It draws nothing itself and needs no Material ancestor or theme, so it fits any design
/// system.
class MnemonicBackupFlowBuilder extends StatefulWidget {
  /// Draws the backup flow with the three builders.
  const MnemonicBackupFlowBuilder({
    super.key,
    required this.words,
    required this.screenProtection,
    required this.onVerified,
    required this.waitingBuilder,
    required this.revealBuilder,
    required this.verifyBuilder,
    this.challengeCount = 3,
    this.language,
    this.allowCopy = false,
    this.obscureUntilShown = true,
    this.protectionTimeout = const Duration(seconds: 15),
  });

  /// The phrase to back up.
  final MnemonicWords words;

  /// Held once for both steps.
  final ScreenProtection screenProtection;

  /// Called once, when every challenge has been answered correctly.
  final VoidCallback onVerified;

  /// Draws the flow while the protection is not yet active, or failed. The phase is
  /// [MnemonicSecretPhase.preparing] or [MnemonicSecretPhase.protectionFailed]; show
  /// `strings.placeholder(phase)`.
  final Widget Function(BuildContext context, MnemonicSecretPhase phase)
  waitingBuilder;

  /// Draws the reveal step. See [MnemonicRevealBuilder].
  final Widget Function(BuildContext context, MnemonicRevealState state)
  revealBuilder;

  /// Draws the verify step. See [MnemonicVerifyBuilder].
  final Widget Function(BuildContext context, MnemonicVerifyState state)
  verifyBuilder;

  /// How many positions the verify step asks for, from 1 to the number of words. Checked when the
  /// flow starts, before the protection is switched on and the words are shown.
  final int challengeCount;

  /// The word list the verify step draws its decoys from. Null, the default, uses the phrase's
  /// own, [MnemonicWordsLanguage.language]; one that differs would give the right word away.
  final Language? language;

  /// Whether the reveal step offers copying.
  final bool allowCopy;

  /// Whether the reveal step keeps the words covered until the user asks to see them.
  final bool obscureUntilShown;

  /// How long to wait for the screen protection before giving up. Null waits without limit.
  final Duration? protectionTimeout;

  @override
  State<MnemonicBackupFlowBuilder> createState() =>
      _MnemonicBackupFlowBuilderState();
}

/// The steps are given [ScreenProtection.none], since this widget already holds the real one;
/// they are built only once it is active, so their own phase never shows an unprotected frame.
class _MnemonicBackupFlowBuilderState extends State<MnemonicBackupFlowBuilder>
    with ProtectedScreenState<MnemonicBackupFlowBuilder> {
  late List<VerificationChallenge> _challenges;
  bool _wroteDown = false;

  @override
  void initState() {
    // Before super.initState(), which switches the protection on: an unusable count is said
    // here, not after the user has seen the words and the verify step fails to build.
    _challenges = _challengesOf(widget);
    super.initState();
  }

  static List<VerificationChallenge> _challengesOf(
    MnemonicBackupFlowBuilder widget,
  ) => challengesFor(
    widget.words,
    language: widget.language,
    count: widget.challengeCount,
  );

  @override
  void didUpdateWidget(MnemonicBackupFlowBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new phrase starts the flow over from the reveal step, with questions about it. Nothing
    // else changes the questions already made.
    if (isNewPhrase(oldWidget.words, widget.words)) {
      _challenges = _challengesOf(widget);
      _wroteDown = false;
    }
  }

  @override
  ScreenProtection get screenProtection => widget.screenProtection;

  @override
  Duration? get protectionTimeout => widget.protectionTimeout;

  @override
  Widget build(BuildContext context) {
    if (!protectionActive) {
      return widget.waitingBuilder(context, secretPhase);
    }
    if (!_wroteDown) {
      return MnemonicRevealBuilder(
        words: widget.words,
        screenProtection: const ScreenProtection.none(),
        allowCopy: widget.allowCopy,
        obscureUntilShown: widget.obscureUntilShown,
        onConfirmed: () {
          if (mounted) setState(() => _wroteDown = true);
        },
        builder: widget.revealBuilder,
      );
    }
    return MnemonicVerifyBuilder(
      words: widget.words,
      screenProtection: const ScreenProtection.none(),
      challenges: _challenges,
      onVerified: widget.onVerified,
      builder: widget.verifyBuilder,
    );
  }
}
