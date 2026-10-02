# rwa-kit-flutter

Open-source Flutter packages for wallet and real-world-asset (RWA) apps, published on pub.dev by Global MPC. One repository, one folder per package.

## Packages

| Package | What it does | pub.dev |
|---|---|---|
| [`mnemonic_backup_flow`](packages/mnemonic_backup_flow) | Recovery-phrase reveal, verification and import screens for wallets: PIN gate, screenshot-protection hooks, random-word checks, clipboard clearing, 12 to 24 words, translatable text. No native code. | [![pub](https://img.shields.io/pub/v/mnemonic_backup_flow)](https://pub.dev/packages/mnemonic_backup_flow) |

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
