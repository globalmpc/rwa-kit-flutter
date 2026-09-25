# mnemonic_backup_flow

Recovery-phrase reveal, verification and import screens for Flutter wallets.

Every wallet team builds these screens, and the same faults come back: the phrase shown before the PIN is asked, no screenshot protection, a checkbox that "confirms" a backup nobody wrote down, the phrase left on the clipboard, and the phrase sitting in the app switcher snapshot. This package is the flow with those faults designed out. It has no native code and depends only on [`bip39_mnemonic`](https://pub.dev/packages/bip39_mnemonic) for word lists and checksums.

```sh
flutter pub add mnemonic_backup_flow
```

## The whole backup in one call

```dart
import 'package:mnemonic_backup_flow/mnemonic_backup_flow.dart';

final words = MnemonicWords.generate(wordCount: 12);

final result = await showMnemonicBackupFlow(
  context,
  words: words,
  authenticate: (context) => myPinOrBiometricCheck(context), // Future<bool>
  screenProtection: myScreenProtection, // see below
);

switch (result) {
  case MnemonicBackupResult.verified:      // saw the words, answered every challenge
  case MnemonicBackupResult.abandoned:     // left before confirming
  case MnemonicBackupResult.notAuthenticated: // authenticate returned false; nothing was shown
}
```

What the flow guarantees:

1. **Nothing is rendered until `authenticate` returns true.** No route is pushed either.
2. **The words appear only after `screenProtection.protect()` completes.** Until then the screen shows a placeholder, so there is no unprotected first frame. If `protect()` throws or does not answer within `protectionTimeout` (15 seconds by default, per screen), the error is reported through `FlutterError.reportError` and the screen says so; a protect that answers later still makes the screen active.
3. **The words are hidden whenever the app is not in the foreground**, so the app switcher snapshot and a notification pull-down do not carry them.
4. **Verification asks for words at distinct random positions**, multiple choice with decoys from the word list, positions chosen with `Random.secure()`.
5. **`release()` is called when the screen goes away**, including when the user backs out, after its `protect()` has settled or `protectionTimeout` later, whichever comes first, so a screen left early cannot leave the protection switched on, whether by a protect that finished later (it is released again when it answers) or by one whose reply was lost.

## Screen protection

The package cannot block screenshots by itself; that needs platform code, and your app most likely already has a plugin for it. Wrap it:

```dart
// with no_screenshot
final screenProtection = ScreenProtection.callbacks(
  protect: () => NoScreenshot.instance.screenshotOff(),
  release: () => NoScreenshot.instance.screenshotOn(),
);

// with screen_protector
final screenProtection = ScreenProtection.callbacks(
  protect: () => ScreenProtector.protectDataLeakageOn(),
  release: () => ScreenProtector.protectDataLeakageOff(),
);
```

**Each screen protects on entry and releases on exit, on its own.** If your app pushes a second protected screen while the first is still animating out, the first screen's `release()` runs when it is disposed, after the second screen's `protect()`, and a plugin that treats the two as one switch ends up off. Two ways to avoid that: do not overlap two protected screens (the flow in this package never does), or turn the plugin on around your own route stack and pass `ScreenProtection.none()` to the screens.

`ScreenProtection.none()` exists so that a demo can run without a plugin. It is a typed, deliberate opt-out; a release build should never pass it.

**What the platforms can do.** Android can refuse screenshots and recordings outright (`FLAG_SECURE`). iOS cannot: plugins there detect a screenshot or a recording and cover the content, and the first frame of a recording may still be captured. Write your app's copy accordingly rather than promising more than iOS allows.

## Using the screens on their own

Each screen is a plain widget you can push yourself. If you do, gate the reveal the way the flow does.

```dart
MnemonicRevealScreen(
  words: words,
  screenProtection: screenProtection,
  onConfirmed: () => Navigator.of(context).pop(true),
  allowCopy: false,                              // default; the clipboard is readable by other apps
  clipboardClearAfter: const Duration(seconds: 30), // if copying is allowed
)

MnemonicVerifyScreen(
  words: words,
  challengeCount: 3,
  choiceCount: 4,
  onVerified: () => Navigator.of(context).pop(true),
  onWrongAnswer: (position) => analytics.backupRetry(position), // optional
)

MnemonicImportScreen(
  screenProtection: screenProtection,
  onImported: (words) => Navigator.of(context).pop(words),
)
```

The import screen turns autocorrect and suggestions off, accepts any whitespace between words, ignores letter case, empties the clipboard after a paste, and reports three problems separately: a wrong word count (with the count), a word that is not in the list (with the word), and a checksum mismatch.

## Text and languages

Every string has an English default and can be replaced through `MnemonicBackupStrings`. Texts that carry a number or a word are functions:

```dart
const strings = MnemonicBackupStrings(
  revealTitle: 'Deine Wiederherstellungsphrase',
  verifyPrompt: (position) => 'Wähle Wort Nr. $position',
);
```

Word lists follow `bip39_mnemonic`: pass `language: Language.spanish` (or any other it supports) to `MnemonicWords.generate`, `MnemonicWords.parse` and `MnemonicVerifyScreen`.

## Handling the phrase in code

`MnemonicWords` is the only type that carries a phrase. Its `toString()` is `MnemonicWords(12 words)`, so interpolating it into a log line, an assertion message or an error does not leak the words; the words are reachable only through `.words` and `.sentence`. `MnemonicFormatException` and `VerificationChallenge` behave the same way.

```dart
final words = MnemonicWords.parse(userInput);         // throws MnemonicFormatException
final same = MnemonicWords.fromList(['abandon', ...]); // same validation, no splitting
words.length;    // 12
words.sentence;  // the phrase, one space between words
```

`MnemonicWords.generate` draws entropy from `Random.secure()` through `bip39_mnemonic` and supports 12, 15, 18, 21 and 24 words.

## API

| Name | Purpose |
|---|---|
| `showMnemonicBackupFlow(context, words:, authenticate:, screenProtection:, strings?, challengeCount?, allowCopy?, protectionTimeout?)` | Authenticate, reveal, verify. Returns `MnemonicBackupResult`. |
| `MnemonicRevealScreen` | Numbered words behind the screen protection, hidden while not in the foreground, optional copy with timed clearing. |
| `MnemonicVerifyScreen` | Distinct-position multiple-choice check; retry after a wrong answer. |
| `MnemonicImportScreen` | Typed or pasted phrase, validated, clipboard emptied after paste. |
| `MnemonicWords` | Generate, parse, hold a phrase; redacted `toString`. |
| `MnemonicFormatException` | `problem` is `wordCount`, `unknownWord` or `checksum`; `wordCount` and `word` carry the detail. |
| `generateChallenges(words, wordList:, count?, choiceCount?, random?)` | The verification questions, for a custom verify UI. |
| `ScreenProtection` | `none()`, `callbacks(protect:, release:)`, or your own subclass. |
| `SensitiveClipboard` | Copy with timed clearing, the timer starting when the write has landed, that never removes text the user copied later and remembers a copied text until a look proves it gone. A clipboard without text means the copy is gone, except on Android with the app out of the foreground, where the clipboard is hidden: then it looks three times, five seconds apart, then wipes without looking, and only text it knows it placed. `clear()` and dispose remove the text at once, wiping without looking when the clipboard is hidden or unreadable, and a failed wipe is retried. Text the platform holds but will not show (iOS 16 and later ask the user before another app's text is read) is not ours and is left alone. Every platform call is bounded; a write that lands after its bound is removed at once, and `copy()` after `dispose()` throws. |
| `MnemonicBackupStrings` | All user-facing text. |

## What it does not do

- Store or check a PIN, or call biometrics. `authenticate` is yours: the package only refuses to show anything until it says yes.
- Block screenshots on its own. It calls your `ScreenProtection` at the right moments; the platform work is the plugin's.
- Derive keys, encrypt, or store the phrase. It hands `MnemonicWords` back and keeps nothing.
- Lock the user out after wrong answers. `onWrongAnswer` lets the app apply its own policy.
- Read the words aloud differently for accessibility. Screen readers announce the words like any text, which is what a user who relies on one needs.

## Development

```sh
cd packages/mnemonic_backup_flow
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
flutter pub publish --dry-run
```

Tests cover the parser, the challenge generator, the clipboard, every screen and the whole flow, using a fake clipboard and a recording screen protection. The only fixed phrase in the repository is the BIP39 specification's all-zero test vector.

## License

MIT. See [LICENSE](LICENSE).
