import 'package:bip39_mnemonic/bip39_mnemonic.dart' show Language;
import 'package:flutter/widgets.dart';

import 'clipboard_calls.dart';
import 'mnemonic_words.dart';
import 'protected_screen.dart';
import 'report.dart';
import 'screen_protection.dart';
import 'secret_phase.dart';

/// What the import step shows and allows at this moment, given to
/// [MnemonicImportBuilder.builder].
class MnemonicImportState {
  /// [MnemonicImportBuilder] makes these. Public so that an app can test its own step with any
  /// state it wants to see; in the app itself, take the one the builder hands over.
  @visibleForTesting
  const MnemonicImportState({
    required this.phase,
    required this.controller,
    required this.error,
    required this.allowPaste,
    required this.pasting,
    required this.onSubmit,
    required this.onPaste,
  });

  /// Whether the phrase may be on screen at all, and if not, why. Show
  /// `strings.placeholder(phase)` in place of the input for every phase but
  /// [MnemonicSecretPhase.visible].
  final MnemonicSecretPhase phase;

  /// The text of the input. Null unless the phase is [MnemonicSecretPhase.visible]: draw the field
  /// only with it. Turn autocorrect and suggestions off on the field, as a phrase must not reach a
  /// keyboard's dictionary. The text is kept while the field is hidden.
  final TextEditingController? controller;

  /// Why the last [onSubmit] refused the text, or null. Cleared when the text changes. Show it
  /// with `strings.importError`. Null unless the phase is [MnemonicSecretPhase.visible], like
  /// [controller]: an unknown word is usually a misspelled word of the phrase.
  final MnemonicFormatException? error;

  /// Whether the app offers a paste action. Draw it, disabled while [onPaste] is null.
  final bool allowPaste;

  /// Whether a paste is under way.
  final bool pasting;

  /// Checks the text and, when it is a valid phrase, passes it to
  /// [MnemonicImportBuilder.onImported]; otherwise sets [error]. Non-null once the screen
  /// protection is active. Each call with a valid phrase calls onImported again, so an app that
  /// rejected the phrase and stayed can let the user retry; an app that leaves the step from
  /// onImported should leave once.
  final VoidCallback? onSubmit;

  /// Reads the clipboard into the input and then empties the clipboard, so the phrase does not
  /// stay there. Non-null with [allowPaste], once the protection is active and while no paste is
  /// under way. Completes with false only when the clipboard could not be read (show
  /// `strings.pasteFailed`).
  final Future<bool> Function()? onPaste;
}

/// The import step of [MnemonicImportScreen] without its look: the same rules, drawn by
/// [builder].
///
/// The input is handed over only once [screenProtection] is active and never while the app is not
/// in the foreground. A paste empties the clipboard afterwards. A valid phrase is handed back as
/// [MnemonicWords] through [onImported].
///
/// It draws nothing itself and needs no Material ancestor or theme, so it fits any design system.
class MnemonicImportBuilder extends StatefulWidget {
  /// Draws the import step with [builder].
  const MnemonicImportBuilder({
    super.key,
    required this.onImported,
    required this.screenProtection,
    required this.builder,
    this.language = Language.english,
    this.allowPaste = true,
    this.protectionTimeout = const Duration(seconds: 15),
  });

  /// Called with the validated phrase, each time a valid phrase is submitted. If it leaves the
  /// step, make it leave once: a double tap submits twice.
  final void Function(MnemonicWords words) onImported;

  /// Switched on before the input is handed over, and off when this step goes away.
  final ScreenProtection screenProtection;

  /// Draws the step from its current state.
  final Widget Function(BuildContext context, MnemonicImportState state)
  builder;

  /// The word list the phrase is checked against.
  final Language language;

  /// Whether to offer pasting.
  final bool allowPaste;

  /// How long to wait for the screen protection before giving up. Null waits without limit.
  final Duration? protectionTimeout;

  @override
  State<MnemonicImportBuilder> createState() => _MnemonicImportBuilderState();
}

class _MnemonicImportBuilderState extends State<MnemonicImportBuilder>
    with ProtectedScreenState<MnemonicImportBuilder> {
  final _controller = TextEditingController();
  String _lastText = '';
  MnemonicFormatException? _error;
  bool _pasting = false;

  // Weak, as ProtectedScreenState's own work is: a callback the app keeps must not keep this
  // disposed step, and the phrase typed into it, in memory.
  late final _self = WeakReference(this);

  @override
  ScreenProtection get screenProtection => widget.screenProtection;

  @override
  Duration? get protectionTimeout => widget.protectionTimeout;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_textChanged);
  }

  @override
  void didUpdateWidget(MnemonicImportBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A check against the old word list no longer says anything about the text, and the text may
    // now be a phrase to import.
    if (oldWidget.language != widget.language) {
      _error = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// An edit clears the last error. The controller also notifies for a moved cursor, which is not
  /// an edit, so the text itself is compared.
  void _textChanged() {
    final text = _controller.text;
    if (text == _lastText) return;
    _lastText = text;
    if (_error != null && mounted) {
      setState(() => _error = null);
    }
  }

  Future<bool> _paste() async {
    if (!mounted || !widget.allowPaste || !protectionActive || _pasting) {
      return true;
    }
    setState(() => _pasting = true);
    try {
      return await _pasteOnce();
    } finally {
      if (mounted) {
        setState(() => _pasting = false);
      }
    }
  }

  Future<bool> _pasteOnce() async {
    final String? text;
    try {
      text = await readClipboardText();
    } catch (error, stack) {
      reportBackupFlowError(
        error,
        stack,
        'while reading the clipboard for a paste',
      );
      return false;
    }
    if (text == null || text.isEmpty) {
      return true;
    }
    if (mounted) {
      _controller.text = text;
      // A paste clears the error even when it brings back the same text.
      if (_error != null) setState(() => _error = null);
    }
    // Read into the app, the phrase must not stay on the clipboard, whether or not the step is
    // still there to show it.
    try {
      await writeClipboardText('');
    } catch (error, stack) {
      reportBackupFlowError(
        error,
        stack,
        'while emptying the clipboard after a paste',
      );
    }
    return true;
  }

  void _submit() {
    if (!mounted || !protectionActive) return;
    try {
      final words = MnemonicWords.parse(
        _controller.text,
        language: widget.language,
      );
      widget.onImported(words);
    } on MnemonicFormatException catch (exception) {
      setState(() => _error = exception);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = protectionActive;
    final self = _self;
    return widget.builder(
      context,
      MnemonicImportState(
        phase: secretPhase,
        controller: secretVisible ? _controller : null,
        error: secretVisible ? _error : null,
        allowPaste: widget.allowPaste,
        pasting: _pasting,
        onSubmit: active ? () => self.target?._submit() : null,
        onPaste: widget.allowPaste && active && !_pasting
            ? () async => await self.target?._paste() ?? true
            : null,
      ),
    );
  }
}
