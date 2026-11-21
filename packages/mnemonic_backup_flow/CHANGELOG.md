# Changelog

All notable changes to `mnemonic_backup_flow` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package follows
[Semantic Versioning](https://semver.org/).

## Unreleased

## 0.3.1 - 2026-11-20

The steps in any design system, and a full pub.dev score. Apps need no code change.

### Added

- `MnemonicBackupFlowBuilder`, `MnemonicRevealBuilder`, `MnemonicVerifyBuilder` and
  `MnemonicImportBuilder`: the rules of the flow and of each screen without their look, for
  wallets with their own design system. They need no Material ancestor or theme. Each hands its
  builder a state (`MnemonicRevealState`, `MnemonicVerifyState`, `MnemonicImportState`) whose
  secret parts, the words, the current challenge and the input, are null unless they may be
  painted, so a page that draws only what it is given never shows them at the wrong time. Every
  callback checks its condition again when it is called, so one kept from an earlier state does
  nothing, and reaches the step through a weak reference, so one kept after the step is gone does
  not keep the phrase in memory. The flow builder holds the
  screen protection once for both steps, as `showMnemonicBackupFlow` does. An app can build the
  states directly to test its own pages.
- `MnemonicSecretPhase`: `preparing`, `protectionFailed`, `hidden` or `visible`.
- `words.language`: the word list a phrase was generated in or checked against, kept with the
  phrase, also when it is made in another isolate. An extension (`MnemonicWordsLanguage`) over a
  private field, so a class that implements `MnemonicWords` keeps compiling; such a class counts
  as English, so pass `language` where a step asks for it.
- `strings.placeholder(phase)` and `strings.importError(error)`, as an extension
  (`MnemonicBackupStringsForBuilders`) so a class that implements `MnemonicBackupStrings` keeps
  compiling.
- Documentation on every public member, and tests for the example app, which now also shows the
  backup drawn in a look of its own.

### Changed

- The screens and `showMnemonicBackupFlow` are drawn on the builders, so the two cannot follow
  different rules. Their constructors and behaviour are unchanged, except that the verify
  screen's choices are disabled once every challenge has been answered (taps were ignored
  before).
- The Material import keeps a documented suppression of the Flutter 3.50 deprecation of
  `package:flutter/material.dart`. Its replacement, `package:material_ui`, is a separate copy of
  Material: a screen built on it inside an app built on `MaterialApp` would lose the app's theme.

### Fixed

- The verify step of `showMnemonicBackupFlow` draws its decoys from the phrase's own word list. They
  always came from the English list, so for a phrase in another language the one word from the
  phrase's own list gave the answer away. No code change is needed: `MnemonicWords` now remembers
  its language, and a new `language` parameter overrides it. A phrase parsed from accented text now
  holds the word list's own spelling (it looks the same), so for a phrase this package made or
  parsed, a decoy can never be a word of the phrase in another Unicode form.
- An unusable `challengeCount` for `showMnemonicBackupFlow` is reported before the user is asked
  to authenticate, not after the user has confirmed the phrase.

## 0.3.0 - 2026-11-09

Upgrading from 0.2.0: apps need no code change. The reveal step keeps the words covered until the
user taps Show the words, and covers them again when the app leaves the foreground. The button
that leaves the reveal step says Continue, and it stays disabled until the words have been on
screen. Pass `obscureUntilShown: false` to show the words as soon as the protection is active,
which is what 0.2.0 did. Set `revealConfirm` to `I wrote it down` to keep the previous label.

### Added

- `obscureUntilShown` on `MnemonicRevealScreen` and `showMnemonicBackupFlow`. True by default.
- `MnemonicBackupStrings.revealCovered` and `revealShow`, so the cover can be translated.
- A README figure of the same backup without the package and with it. The words in it are an
  example, not a recovery phrase.

### Changed

- The default `revealConfirm` is Continue. The reveal step is not the check; the word quiz is.

### Fixed

- Leaving the foreground covers the words again even when the app returns before the background
  frame is built. The cover flag is cleared on the lifecycle notification, not after that frame.

## 0.2.0 - 2026-10-17

Upgrading from 0.1.0: apps that use `showMnemonicBackupFlow` need no code change. Apps that push
`MnemonicVerifyScreen` themselves now pass a `screenProtection`. With a screenshot plugin that is a
single on/off switch, the safe choice is to hold the plugin around the app's own route stack, wait
for its `protect()` to complete, and pass `ScreenProtection.none()` to every screen: a screen's
release happens after it has gone and can switch such a plugin off for the next protected screen.
The README's "Screen protection" section has the details.

### Changed

- `MnemonicVerifyScreen` takes `screenProtection` and `protectionTimeout`, shows its choices,
  which contain a real word of the phrase, only once the protection is active, and hides them
  while the app is not in the foreground, as the reveal screen does. Breaking for apps that push
  the verify screen themselves: pass a `ScreenProtection`, as the upgrade note above describes.
- `MnemonicImportScreen` hides its field while the app is not in the foreground, keeping what
  was typed.
- `ScreenProtection.none()` makes a screen active from its first frame, with nothing to release,
  whether or not it is created with `const`.
- A verify screen with an unusable `challengeCount` or `choiceCount` fails when it is created,
  before the protection is switched on, instead of on its first build.
- README: a diagram of the three screens and the import screen, above the install line.

### Fixed

- `showMnemonicBackupFlow` hosts the reveal and verify steps in one route with one hold on the
  protection, switched on before the first step renders and off after the route is gone. In
  0.1.0 the verify route was pushed while the reveal route was still animating out, so the reveal
  screen's release turned a plugin that is a single switch off during verification.
- A double tap on the last correct answer called `onVerified` twice when the callback did not
  leave the screen at once. Taps after verification are ignored.
- README: states what `verified` proves (the right word picked at every position asked, retries
  allowed, not a written-down phrase), that a screen given the app's protection never shows the
  words before `protect()` completes however late it answers, and when the release of a screen or
  of the flow's route, which happens after it has gone, can switch a single-switch plugin off for
  the protected screen showing next.

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
