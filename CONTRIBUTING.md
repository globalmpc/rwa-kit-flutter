# Contributing

## Setup

Flutter on the stable channel, at the version pinned in `.github/workflows/ci.yml`; that pin is the one place the version is written, so a local run and CI agree. Each package resolves its own dependencies:

```sh
cd packages/<package>
flutter pub get
dart format .
flutter analyze --fatal-infos
flutter test
flutter pub publish --dry-run
```

All five must pass before a pull request. CI runs the same commands for every package.

## Layout

One package per folder under `packages/`, folder name equal to the package name. Every package carries its own `README.md`, `CHANGELOG.md` and `LICENSE`, because pub.dev reads them per package, and its own `analysis_options.yaml` that includes `package:flutter_lints/flutter.yaml` together with the root `analysis_options.yaml`, so the strict analyzer block exists once; an example app includes the package's file. `analysis_options.yaml` is listed in the package's `.pubignore` (one unanchored pattern covers the example's file too), because the root file is not part of a published archive; CI fails a package without that line.

A package README states the install line, one runnable example, and what the package does not do. Platform limits are written down, not implied.

## Branches, commits, pull requests

- Branch from `main`: `feat/<package>-<topic>`, `fix/<package>-<topic>`, `chore/<topic>`.
- Commit messages follow Conventional Commits: `feat(mnemonic_backup_flow): random-word verification`.
- One package per pull request. Fill in the template, link the issue, and add a CHANGELOG entry under `Unreleased`. Until a package's first release is tagged, its `0.1.0` entry is edited in place instead.

## Rules for published code

- No credentials, private keys, wallet addresses, or company-internal references in code, comments, tests or docs. Comments are published text.
- No dependency on a service or endpoint that is not public.
- Public API has documentation comments.

## Releasing

1. Move the `Unreleased` entries in the package CHANGELOG under the new version and bump `version` in `pubspec.yaml`.
2. Merge to `main`.
3. Tag the public repository `<package>-v<version>` (for example `mnemonic_backup_flow-v0.1.0`). The release workflow publishes to pub.dev and creates the GitHub Release.

## Licensing of contributions

By contributing, you agree that your contribution is licensed under the licence of the package it lands in.
