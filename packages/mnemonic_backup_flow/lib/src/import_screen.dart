import 'package:bip39_mnemonic/bip39_mnemonic.dart' show Language;

import 'import_builder.dart';
import 'material_import.dart';
import 'mnemonic_words.dart';
import 'screen_protection.dart';
import 'strings.dart';

/// Takes a phrase the user types or pastes, validates it, and hands it back as [MnemonicWords].
///
/// The field has autocorrect and suggestions off, the screen protection is active while the
/// words are on screen, the field is hidden while the app is not in the foreground, and a paste
/// empties the clipboard afterwards so the phrase does not stay there. For a look of your own with
/// the same rules, use [MnemonicImportBuilder].
class MnemonicImportScreen extends StatefulWidget {
  /// The import screen, in Material.
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

  /// Switched on before the field is shown, and off when the screen goes away.
  final ScreenProtection screenProtection;

  /// The word list the phrase is checked against.
  final Language language;

  /// Whether to offer a paste button.
  final bool allowPaste;

  /// The texts of the screen.
  final MnemonicBackupStrings strings;

  /// How long to wait for the screen protection before giving up. Null waits without limit.
  final Duration? protectionTimeout;

  @override
  State<MnemonicImportScreen> createState() => _MnemonicImportScreenState();
}

// A State only so the widget's public type stays what earlier versions shipped; the rules live in
// MnemonicImportBuilder.
class _MnemonicImportScreenState extends State<MnemonicImportScreen> {
  @override
  Widget build(BuildContext context) => MnemonicImportBuilder(
    onImported: widget.onImported,
    screenProtection: widget.screenProtection,
    language: widget.language,
    allowPaste: widget.allowPaste,
    protectionTimeout: widget.protectionTimeout,
    builder: (context, state) => _view(context, state, widget.strings),
  );
}

Widget _view(
  BuildContext context,
  MnemonicImportState state,
  MnemonicBackupStrings strings,
) {
  final theme = Theme.of(context);
  final controller = state.controller;
  final error = state.error;
  final onSubmit = state.onSubmit;
  final onPaste = state.onPaste;
  return Scaffold(
    appBar: AppBar(title: Text(strings.importTitle)),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.importInstruction, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),
            if (controller != null)
              TextField(
                controller: controller,
                minLines: 3,
                maxLines: 6,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmit?.call(),
                decoration: InputDecoration(
                  hintText: strings.importHint,
                  border: const OutlineInputBorder(),
                  errorText: error == null ? null : strings.importError(error),
                  errorMaxLines: 3,
                ),
              )
            else
              Text(
                strings.placeholder(state.phase) ?? '',
                style: theme.textTheme.bodyLarge,
              ),
            const SizedBox(height: 8),
            if (state.allowPaste)
              TextButton.icon(
                onPressed: onPaste == null
                    ? null
                    : () => _paste(context, onPaste, strings),
                icon: const Icon(Icons.content_paste),
                label: Text(strings.importPaste),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: onSubmit,
              child: Text(strings.importConfirm),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _paste(
  BuildContext context,
  Future<bool> Function() paste,
  MnemonicBackupStrings strings,
) async {
  if (await paste() || !context.mounted) {
    return;
  }
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(strings.pasteFailed)));
}
