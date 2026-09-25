import 'package:bip39_mnemonic/bip39_mnemonic.dart' show Language;
import 'package:flutter/material.dart';

import 'mnemonic_words.dart';
import 'clipboard_calls.dart';
import 'protected_screen.dart';
import 'report.dart';
import 'screen_protection.dart';
import 'strings.dart';

/// Takes a phrase the user types or pastes, validates it, and hands it back as [MnemonicWords].
///
/// The field has autocorrect and suggestions off, the screen protection is active while the
/// words are on screen, and a paste empties the clipboard afterwards so the phrase does not
/// stay there.
class MnemonicImportScreen extends StatefulWidget {
  const MnemonicImportScreen({
    super.key,
    required this.onImported,
    required this.screenProtection,
    this.language = Language.english,
    this.allowPaste = true,
    this.strings = const MnemonicBackupStrings(),
    this.protectionTimeout = const Duration(seconds: 15),
  });

  /// Called with the validated phrase.
  final void Function(MnemonicWords words) onImported;

  final ScreenProtection screenProtection;
  final Language language;

  /// Whether to offer a paste button.
  final bool allowPaste;

  final MnemonicBackupStrings strings;

  /// How long to wait for the screen protection before giving up. Null waits without limit.
  final Duration? protectionTimeout;

  @override
  State<MnemonicImportScreen> createState() => _MnemonicImportScreenState();
}

class _MnemonicImportScreenState extends State<MnemonicImportScreen>
    with ProtectedScreenState<MnemonicImportScreen> {
  final _controller = TextEditingController();
  String? _error;
  bool _pasting = false;

  @override
  ScreenProtection get screenProtection => widget.screenProtection;

  @override
  Duration? get protectionTimeout => widget.protectionTimeout;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    if (_pasting) {
      return;
    }
    setState(() => _pasting = true);
    try {
      await _pasteOnce();
    } finally {
      if (mounted) {
        setState(() => _pasting = false);
      }
    }
  }

  Future<void> _pasteOnce() async {
    final String? text;
    try {
      text = await readClipboardText();
    } catch (error, stack) {
      reportBackupFlowError(
        error,
        stack,
        'while reading the clipboard for a paste',
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(widget.strings.pasteFailed)));
      }
      return;
    }
    if (text == null || text.isEmpty) {
      return;
    }
    if (mounted) {
      final pasted = text;
      setState(() {
        _controller.text = pasted;
        _error = null;
      });
    }
    // Read into the app, the phrase must not stay on the clipboard, whether or not the screen is
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
  }

  void _submit() {
    final strings = widget.strings;
    try {
      final words = MnemonicWords.parse(
        _controller.text,
        language: widget.language,
      );
      widget.onImported(words);
    } on MnemonicFormatException catch (exception) {
      setState(() {
        _error = switch (exception.problem) {
          MnemonicFormatProblem.wordCount => strings.importWrongCount(
            exception.wordCount ?? 0,
          ),
          MnemonicFormatProblem.unknownWord => strings.importUnknownWord(
            exception.word ?? '',
          ),
          MnemonicFormatProblem.checksum => strings.importInvalid,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(strings.importTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                strings.importInstruction,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              if (protectionActive)
                TextField(
                  controller: _controller,
                  minLines: 3,
                  maxLines: 6,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) {
                    if (_error != null) {
                      setState(() => _error = null);
                    }
                  },
                  decoration: InputDecoration(
                    hintText: strings.importHint,
                    border: const OutlineInputBorder(),
                    errorText: _error,
                    errorMaxLines: 3,
                  ),
                )
              else
                Text(
                  protectionPlaceholder(strings),
                  style: theme.textTheme.bodyLarge,
                ),
              const SizedBox(height: 8),
              if (widget.allowPaste)
                TextButton.icon(
                  onPressed: protectionActive && !_pasting ? _paste : null,
                  icon: const Icon(Icons.content_paste),
                  label: Text(strings.importPaste),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: protectionActive ? _submit : null,
                child: Text(strings.importConfirm),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
