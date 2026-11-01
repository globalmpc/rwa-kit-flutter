# mnemonic_backup_flow

Built by [MPC (Mineral Project Coin)](https://www.globalmpc.tech) — mining real-world asset (RWA) infrastructure.

Recovery-phrase reveal, verification and import screens for Flutter wallets.

Every wallet team builds these screens, and the same faults come back: the phrase shown before the PIN is asked, no screenshot protection, a checkbox that "confirms" a backup nobody wrote down, the phrase left on the clipboard, and the phrase sitting in the app switcher snapshot. This package is the flow with those faults designed out. What it can check is what happens on screen: a `verified` result means the user picked the right word at every position asked, in the app, with the positions and decoys the package generates (or the challenges your app supplies). It does not prove the phrase was written down or kept safe, and since a wrong answer can be retried without limit, it can also be reached by trying every choice; an app that wants to limit attempts pushes `MnemonicVerifyScreen` itself and acts on `onWrongAnswer`, since the one-call flow does not limit them. It has no native code and depends only on [`bip39_mnemonic`](https://pub.dev/packages/bip39_mnemonic) for word lists and checksums.

![Diagram: authenticate, reveal, verify, plus the import screen](https://raw.githubusercontent.com/globalmpc/rwa-kit-flutter/main/packages/mnemonic_backup_flow/doc/how-it-works.svg)

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
  case MnemonicBackupResult.verified:      // saw the words, then picked the right word at every position asked (retries allowed)
  case MnemonicBackupResult.abandoned:     // left before confirming
  case MnemonicBackupResult.notAuthenticated: // authenticate returned false; nothing was shown
}
```

What the flow guarantees:

1. **Nothing is rendered until `authenticate` returns true.** No route is pushed either.
2. **The words appear only after `screenProtection.protect()` completes**, on the reveal step and on the verify step, whose choices contain a real word. Until then the screen shows a placeholder, so there is no unprotected first frame. While the screen is showing, if `protect()` throws or does not answer within `protectionTimeout` (15 seconds by default; the flow waits once for its route, a screen you push yourself waits on its own), the error is reported through `FlutterError.reportError` and the screen says so; a protect that threw leaves that screen in the failed state. A protect that only timed out and answers later still makes the screen active, and the words appear then: however late your `protect()` answers, a screen given your `ScreenProtection` never shows the words before it has completed. A screen given `ScreenProtection.none()` shows them on its first frame and relies on the protection your app already holds.
3. **The words are hidden whenever the app is not in the foreground**, on every screen, including the import field, so the app switcher snapshot and a notification pull-down do not carry them.
4. **Verification asks for words at distinct random positions**, multiple choice with decoys from the word list, positions chosen with `Random.secure()`.
5. **`release()` is called when the flow's route goes away**, including when the user backs out at either step, after its `protect()` has settled or `protectionTimeout` later, whichever comes first. A protect that settles within that time is released once; one that completes or throws after the timeout-driven release is released a second time. So a route left early cannot leave the protection switched on, even when the protect's reply is lost, provided `protectionTimeout` is not null: with `null`, the release waits for `protect()` without limit. The reveal and verify steps live in that one route with one hold on your protection, so the plugin is switched on once and is never released between the two steps. A protect that answers after the route has already been released is released once more; see the next section.

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

**Each screen protects on entry and releases on exit, on its own.** If your app pushes a second protected screen while the first is still animating out, the first screen's `release()` runs when it is disposed, after the second screen's `protect()`, and a plugin that treats the two as one switch ends up off. Two ways to avoid that: do not overlap two protected screens, or hold the plugin around your own route stack and pass `ScreenProtection.none()` to the screens; wait for your own `protect()` to complete before pushing them, since a screen given `none()` shows the words on its first frame. `showMnemonicBackupFlow` does the latter: its reveal and verify steps share one protected route.

**When a screen goes away before its `protect()` has answered.** Its `release()` waits for `protect()` to settle, but for at most `protectionTimeout` after the screen is gone (with `protectionTimeout: null` it waits without limit). If `protect()` answers after that release, it is released a second time, so the protection cannot stay switched on. Both releases happen after the screen has gone, so with a plugin that is a single on/off switch either one can switch protection off for a protected screen that is showing by then. The same holds for the flow: `showMnemonicBackupFlow` keeps its own reveal and verify steps from overlapping, but its route still releases when it goes away, after its exit animation and after `showMnemonicBackupFlow` has already returned. If your app shows another protected screen right after the flow, or pushes screens itself with a plugin that can answer slowly, hold the plugin around your own route stack and pass `ScreenProtection.none()` to the screens; wait for your own `protect()` to complete before pushing them, since a screen given `none()` shows the words on its first frame.

`ScreenProtection.none()` exists so that a demo can run without a plugin, and for screens inside a route that already holds the plugin, as the flow's steps are. It is a typed, deliberate opt-out that renders on the first frame; a release build should never pass it to a screen that is not otherwise protected.

**What the platforms can do.** Android can refuse screenshots and recordings outright (`FLAG_SECURE`). iOS cannot: plugins there detect a screenshot or a recording and cover the content, and the first frame of a recording may still be captured. Write your app's copy accordingly rather than promising more than iOS allows.

## Using the screens on their own

Each screen is a plain widget you can push yourself. If you do, gate the reveal the way the flow does, and do not let two of them overlap (see above).

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
  screenProtection: screenProtection,
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

The import screen turns autocorrect and suggestions off, accepts any whitespace between words, ignores letter case, hides the field while the app is not in the foreground, empties the clipboard after a paste, and reports three problems separately: a wrong word count (with the count), a word that is not in the list (with the word), and a checksum mismatch.

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
| `showMnemonicBackupFlow(context, words:, authenticate:, screenProtection:, strings?, challengeCount?, allowCopy?, protectionTimeout?)` | Authenticate, then reveal and verify in one protected route. Returns `MnemonicBackupResult`. |
| `MnemonicRevealScreen` | Numbered words behind the screen protection, hidden while not in the foreground, optional copy with timed clearing. |
| `MnemonicVerifyScreen` | Distinct-position multiple-choice check behind the screen protection; retry after a wrong answer. |
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
