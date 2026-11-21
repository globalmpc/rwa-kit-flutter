import 'package:bip39_mnemonic/bip39_mnemonic.dart' show Language;
import 'package:flutter/widgets.dart';

import 'challenge.dart';
import 'mnemonic_words.dart';
import 'protected_screen.dart';
import 'screen_protection.dart';
import 'secret_phase.dart';

/// What the verify step shows and allows at this moment, given to
/// [MnemonicVerifyBuilder.builder].
///
/// Every list of choices holds a real word of the phrase, so the current challenge is only
/// handed over while it may be painted.
class MnemonicVerifyState {
  /// [MnemonicVerifyBuilder] makes these. Public so that an app can test its own step with any
  /// state it wants to see; in the app itself, take the one the builder hands over.
  @visibleForTesting
  const MnemonicVerifyState({
    required this.phase,
    required this.step,
    required this.stepCount,
    required this.challenge,
    required this.wrong,
    required this.verified,
    required this.onAnswer,
  });

  /// Whether the choices may be on screen at all, and if not, why. Show
  /// `strings.placeholder(phase)` in their place for every phase but
  /// [MnemonicSecretPhase.visible].
  final MnemonicSecretPhase phase;

  /// The 1-based number of the current challenge, and how many there are, for
  /// `strings.verifyProgress`. Safe to show in every phase: neither names a word.
  final int step;

  /// How many challenges there are in all.
  final int stepCount;

  /// The current challenge: ask for the word at its `position` and offer its `choices`. Null
  /// unless the phase is [MnemonicSecretPhase.visible].
  final VerificationChallenge? challenge;

  /// Whether the last answer to the current challenge was wrong. Show `strings.verifyWrong` with
  /// the challenge's position under the choices.
  final bool wrong;

  /// Whether every challenge has been answered correctly.
  final bool verified;

  /// Answers the current challenge with one of its choices. Non-null only while [challenge] is on
  /// screen and the step is not yet verified. A callback kept from an earlier challenge does
  /// nothing.
  final void Function(String choice)? onAnswer;
}

/// The verify step of [MnemonicVerifyScreen] without its look: the same rules, drawn by
/// [builder].
///
/// It asks for the words at a few distinct positions, one at a time, as multiple choice. The
/// choices are handed over only once [screenProtection] is active and never while the app is not
/// in the foreground. A wrong answer sets `wrong` and lets the user try again; the app decides
/// whether repeated failures should end the flow through [onWrongAnswer]. [onVerified] is called
/// once, when every challenge has been answered correctly.
///
/// It draws nothing itself and needs no Material ancestor or theme, so it fits any design system.
class MnemonicVerifyBuilder extends StatefulWidget {
  /// Draws the verify step with [builder].
  const MnemonicVerifyBuilder({
    super.key,
    required this.words,
    required this.screenProtection,
    required this.onVerified,
    required this.builder,
    this.challenges,
    this.challengeCount = 3,
    this.choiceCount = 4,
    this.language,
    this.onWrongAnswer,
    this.protectionTimeout = const Duration(seconds: 15),
  });

  /// The phrase being verified.
  final MnemonicWords words;

  /// Switched on before the choices are handed over, and off when this step goes away.
  final ScreenProtection screenProtection;

  /// Called once, when every challenge has been answered correctly. Further answers are ignored,
  /// so a double tap on the last answer cannot call it twice.
  final VoidCallback onVerified;

  /// Draws the step from its current state.
  final Widget Function(BuildContext context, MnemonicVerifyState state)
  builder;

  /// Challenges to use, at least one. When null, [challengeCount] challenges are generated when the
  /// step is created; an unusable count throws then, before the protection is switched on. The
  /// questions are kept for the life of the step: only a new [words] starts it over.
  final List<VerificationChallenge>? challenges;

  /// How many positions to ask for, when [challenges] is null.
  final int challengeCount;

  /// How many choices each challenge offers, the right word included, when [challenges] is null.
  final int choiceCount;

  /// The word list decoys are drawn from. Null, the default, uses the phrase's own,
  /// [MnemonicWordsLanguage.language]; one that differs would give the right word away.
  final Language? language;

  /// Receives the 1-based position after each wrong answer.
  final void Function(int position)? onWrongAnswer;

  /// How long to wait for the screen protection before giving up. Null waits without limit.
  final Duration? protectionTimeout;

  @override
  State<MnemonicVerifyBuilder> createState() => _MnemonicVerifyBuilderState();
}

/// The challenges a verify step asks: [given], or [count] generated from [words] with decoys from
/// [language], or the phrase's own list when that is null. The one place that rule lives, used by
/// [MnemonicVerifyBuilder] and [MnemonicBackupFlowBuilder]. Not exported.
List<VerificationChallenge> challengesFor(
  MnemonicWords words, {
  List<VerificationChallenge>? given,
  Language? language,
  int count = 3,
  int choiceCount = 4,
}) {
  if (given != null) {
    if (given.isEmpty) {
      throw ArgumentError.value(given, 'challenges', 'must not be empty');
    }
    return given;
  }
  return generateChallenges(
    words.words,
    wordList: (language ?? words.language).list,
    count: count,
    choiceCount: choiceCount,
  );
}

class _MnemonicVerifyBuilderState extends State<MnemonicVerifyBuilder>
    with ProtectedScreenState<MnemonicVerifyBuilder> {
  late List<VerificationChallenge> _challenges;
  int _index = 0;
  bool _wrong = false;
  bool _verified = false;

  /// Counts the times the step has started over for a new phrase. An answer carries the round it
  /// was handed out in, so one kept from the old phrase cannot answer the new one.
  int _round = 0;

  // Weak, as ProtectedScreenState's own work is: a callback the app keeps must not keep this
  // disposed step, and the phrase it holds, in memory.
  late final _self = WeakReference(this);

  @override
  ScreenProtection get screenProtection => widget.screenProtection;

  @override
  Duration? get protectionTimeout => widget.protectionTimeout;

  @override
  void initState() {
    // Before super.initState(), which switches the protection on: a State whose initState throws
    // is never disposed. An unusable count or an empty list is said here, not as a RangeError on
    // the first build.
    _challenges = _challengesOf(widget);
    super.initState();
  }

  static List<VerificationChallenge> _challengesOf(
    MnemonicVerifyBuilder widget,
  ) => challengesFor(
    widget.words,
    given: widget.challenges,
    language: widget.language,
    count: widget.challengeCount,
    choiceCount: widget.choiceCount,
  );

  @override
  void didUpdateWidget(MnemonicVerifyBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new phrase starts the step over: the old questions would verify a phrase the user is no
    // longer being asked about. Nothing else does, as in earlier versions, so an app that makes
    // new challenges on every rebuild does not send the user back to the first question.
    if (!isNewPhrase(oldWidget.words, widget.words)) return;
    _challenges = _challengesOf(widget);
    _index = 0;
    _wrong = false;
    _verified = false;
    _round++;
  }

  void _answer(int round, int index, String choice) {
    // A callback handed out for an earlier challenge or an earlier phrase, or one called while the
    // choices are no longer on screen, answers nothing.
    if (!mounted ||
        _verified ||
        round != _round ||
        index != _index ||
        !secretVisible) {
      return;
    }
    final challenge = _challenges[_index];
    if (!challenge.accepts(choice)) {
      setState(() => _wrong = true);
      widget.onWrongAnswer?.call(challenge.position);
      return;
    }
    if (_index + 1 == _challenges.length) {
      setState(() {
        _verified = true;
        _wrong = false;
      });
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
    final visible = secretVisible;
    final (round, index) = (_round, _index);
    final self = _self;
    return widget.builder(
      context,
      MnemonicVerifyState(
        phase: secretPhase,
        step: index + 1,
        stepCount: _challenges.length,
        challenge: visible ? _challenges[index] : null,
        wrong: _wrong,
        verified: _verified,
        onAnswer: visible && !_verified
            ? (choice) => self.target?._answer(round, index, choice)
            : null,
      ),
    );
  }
}
