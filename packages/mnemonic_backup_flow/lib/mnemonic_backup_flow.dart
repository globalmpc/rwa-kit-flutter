/// Recovery-phrase reveal, verification and import screens for Flutter wallets.
///
/// Start with [showMnemonicBackupFlow] for the whole backup, or use
/// [MnemonicRevealScreen], [MnemonicVerifyScreen] and [MnemonicImportScreen] on their own.
/// Every screen takes a [ScreenProtection], which the app implements with the screenshot plugin
/// it already uses, and a [MnemonicBackupStrings] for translated text.
library;

export 'package:bip39_mnemonic/bip39_mnemonic.dart' show Language;

export 'src/challenge.dart' show VerificationChallenge, generateChallenges;
export 'src/flow.dart' show MnemonicBackupResult, showMnemonicBackupFlow;
export 'src/import_screen.dart' show MnemonicImportScreen;
export 'src/mnemonic_words.dart'
    show MnemonicFormatException, MnemonicFormatProblem, MnemonicWords;
export 'src/reveal_screen.dart' show MnemonicRevealScreen;
export 'src/screen_protection.dart' show ScreenProtection;
export 'src/sensitive_clipboard.dart' show SensitiveClipboard;
export 'src/strings.dart' show MnemonicBackupStrings;
export 'src/verify_screen.dart' show MnemonicVerifyScreen;
