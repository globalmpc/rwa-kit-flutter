import 'dart:async';

import 'package:flutter/widgets.dart';

import 'mnemonic_words.dart';
import 'protected_screen.dart';
import 'report.dart';
import 'screen_protection.dart';
import 'secret_phase.dart';
import 'sensitive_clipboard.dart';

/// What the reveal step shows and allows at this moment, given to
/// [MnemonicRevealBuilder.builder].
///
/// The words are only handed over while they may be painted, so a custom design cannot show
/// them early by mistake.
class MnemonicRevealState {
  /// [MnemonicRevealBuilder] makes these. Public so that an app can test its own step with any
  /// state it wants to see; in the app itself, take the one the builder hands over.
  @visibleForTesting
  const MnemonicRevealState({
    required this.phase,
    required this.words,
    required this.allowCopy,
    required this.clipboardClearAfter,
    required this.onShow,
    required this.onConfirmed,
    required this.onCopy,
  });

  /// Whether the secret may be on screen at all, and if not, why. Show
  /// `strings.placeholder(phase)` in place of the words for every phase but
  /// [MnemonicSecretPhase.visible].
  final MnemonicSecretPhase phase;

  /// The words in order, the first at index 0. Null unless they may be painted now: the
  /// protection is on, the app is in the foreground, and, unless
  /// [MnemonicRevealBuilder.obscureUntilShown] is false, the user has asked to see them since the
  /// app last left the foreground. Number them from 1 when you show them.
  final List<String>? words;

  /// Whether the app offers a copy action. Draw it, disabled while [onCopy] is null.
  final bool allowCopy;

  /// How long a copied phrase stays on the clipboard, for the notice after [onCopy].
  final Duration clipboardClearAfter;

  /// Uncovers the words. Non-null only while the words are covered and could be shown: show
  /// `strings.revealCovered` with a button for it in place of the words.
  final VoidCallback? onShow;

  /// The user confirms the phrase is written down. Non-null only while the words are on screen.
  final VoidCallback? onConfirmed;

  /// Copies the phrase to the clipboard, which is emptied again after [clipboardClearAfter].
  /// Non-null only with [allowCopy] and the words on screen. Completes with true when the phrase
  /// was copied (show `strings.copiedFor`), false when the copy failed (show `strings.copyFailed`),
  /// and null when nothing was tried because the words are no longer on screen (show nothing).
  final Future<bool?> Function()? onCopy;

  /// Whether the words are covered and waiting for [onShow].
  bool get covered => onShow != null;
}

/// The reveal step of [MnemonicRevealScreen] without its look: the same rules, drawn by
/// [builder].
///
/// - The words are handed over only once [screenProtection] is active, and never while the app is
///   not in the foreground, so the app switcher snapshot does not carry them.
/// - With [obscureUntilShown], the words stay covered until the user asks to see them, and are
///   covered again every time the app leaves the foreground.
/// - Confirming and copying are possible only while the words are on screen.
/// - A copy goes through a clipboard that is emptied after [clipboardClearAfter].
///
/// Every callback the state hands out checks its condition again when it is called, so one kept
/// from an earlier state does nothing once the words are no longer on screen.
///
/// Reaching this step is the app's decision. [showMnemonicBackupFlow] only shows it after the
/// caller's authentication returned true; if you show it yourself, gate it the same way. It draws
/// nothing itself and needs no Material ancestor or theme, so it fits any design system.
class MnemonicRevealBuilder extends StatefulWidget {
  /// Draws the reveal step with [builder].
  const MnemonicRevealBuilder({
    super.key,
    required this.words,
    required this.screenProtection,
    required this.onConfirmed,
    required this.builder,
    this.allowCopy = false,
    this.obscureUntilShown = true,
    this.clipboardClearAfter = const Duration(seconds: 30),
    this.protectionTimeout = const Duration(seconds: 15),
  });

  /// The phrase to show.
  final MnemonicWords words;

  /// Switched on before the words are handed over, and off when this step goes away.
  final ScreenProtection screenProtection;

  /// Called when the user confirms the phrase is written down.
  final VoidCallback onConfirmed;

  /// Draws the step from its current state.
  final Widget Function(BuildContext context, MnemonicRevealState state)
  builder;

  /// Whether to offer copying. Off by default: a clipboard is readable by other apps.
  final bool allowCopy;

  /// When true, the words stay covered until the user asks to see them, and they are covered
  /// again whenever the app leaves the foreground. False hands them over as soon as the
  /// protection is active and the app is in the foreground.
  final bool obscureUntilShown;

  /// How long a copied phrase stays on the clipboard.
  final Duration clipboardClearAfter;

  /// How long to wait for the screen protection before giving up. Null waits without limit.
  final Duration? protectionTimeout;

  @override
  State<MnemonicRevealBuilder> createState() => _MnemonicRevealBuilderState();
}

class _MnemonicRevealBuilderState extends State<MnemonicRevealBuilder>
    with ProtectedScreenState<MnemonicRevealBuilder> {
  SensitiveClipboard? _clipboard;
  bool _shown = false;

  /// Counts the phrases this step has shown. A callback carries the round it was handed out in,
  /// so one kept from an old phrase does nothing for a new one, even one shown at once.
  int _round = 0;

  // Weak, as ProtectedScreenState's own work is: a callback the app keeps must not keep this
  // disposed step, and the phrase it holds, in memory.
  late final _self = WeakReference(this);

  /// The words are painted only while the protection allows it and, unless the step was asked
  /// not to, the user has uncovered them since the app last left the foreground.
  bool get _wordsOnScreen =>
      secretVisible && (!widget.obscureUntilShown || _shown);

  bool get _covered => secretVisible && !_wordsOnScreen;

  @override
  ScreenProtection get screenProtection => widget.screenProtection;

  @override
  Duration? get protectionTimeout => widget.protectionTimeout;

  @override
  void onLeftForeground() {
    // Cleared on the lifecycle notification itself. Waiting for a background frame would leave
    // the words showing if the app returned before that frame was built.
    _shown = false;
  }

  @override
  void didUpdateWidget(MnemonicRevealBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new phrase is covered again: the user asked to see the old one, not this one. And the old
    // one comes off the clipboard now, not when its timer ends.
    if (isNewPhrase(oldWidget.words, widget.words)) {
      _shown = false;
      _round++;
      // On the clipboard's own queue, so a copy of the new phrase made right after waits for it:
      // a clipboard of its own would clear on a queue of its own, and could wipe the new phrase.
      final clipboard = _clipboard;
      if (clipboard != null) {
        unawaited(
          clipboard.clear().catchError(
            (Object error, StackTrace stack) => reportBackupFlowError(
              error,
              stack,
              'while clearing the previous phrase from the clipboard',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _clipboard?.dispose();
    super.dispose();
  }

  void _show(int round) {
    if (!mounted || round != _round || !_covered) return;
    setState(() => _shown = true);
  }

  void _confirm(int round) {
    if (!mounted || round != _round || !_wordsOnScreen) return;
    widget.onConfirmed();
  }

  Future<bool?> _copy(int round) async {
    if (!mounted || round != _round || !widget.allowCopy || !_wordsOnScreen) {
      return null;
    }
    final clipboard = _clipboard ??= SensitiveClipboard(
      clearAfter: widget.clipboardClearAfter,
    );
    bool copied;
    try {
      await clipboard.copy(widget.words.sentence);
      copied = true;
    } catch (error, stack) {
      reportBackupFlowError(error, stack, 'while copying the phrase');
      copied = false;
    }
    // A new phrase arrived while the copy was under way, whether it worked or not: the old phrase
    // is being cleared again, so there is nothing to tell the user about it.
    if (!mounted || round != _round) return null;
    return copied;
  }

  @override
  Widget build(BuildContext context) {
    final onScreen = _wordsOnScreen;
    final self = _self;
    final round = _round;
    return widget.builder(
      context,
      MnemonicRevealState(
        phase: secretPhase,
        // Already unmodifiable: handed over as it is, not copied on every build.
        words: onScreen ? widget.words.words : null,
        allowCopy: widget.allowCopy,
        // The clipboard keeps the time it was made with; say that one.
        clipboardClearAfter:
            _clipboard?.clearAfter ?? widget.clipboardClearAfter,
        onShow: _covered ? () => self.target?._show(round) : null,
        onConfirmed: onScreen ? () => self.target?._confirm(round) : null,
        onCopy: widget.allowCopy && onScreen
            ? () async => self.target?._copy(round)
            : null,
      ),
    );
  }
}
