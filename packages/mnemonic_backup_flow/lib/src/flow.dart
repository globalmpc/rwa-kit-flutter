import 'package:flutter/material.dart';

import 'mnemonic_words.dart';
import 'protected_screen.dart';
import 'reveal_screen.dart';
import 'screen_protection.dart';
import 'strings.dart';
import 'verify_screen.dart';

/// How a backup flow ended.
enum MnemonicBackupResult {
  /// [authenticate] returned false; nothing was shown.
  notAuthenticated,

  /// The user left before the backup was verified, from either screen.
  abandoned,

  /// The user saw the phrase and answered every challenge.
  verified,
}

/// Runs the whole backup: authenticate, reveal, verify.
///
/// [authenticate] is the app's PIN or biometric check. The phrase is not rendered, and no route
/// is pushed, until it returns true. The reveal and verify steps are shown in one full-screen
/// dialog route on the navigator of [context], which holds [screenProtection] once: switched on
/// before the first step renders and off after the route is gone, so the two steps never hold the
/// plugin twice and it is never off between them. [protectionTimeout] is how long that route
/// waits for the protection; null waits without limit.
Future<MnemonicBackupResult> showMnemonicBackupFlow(
  BuildContext context, {
  required MnemonicWords words,
  required Future<bool> Function(BuildContext context) authenticate,
  required ScreenProtection screenProtection,
  MnemonicBackupStrings strings = const MnemonicBackupStrings(),
  int challengeCount = 3,
  bool allowCopy = false,
  Duration? protectionTimeout = const Duration(seconds: 15),
}) async {
  final navigator = Navigator.of(context);
  if (!await authenticate(context)) {
    return MnemonicBackupResult.notAuthenticated;
  }
  final verified = await navigator.push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (context) => _BackupFlow(
        words: words,
        screenProtection: screenProtection,
        strings: strings,
        challengeCount: challengeCount,
        allowCopy: allowCopy,
        protectionTimeout: protectionTimeout,
      ),
    ),
  );
  return verified == true
      ? MnemonicBackupResult.verified
      : MnemonicBackupResult.abandoned;
}

/// The reveal step, then the verify step, behind one hold on the app's protection. The steps
/// are given [ScreenProtection.none], since this route already holds the real one; they render
/// only once it is active, so their own placeholder never shows an unprotected frame.
class _BackupFlow extends StatefulWidget {
  const _BackupFlow({
    required this.words,
    required this.screenProtection,
    required this.strings,
    required this.challengeCount,
    required this.allowCopy,
    required this.protectionTimeout,
  });

  final MnemonicWords words;
  final ScreenProtection screenProtection;
  final MnemonicBackupStrings strings;
  final int challengeCount;
  final bool allowCopy;
  final Duration? protectionTimeout;

  @override
  State<_BackupFlow> createState() => _BackupFlowState();
}

class _BackupFlowState extends State<_BackupFlow>
    with ProtectedScreenState<_BackupFlow> {
  bool _wroteDown = false;

  @override
  ScreenProtection get screenProtection => widget.screenProtection;

  @override
  Duration? get protectionTimeout => widget.protectionTimeout;

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    if (!protectionActive) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.revealTitle)),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              protectionPlaceholder(strings),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }
    if (!_wroteDown) {
      return MnemonicRevealScreen(
        words: widget.words,
        screenProtection: const ScreenProtection.none(),
        strings: strings,
        allowCopy: widget.allowCopy,
        onConfirmed: () => setState(() => _wroteDown = true),
      );
    }
    return MnemonicVerifyScreen(
      words: widget.words,
      screenProtection: const ScreenProtection.none(),
      strings: strings,
      challengeCount: widget.challengeCount,
      onVerified: () => Navigator.of(context).pop(true),
    );
  }
}
