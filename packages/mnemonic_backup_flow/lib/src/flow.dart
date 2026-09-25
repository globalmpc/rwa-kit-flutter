import 'package:flutter/material.dart';

import 'mnemonic_words.dart';
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
/// is pushed, until it returns true. Both screens are pushed as full-screen dialogs on the
/// navigator of [context]. [protectionTimeout] is how long the reveal screen waits for the
/// screen protection; null waits without limit.
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
  final wroteDown = await navigator.push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (context) => MnemonicRevealScreen(
        words: words,
        screenProtection: screenProtection,
        strings: strings,
        allowCopy: allowCopy,
        protectionTimeout: protectionTimeout,
        onConfirmed: () => Navigator.of(context).pop(true),
      ),
    ),
  );
  if (wroteDown != true) {
    return MnemonicBackupResult.abandoned;
  }
  final verified = await navigator.push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (context) => MnemonicVerifyScreen(
        words: words,
        strings: strings,
        challengeCount: challengeCount,
        onVerified: () => Navigator.of(context).pop(true),
      ),
    ),
  );
  return verified == true
      ? MnemonicBackupResult.verified
      : MnemonicBackupResult.abandoned;
}
