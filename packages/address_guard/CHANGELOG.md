# Changelog

All notable changes to `address_guard` are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package follows
[Semantic Versioning](https://semver.org/).

## Unreleased

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
