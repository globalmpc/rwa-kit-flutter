import 'package:bip39_mnemonic/bip39_mnemonic.dart' show Language;

import 'flow_builder.dart';
import 'material_import.dart';
import 'mnemonic_words.dart';
import 'reveal_screen.dart';
import 'screen_protection.dart';
import 'strings.dart';
import 'verify_screen.dart';

/// How a backup flow ended.
enum MnemonicBackupResult {
  /// The `authenticate` callback of [showMnemonicBackupFlow] returned false; nothing was shown.
  notAuthenticated,

  /// The user left before the backup was verified, from either screen.
  abandoned,

  /// The user saw the phrase, then picked the right word at every position asked. Wrong answers
  /// can be retried without limit, so this does not prove the phrase was written down.
  verified,
}

/// Runs the whole backup: authenticate, reveal, verify.
///
/// [authenticate] is the app's PIN or biometric check. The phrase is not rendered, and no route
/// is pushed, until it returns true. The reveal step then keeps the words covered until the user
/// asks to see them, unless [obscureUntilShown] is false. The reveal and verify steps are shown
/// in one full-screen dialog route on the navigator of [context], which holds [screenProtection]
/// once: switched on before the first step renders and off after the route is gone, so the two
/// steps never hold the plugin twice and it is never off between them. [protectionTimeout] is
/// how long that route waits for the protection; null waits without limit. [language] is the
/// word list the verify step draws its decoys from; null, the default, uses the phrase's own.
/// Throws [ArgumentError] for a [challengeCount] outside 1 to the number of words, before
/// [authenticate] is called.
///
/// For a look of your own with the same rules, show [MnemonicBackupFlowBuilder] on a route of
/// your own after the same authentication.
Future<MnemonicBackupResult> showMnemonicBackupFlow(
  BuildContext context, {
  required MnemonicWords words,
  required Future<bool> Function(BuildContext context) authenticate,
  required ScreenProtection screenProtection,
  MnemonicBackupStrings strings = const MnemonicBackupStrings(),
  int challengeCount = 3,
  Language? language,
  bool allowCopy = false,
  bool obscureUntilShown = true,
  Duration? protectionTimeout = const Duration(seconds: 15),
}) async {
  // Checked before the user is asked to authenticate, not after the words have been shown.
  if (challengeCount < 1 || challengeCount > words.length) {
    throw ArgumentError.value(
      challengeCount,
      'challengeCount',
      'must be between 1 and ${words.length}',
    );
  }
  final navigator = Navigator.of(context);
  if (!await authenticate(context)) {
    return MnemonicBackupResult.notAuthenticated;
  }
  final verified = await navigator.push<bool>(
    MaterialPageRoute<bool>(
      fullscreenDialog: true,
      builder: (context) => MnemonicBackupFlowBuilder(
        words: words,
        screenProtection: screenProtection,
        challengeCount: challengeCount,
        language: language,
        allowCopy: allowCopy,
        obscureUntilShown: obscureUntilShown,
        protectionTimeout: protectionTimeout,
        onVerified: () => Navigator.of(context).pop(true),
        waitingBuilder: (context, phase) => Scaffold(
          appBar: AppBar(title: Text(strings.revealTitle)),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                strings.placeholder(phase) ?? '',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ),
        revealBuilder: (context, state) =>
            materialRevealView(context, state, strings),
        verifyBuilder: (context, state) =>
            materialVerifyView(context, state, strings),
      ),
    ),
  );
  return verified == true
      ? MnemonicBackupResult.verified
      : MnemonicBackupResult.abandoned;
}
