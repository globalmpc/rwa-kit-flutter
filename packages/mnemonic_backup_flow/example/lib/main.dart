import 'package:flutter/material.dart';
import 'package:mnemonic_backup_flow/mnemonic_backup_flow.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'mnemonic_backup_flow example',
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _status = 'No phrase yet.';

  // A real app wraps the screenshot plugin it already uses, for example:
  //   ScreenProtection.callbacks(
  //     protect: () => NoScreenshot.instance.screenshotOff(),
  //     release: () => NoScreenshot.instance.screenshotOn(),
  //   )
  // ScreenProtection.none() leaves the phrase visible to screenshots and belongs in a demo only.
  static const _screenProtection = ScreenProtection.none();

  Future<void> _backUpNewPhrase() async {
    final words = MnemonicWords.generate(wordCount: 12);
    final result = await showMnemonicBackupFlow(
      context,
      words: words,
      screenProtection: _screenProtection,
      authenticate: _askDemoPin,
    );
    if (!mounted) {
      return;
    }
    setState(
      () => _status = 'Backup of a ${words.length}-word phrase: ${result.name}',
    );
  }

  /// The same backup drawn with plain widgets, the way a wallet with its own design system draws
  /// it: MnemonicBackupFlowBuilder keeps every rule and hands over what to draw.
  Future<void> _backUpInYourOwnLook() async {
    final words = MnemonicWords.generate(wordCount: 12);
    if (!await _askDemoPin(context) || !mounted) {
      return;
    }
    final verified = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        pageBuilder: (context, _, _) => MnemonicBackupFlowBuilder(
          words: words,
          screenProtection: _screenProtection,
          onVerified: () => Navigator.of(context).pop(true),
          waitingBuilder: (context, phase) => _PlainPage(
            children: [
              _PlainText(_strings.placeholder(phase)!),
              _CancelButton(context),
            ],
          ),
          revealBuilder: (context, state) => _PlainPage(
            children: [
              _PlainText(_strings.revealWarning),
              if (state.words case final shown?)
                for (final (index, word) in shown.indexed)
                  _PlainText('${index + 1}. $word')
              else if (state.covered)
                _PlainButton(_strings.revealShow, onTap: state.onShow)
              else
                _PlainText(_strings.placeholder(state.phase)!),
              _PlainButton(_strings.revealConfirm, onTap: state.onConfirmed),
              _CancelButton(context),
            ],
          ),
          verifyBuilder: (context, state) => _PlainPage(
            children: [
              _PlainText(_strings.verifyProgress(state.step, state.stepCount)),
              if (state.challenge case final challenge?) ...[
                _PlainText(_strings.verifyPrompt(challenge.position)),
                for (final choice in challenge.choices)
                  _PlainButton(
                    choice,
                    onTap: state.onAnswer == null
                        ? null
                        : () => state.onAnswer!(choice),
                  ),
                if (state.wrong)
                  _PlainText(_strings.verifyWrong(challenge.position)),
              ] else
                _PlainText(_strings.placeholder(state.phase)!),
              _CancelButton(context),
            ],
          ),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(
      () => _status =
          'Own-look backup: ${verified == true ? 'verified' : 'abandoned'}',
    );
  }

  static const _strings = MnemonicBackupStrings();

  Future<void> _importPhrase() async {
    final words = await Navigator.of(context).push<MnemonicWords>(
      MaterialPageRoute<MnemonicWords>(
        fullscreenDialog: true,
        builder: (context) => MnemonicImportScreen(
          screenProtection: _screenProtection,
          onImported: (words) => Navigator.of(context).pop(words),
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(
      () => _status = words == null
          ? 'Import cancelled.'
          : 'Imported a ${words.length}-word phrase.',
    );
  }

  /// Stands in for the app's PIN or biometric check. Any four digits pass here; a real check
  /// compares against a stored hash or calls local_auth.
  Future<bool> _askDemoPin(BuildContext context) async {
    final entered = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Enter your PIN (demo)'),
          content: TextField(
            controller: controller,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 4,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Unlock'),
            ),
          ],
        );
      },
    );
    return entered != null && RegExp(r'^\d{4}$').hasMatch(entered);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('mnemonic_backup_flow')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _backUpNewPhrase,
              child: const Text('Back up a new phrase'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _importPhrase,
              child: const Text('Import a phrase'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _backUpInYourOwnLook,
              child: const Text('Back up in your own look'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A page in a plain look of its own: dark, no Material widgets.
class _PlainPage extends StatelessWidget {
  const _PlainPage({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF101418),
    // A text style of its own: with no Material page above, text would otherwise take the
    // framework's fallback style.
    child: DefaultTextStyle(
      style: const TextStyle(
        color: Color(0xFFE6EDF3),
        fontSize: 16,
        decoration: TextDecoration.none,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ),
  );
}

class _PlainText extends StatelessWidget {
  const _PlainText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 16),
    ),
  );
}

/// A button drawn from scratch, disabled while [onTap] is null.
class _PlainButton extends StatelessWidget {
  const _PlainButton(this.label, {required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    child: GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF6E8BFF)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF6E8BFF), fontSize: 16),
          ),
        ),
      ),
    ),
  );
}

/// A plain route has no back button and no swipe-back on iOS, so every page offers a way out:
/// leaving the route is what releases the screen protection.
class _CancelButton extends StatelessWidget {
  const _CancelButton(this.routeContext);

  final BuildContext routeContext;

  @override
  Widget build(BuildContext context) => _PlainButton(
    'Cancel',
    onTap: () => Navigator.of(routeContext).pop(false),
  );
}
