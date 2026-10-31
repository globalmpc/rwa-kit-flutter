# rwa-kit-flutter

Open-source Flutter packages for wallet and real-world-asset (RWA) apps, published on pub.dev by Global MPC. One repository, one folder per package. The packages are built for wallets on **BNB Smart Chain (BSC)** and other EVM networks.

## Technology Stack

- **Blockchain:** BNB Smart Chain and other EVM-compatible chains, through BIP39 recovery phrases and EVM addresses. The packages make no RPC calls and send no transactions.
- **Language:** Dart 3.8+, Flutter 3.32+.
- **Development:** CI runs `dart format`, `flutter analyze --fatal-infos`, `flutter test` and `flutter pub publish --dry-run` on every package.
- **Dependencies:** `bip39_mnemonic` (word lists and checksums), used by `mnemonic_backup_flow`, and `pointycastle` (keccak-256 for EIP-55 checksums), used by `address_guard`.

## Supported Networks

- **BNB Smart Chain Mainnet (Chain ID: 56)**, **BNB Smart Chain Testnet (Chain ID: 97)** and other EVM networks. The screens handle the BIP39 phrase a wallet derives its keys from, and EVM addresses are the same format on every EVM chain, so no RPC endpoint is configured in the packages. `address_guard` takes the chain ID from the app and binds each confirmation to it.

## Packages

| Package | What it does | pub.dev |
|---|---|---|
| [`mnemonic_backup_flow`](packages/mnemonic_backup_flow) | Recovery-phrase reveal, verification and import screens for wallets: PIN gate, screenshot-protection hooks, random-word checks, clipboard clearing, 12 to 24 words, translatable text. No native code. | [![pub](https://img.shields.io/pub/v/mnemonic_backup_flow)](https://pub.dev/packages/mnemonic_backup_flow) |
| [`address_guard`](packages/address_guard) | Catches address-poisoning look-alikes before a wallet sends: compares a recipient with the addresses the user has really paid, from the transactions they signed, checks the EIP-55 checksum, and shows the full address on a confirm card with the differing characters highlighted. No native code, no network calls. | [![pub](https://img.shields.io/pub/v/address_guard)](https://pub.dev/packages/address_guard) |

## Layout

```
packages/<package>/      one pub.dev package: pubspec.yaml, lib/, test/, example/, README, CHANGELOG, LICENSE
analysis_options.yaml    analyzer strictness, included by every package
.github/workflows/       ci.yml checks every package; release.yml publishes one package per tag
```

## Releases

A release is a tag on the public repository in the form `<package>-v<version>`. The workflow verifies the tag against `pubspec.yaml`, publishes to pub.dev with a short-lived GitHub token (no stored credential), and creates a GitHub Release.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues: [SECURITY.md](SECURITY.md).
