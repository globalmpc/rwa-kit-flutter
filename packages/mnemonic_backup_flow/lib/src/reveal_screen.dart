import 'package:flutter/material.dart';

import 'mnemonic_words.dart';
import 'protected_screen.dart';
import 'report.dart';
import 'screen_protection.dart';
import 'sensitive_clipboard.dart';
import 'strings.dart';

/// Shows the phrase, numbered, once the screen protection is active and the user has asked to
/// see it, and hides it while the app is not in the foreground so the app switcher snapshot does
/// not carry it.
///
/// Reaching this screen is the app's decision. [showMnemonicBackupFlow] only pushes it after the
/// caller's authentication returned true; if you push it yourself, gate it the same way.
class MnemonicRevealScreen extends StatefulWidget {
  const MnemonicRevealScreen({
    super.key,
    required this.words,
    required this.screenProtection,
    required this.onConfirmed,
    this.strings = const MnemonicBackupStrings(),
    this.allowCopy = false,
    this.obscureUntilShown = true,
    this.clipboardClearAfter = const Duration(seconds: 30),
    this.protectionTimeout = const Duration(seconds: 15),
  });

  final MnemonicWords words;
  final ScreenProtection screenProtection;

  /// Called when the user confirms the phrase is written down.
  final VoidCallback onConfirmed;

  final MnemonicBackupStrings strings;

  /// Whether to offer a copy button. Off by default: a clipboard is readable by other apps.
  final bool allowCopy;

  /// When true, the words stay covered until the user asks to see them, and they are covered
  /// again whenever the app leaves the foreground. The confirm button stays disabled until the
  /// words are on screen. False shows the words as soon as the protection is active.
  final bool obscureUntilShown;

  /// How long a copied phrase stays on the clipboard.
  final Duration clipboardClearAfter;

  /// How long to wait for the screen protection before giving up. Null waits without limit.
  final Duration? protectionTimeout;

  @override
  State<MnemonicRevealScreen> createState() => _MnemonicRevealScreenState();
}

class _MnemonicRevealScreenState extends State<MnemonicRevealScreen>
    with ProtectedScreenState<MnemonicRevealScreen> {
  SensitiveClipboard? _clipboard;
  bool _shown = false;

  /// The words are painted only while the protection allows it and, unless the screen was asked
  /// not to, the user has uncovered them since the app last left the foreground.
  bool get _wordsOnScreen =>
      secretVisible && (!widget.obscureUntilShown || _shown);

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
  void dispose() {
    _clipboard?.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final clipboard = _clipboard ??= SensitiveClipboard(
      clearAfter: widget.clipboardClearAfter,
    );
    String notice;
    try {
      await clipboard.copy(widget.words.sentence);
      notice = widget.strings.copiedFor(widget.clipboardClearAfter.inSeconds);
    } catch (error, stack) {
      reportBackupFlowError(error, stack, 'while copying the phrase');
      notice = widget.strings.copyFailed;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final theme = Theme.of(context);
    final visible = _wordsOnScreen;
    return Scaffold(
      appBar: AppBar(title: Text(strings.revealTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(strings.revealWarning, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 16),
              Expanded(child: _body(strings, theme, visible)),
              if (widget.allowCopy)
                TextButton.icon(
                  onPressed: visible ? _copy : null,
                  icon: const Icon(Icons.copy),
                  label: Text(strings.copy),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: visible ? widget.onConfirmed : null,
                child: Text(strings.revealConfirm),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(MnemonicBackupStrings strings, ThemeData theme, bool visible) {
    if (!secretVisible) {
      return Center(
        child: Text(
          secretPlaceholder(strings),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge,
        ),
      );
    }
    if (!visible) {
      // A scroll view, not a column that must fit: two of these screens can share a short
      // route, and a column taller than that space is an overflow.
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        strings.revealCovered,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => setState(() => _shown = true),
                        child: Text(strings.revealShow),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    return _WordGrid(words: widget.words.words);
  }
}

class _WordGrid extends StatelessWidget {
  const _WordGrid({required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Selection is disabled so the words cannot be copied through a long press; copying, when the
    // app allows it, goes through the button and its timed clipboard clearing.
    return SelectionContainer.disabled(
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var index = 0; index < words.length; index++)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}. ${words[index]}',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
