# Changelog

All notable changes to `mnemonic_backup_flow` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package follows
[Semantic Versioning](https://semver.org/).

## Unreleased

### Changed

- `MnemonicVerifyScreen` takes `screenProtection` and `protectionTimeout`, shows its choices,
  which contain a real word of the phrase, only once the protection is active, and hides them
  while the app is not in the foreground, as the reveal screen does. Breaking for apps that push
  the verify screen themselves: pass the same `ScreenProtection` as to the reveal screen, and do
  not push one while the other is still animating out.
- `MnemonicImportScreen` hides its field while the app is not in the foreground, keeping what
  was typed.
- `ScreenProtection.none()` makes a screen active from its first frame, with nothing to release.
- A verify screen with an unusable `challengeCount` or `choiceCount` fails when it is created,
  before the protection is switched on, instead of on its first build.
- README: a diagram of the three screens and the import screen, above the install line.

### Fixed

- `showMnemonicBackupFlow` hosts the reveal and verify steps in one route with one hold on the
  protection, switched on before the first step renders and off after the route is gone. In
  0.1.0 the verify route was pushed while the reveal route was still animating out, so the reveal
  screen's release turned a plugin that is a single switch off during verification.

## 0.1.0 - 2026-09-25

First release.

### Added

- `showMnemonicBackupFlow`: authenticate, reveal, verify, in that order. Nothing is rendered and
  no route is pushed until the app's authentication callback returns true.
- `MnemonicRevealScreen`: numbered words shown only after the screen protection reports it is
  active, hidden while the app is inactive or in the background, no text selection, an optional
  copy button whose clipboard entry is cleared after a delay.
- `MnemonicVerifyScreen` and `generateChallenges`: distinct random positions, multiple choice
  with decoys from the word list, retry after a wrong answer, an `onWrongAnswer` hook.
- `MnemonicImportScreen`: typed or pasted phrase with autocorrect off, whitespace and case
  normalised, word count, unknown word and checksum errors named separately, clipboard emptied
  after a paste.
- `MnemonicWords`: generation from `Random.secure` entropy for 12, 15, 18, 21 or 24 words,
  validation through `bip39_mnemonic` with each word trimmed and lower-cased whether given as
  text or as a list, and a `toString` that never contains the words.
- `ScreenProtection`: the hook an app implements with its screenshot plugin, with
  `ScreenProtection.none()` as an explicit opt-out and `ScreenProtection.callbacks` for adapters.
  Each screen's release waits for its protect to settle, or `protectionTimeout` after the screen
  goes away; a protect that throws or exceeds the timeout is reported and leaves the screen on an
  explanatory placeholder, and one that answers late is released again.
- `SensitiveClipboard`: copy with timed clearing (the timer starts when the write has landed)
  that leaves later clipboard contents alone, remembers every text it may have placed until a
  look proves it gone, treats a clipboard without text as gone except on Android out of the
  foreground where it is hidden (three looks five seconds apart, then a wipe without looking,
  and only of text it knows it placed), removes at once on `clear()` and dispose, retries a
  failed look or wipe, leaves alone text the platform withholds, bounds every platform call,
  removes a write that lands late at once, and reports a failure nobody awaits.
- `MnemonicBackupStrings`: every user-facing text with English defaults, for translation.
