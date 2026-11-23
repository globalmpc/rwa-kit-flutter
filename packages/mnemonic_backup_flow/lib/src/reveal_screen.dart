import 'material_import.dart';
import 'mnemonic_words.dart';
import 'reveal_builder.dart';
import 'screen_protection.dart';
import 'strings.dart';

/// Shows the phrase, numbered, once the screen protection is active and the user has asked to
/// see it, and hides it while the app is not in the foreground so the app switcher snapshot does
/// not carry it.
///
/// Reaching this screen is the app's decision. [showMnemonicBackupFlow] only pushes it after the
/// caller's authentication returned true; if you push it yourself, gate it the same way. For a
/// look of your own with the same rules, use [MnemonicRevealBuilder].
class MnemonicRevealScreen extends StatefulWidget {
  /// The reveal screen, in Material.
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

  /// The phrase to show.
  final MnemonicWords words;

  /// Switched on before the words are shown, and off when the screen goes away.
  final ScreenProtection screenProtection;

  /// Called when the user confirms the phrase is written down.
  final VoidCallback onConfirmed;

  /// The texts of the screen.
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

// A State only so the widget's public type stays what earlier versions shipped; the rules live in
// MnemonicRevealBuilder.
class _MnemonicRevealScreenState extends State<MnemonicRevealScreen> {
  @override
  Widget build(BuildContext context) => MnemonicRevealBuilder(
    words: widget.words,
    screenProtection: widget.screenProtection,
    onConfirmed: widget.onConfirmed,
    allowCopy: widget.allowCopy,
    obscureUntilShown: widget.obscureUntilShown,
    clipboardClearAfter: widget.clipboardClearAfter,
    protectionTimeout: widget.protectionTimeout,
    builder: (context, state) =>
        materialRevealView(context, state, widget.strings),
  );
}

/// The Material look of the reveal step, shared by [MnemonicRevealScreen] and
/// [showMnemonicBackupFlow]. Not exported.
Widget materialRevealView(
  BuildContext context,
  MnemonicRevealState state,
  MnemonicBackupStrings strings,
) {
  final theme = Theme.of(context);
  final onCopy = state.onCopy;
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
            Expanded(child: _body(state, strings, theme)),
            if (state.allowCopy)
              TextButton.icon(
                onPressed: onCopy == null
                    ? null
                    : () => _copy(context, onCopy, state, strings),
                icon: const Icon(Icons.copy),
                label: Text(strings.copy),
              ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: state.onConfirmed,
              child: Text(strings.revealConfirm),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _copy(
  BuildContext context,
  Future<bool?> Function() copy,
  MnemonicRevealState state,
  MnemonicBackupStrings strings,
) async {
  final copied = await copy();
  if (copied == null || !context.mounted) {
    return;
  }
  final notice = copied
      ? strings.copiedFor(state.clipboardClearAfter.inSeconds)
      : strings.copyFailed;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notice)));
}

Widget _body(
  MnemonicRevealState state,
  MnemonicBackupStrings strings,
  ThemeData theme,
) {
  final placeholder = strings.placeholder(state.phase);
  if (placeholder != null) {
    return Center(
      child: Text(
        placeholder,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge,
      ),
    );
  }
  final words = state.words;
  if (words == null) {
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
                      onPressed: state.onShow,
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
  return _WordGrid(words: words);
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
