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
          ],
        ),
      ),
    );
  }
}
