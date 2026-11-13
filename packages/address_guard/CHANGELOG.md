# Changelog

All notable changes to `address_guard` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package follows
[Semantic Versioning](https://semver.org/).

## Unreleased

## 0.2.0 - 2026-11-12

Matches look-alikes the way attackers make them, and marks the planted transfers in the
account's history. Based on the USENIX Security 2025 measurement of 270 million poisoning
transfers ([Tsuchiya et al.](https://www.usenix.org/system/files/usenixsecurity25-tsuchiya.pdf))
and the 2025 study of 53 wallets under address poisoning
([Guan and Li](https://arxiv.org/abs/2508.12107)).

### Added

- `screenHistory`: the entries of the account's activity list that look like poisoning, so the
  wallet can hide or mark them before the user copies an address from there. An entry is a suspect
  when its counterparty imitates a known recipient and the owner has not paid it. Each suspect names the
  addresses it imitates and its `PoisoningSign`s: `zeroValue`, `dust` (through the app's
  `isDust`), `unlistedToken` (a token missing from the app's `listedTokens`, as counterfeit tokens
  are) and `namesOwnerAsSender` (a token record that shows the owner paying the look-alike;
  never for the native coin, whose sender cannot be forged). A native send from the owner is
  never a suspect, for the same reason. It reads the untrusted data that `deriveKnownRecipients`
  refuses, and can only raise an alarm with it, never make an address known. A counterparty only
  in the address book is still flagged, since saving the copied look-alike is how the attack
  succeeds; two saved addresses that resemble each other flag each other. Entries with a malformed sender, recipient or amount are skipped; a malformed token field
  still raises the alarm, as an unlisted token. A `listedTokens` entry that is not an address
  throws, since a mistyped list would call every real token fake.
- `HistoryTransfer`, `PoisoningSuspect` and `PoisoningSign`.
- `assessRecipient(suspects: ...)`: what `screenHistory` flagged. A candidate that planted an entry
  is a `lookalike` with the new reason `RecipientReason.plantedInHistory`, and the addresses it
  imitates are on the card, even when its ends do not match the window here and even when it is
  in the address book. Only a recipient the owner has really paid still wins.
- `LookalikeMatch.sharedLength`: how many characters a look-alike shares at the ends.
- `AddressGuardStrings`: `reasonPlantedInHistory`, `historyWarning`, a sentence
  for each sign, and `sign(PoisoningSign)`.
- The example app has an activity list with the two planted entries flagged.

### Changed

- **Breaking:** the default `prefixLength` is three characters instead of four
  (`defaultPrefixLength`). Measured look-alikes start at three shared characters at the start and
  four at the end and go up to 20 in all; 0.1.0 required four at the start, so a three-and-four
  look-alike passed as a first-time recipient. The lengths were already minimums and still are.
  Pass `prefixLength: 4` to keep the 0.1.0 behaviour.
- **Breaking:** `LookalikeMatch.prefix` and `suffix` hold every shared character, not only the
  window, and the middles are what lies between them. Matches come closest copy first.
- **Breaking:** `RecipientReason` has a new value, `plantedInHistory`. A `switch` over it needs a
  case for it. A lookalike verdict still always comes with `lookalikes` to show.
- `RecipientConfirmCard` and `AddressText` set in bold everything after the first three
  characters by default (was four), the new window, for known and first-time recipients too.
- `RecipientConfirmCard` also clears a tick when the check's reasons change, such as learning that
  the address was planted, and sets in bold the characters between the ends a look-alike really
  shares, not only the minimum window.
- README: a without-and-with figure and an eight-step walkthrough, in the style of the other
  globalmpc packages, lead the page. The still hero image stays in the repository, because the
  0.1.0 page on pub.dev links to it.

## 0.1.0 - 2026-10-30

First release.

### Added

- `deriveKnownRecipients`: the recipients an account has really chosen to pay, from the transactions
  it signed. A recipient counts only from a successful transaction whose own `from` is the account
  and whose signed data names it: a native send, or a direct `transfer(address,uint256)` call, with
  a non-zero amount. Transfers into the account, token `Transfer` logs, `transferFrom`, `approve`
  and other contract calls never count, so a look-alike planted in the history cannot become a known
  recipient.
- `KnownRecipient` with `RecipientProvenance.sentByOwner` and `confirmedByUser`, for the app's
  address book.
- `assessRecipient`: one verdict of `known`, `firstTime`, `lookalike`, `invalid` or `badChecksum`,
  with the reasons in order and the look-alike evidence. An exact known match outranks resemblance;
  a look-alike outranks a checksum complaint; a known address with altered casing is `badChecksum`.
  A saved address the user has not paid is reported as `savedRecipient`, so the card never says it
  was paid. An address that is both paid and saved is reported with its address-book label. Other
  rows of a payout list can be passed as `batch`; a batch match flags a look-alike but never makes
  an address known, and a batch row that is not an address is skipped.
- `findLookalikes`: same first and last characters (four and four by default), different middle,
  compared without regard to case. A window that leaves no middle is refused.
- `RecipientConfirmCard`: the full address in groups of four with the middle in bold, every
  character that differs from the imitated address highlighted, the reasons and the network, and a
  confirm button that depends on the verdict. A look-alike or an altered address cannot be confirmed
  unless `allowOverride` is set; a first-time recipient needs the user to tick that they checked the
  full address. A change in the recipient, its verdict, what it imitates, the chain or
  `allowOverride` clears the tick, and a double tap confirms once. Screen readers hear the address
  spelled out in groups.
- `ConfirmedRecipient.matches`, to check a transaction against what the user confirmed just before
  signing.
- `AddressText`, `AddressGuardStrings` for translated text, and the EIP-55 helpers
  `toChecksumAddress`, `checksumState`, `isValidChecksum`, `isEvmAddress` and `normalizeAddress`.
  All lower case and all capitals carry no checksum (EIP-55) and are `unchecksummed`, not an error.
