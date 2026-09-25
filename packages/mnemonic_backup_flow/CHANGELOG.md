# Changelog

All notable changes to `mnemonic_backup_flow` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package follows
[Semantic Versioning](https://semver.org/).

## 0.1.0 - 2026-09-24

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
