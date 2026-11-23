/// Recovery-phrase reveal, verification and import screens for Flutter wallets.
///
/// Start with [showMnemonicBackupFlow] for the whole backup, or use
/// [MnemonicRevealScreen], [MnemonicVerifyScreen] and [MnemonicImportScreen] on their own.
/// Every screen takes a [ScreenProtection], which the app implements with the screenshot plugin
/// it already uses, and a [MnemonicBackupStrings] for translated text.
///
/// Drawing the steps in your own design system? [MnemonicBackupFlowBuilder],
/// [MnemonicRevealBuilder], [MnemonicVerifyBuilder] and [MnemonicImportBuilder] keep the same
/// rules and hand you the state to draw.
library;

export 'package:bip39_mnemonic/bip39_mnemonic.dart' show Language;

export 'src/challenge.dart' show VerificationChallenge, generateChallenges;
export 'src/flow.dart' show MnemonicBackupResult, showMnemonicBackupFlow;
export 'src/flow_builder.dart' show MnemonicBackupFlowBuilder;
export 'src/import_builder.dart'
    show MnemonicImportBuilder, MnemonicImportState;
export 'src/import_screen.dart' show MnemonicImportScreen;
export 'src/mnemonic_words.dart'
    show
        MnemonicFormatException,
        MnemonicFormatProblem,
        MnemonicWords,
        MnemonicWordsLanguage;
export 'src/reveal_builder.dart'
    show MnemonicRevealBuilder, MnemonicRevealState;
export 'src/reveal_screen.dart' show MnemonicRevealScreen;
export 'src/screen_protection.dart' show ScreenProtection;
export 'src/secret_phase.dart' show MnemonicSecretPhase;
export 'src/sensitive_clipboard.dart' show SensitiveClipboard;
export 'src/strings.dart'
    show MnemonicBackupStrings, MnemonicBackupStringsForBuilders;
export 'src/verify_builder.dart'
    show MnemonicVerifyBuilder, MnemonicVerifyState;
export 'src/verify_screen.dart' show MnemonicVerifyScreen;
