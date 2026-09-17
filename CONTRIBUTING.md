# Contributing to Calma

Thanks for being here. Calma is free software maintained by volunteers. It gets better mostly because people send small fixes and hardware reports.

## Ways to help that aren't code

- **Hardware reports.** Tell us your Mac model (`sysctl -n hw.model`), your macOS version, and which features work: charge limit, draining, MagSafe Light. Attach the output of `calma probe`. [File one here](https://github.com/Milanpatel35/calma/issues/new?template=hardware_report.yml). This is the most valuable contribution you can make, because we can't test every model.
- **Translations.** See [docs/TRANSLATING.md](docs/TRANSLATING.md). You don't need Xcode.
- **Documentation.** If something in the README confused you, that's a bug in the README.
- **Triage.** Reproducing open issues and adding detail saves maintainers hours.

## Development setup

You'll need macOS 13+, Xcode 15+ (or a Swift 5.9+ toolchain), and ideally a MacBook for testing hardware behaviour. The logic tests run anywhere.

Calma is a plain Swift Package. There's no `.xcodeproj`: open `Package.swift` in Xcode, or use the command line.

```sh
git clone https://github.com/Milanpatel35/calma.git
cd calma
swift build                  # builds CalmaApp, calmad, calma (CLI), CalmaKit, CalmaHardware
swift test                   # runs CalmaKitTests + CalmaHardwareTests (no hardware touched)
Scripts/build-app.sh         # packages dist/Calma.app, .dmg and .zip
```

### Package layout

| Target | Purpose |
|---|---|
| `CSMC` | A tiny C layer over the AppleSMC IOKit user client, written in C so the struct layout matches the kernel exactly. |
| `CalmaKit` | Pure Swift with no IOKit: settings, models, `ChargeEngine`, schedule, IPC protocol. |
| `CalmaHardware` | `SMCConnection`, the write allowlist, `BatteryReader`, power-source notifications. |
| `calmad` | The root LaunchDaemon. It's the only process that writes to the SMC. |
| `CalmaCLI` | The `calma` command-line tool. |
| `CalmaApp` | The SwiftUI menu bar app. |

### Running a development helper

Install the helper you just built:

```sh
swift build
sudo Scripts/install-daemon.sh .build/debug
```

To iterate on the daemon **without root**, point it at scratch locations. It still reads the battery, but SMC writes will fail and get logged:

```sh
export CALMA_SOCKET=/tmp/calmad.sock CALMA_SUPPORT_DIR=/tmp/calma CALMA_LOG_DIR=/tmp/calma-logs
swift run calmad &
swift run calma status
```

Remove the helper with `sudo Scripts/uninstall-daemon.sh`. If anything goes wrong, see [docs/RECOVERY.md](docs/RECOVERY.md).

### Before you push

```sh
swift build
swift test
swiftlint --strict          # brew install swiftlint
```

## Working on SMC code

Read [docs/SAFETY.md](docs/SAFETY.md) first. It is not optional.

- Never add a key to the write allowlist (`Sources/CalmaHardware/SMCKeys.swift`) without first documenting it in [docs/SMC_KEYS.md](docs/SMC_KEYS.md): what it does, its size and values, its safe default, and which models it's confirmed on.
- Never add a generic "write key" command to the IPC protocol.
- Put new behaviour in `ChargeEngine` as pure logic with unit tests. Keep I/O in `calmad`.
- Test helper changes against the in-memory SMC fake, and say in the PR what you tested on real hardware and on which model.
- Changes that could leave a Mac unable to charge get extra review and won't be merged quickly. That's deliberate.
- Don't write undocumented values to guessed keys, including on macOS 27. Research goes in an issue first.

## Pull requests

1. Open an issue first for anything bigger than a bug fix, so we can agree on the approach before you spend time on it.
2. Branch from `dev` and name the branch `feat/…`, `fix/…`, `docs/…` or `chore/…`. Open your PR against `dev`, never `main`.
3. Use [Conventional Commits](https://www.conventionalcommits.org/), for example `feat: add drift range to CLI`.
4. Keep each PR to one concern.
5. Add your change to `CHANGELOG.md` under `## [Unreleased]`.
6. Fill in the PR template, including the hardware you tested on.

CI must pass (build, tests, SwiftLint).

### Branches

| Branch | Purpose |
|---|---|
| `dev` | Default branch. Every change is merged here first and tested. |
| `main` | Stable and live. The website deploys from it and releases are tagged on it. It only changes through a `dev` → `main` pull request, once `dev` has been verified. |

 A maintainer will review; expect a round or two of comments, and don't take them personally.

## Code style

- `.swiftlint.yml` is the source of truth.
- Prefer explicit code over clever code. This codebase touches hardware, so readability beats brevity.
- Document public types with DocC comments.
- Don't add third-party runtime dependencies to the app, CLI or helper without discussing it first. Dev-only tooling is fine.

## Project principles

These aren't up for negotiation, so you don't spend effort on a PR that can't be merged:

1. **Everything stays free.** No paid tiers and no gated features, ever.
2. **No telemetry.** No analytics, no crash reporting, no phoning home. The only network call is the opt-in update check.
3. **Safety over features.** If a feature can't be made safe, it doesn't ship.
4. **Native macOS.** No Electron, no web views, no cross-platform frameworks.
5. **Clean room.** Never copy code, assets or text from proprietary apps.

## Releases

Maintainers merge `dev` into `main`, tag `vX.Y.Z` on `main`, and the release workflow builds, signs (when secrets are configured) and publishes. See [docs/RELEASING.md](docs/RELEASING.md).

## Recognition

Every kind of contribution counts: code, docs, translations, hardware reports and triage. Once your contribution lands, add yourself to [CONTRIBUTORS.md](CONTRIBUTORS.md), or ask a maintainer to add you.

## Code of conduct

By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md). Be decent to people.

## Licensing of contributions

Contributions are licensed under GPL-3.0, the same as the project. By submitting a PR you confirm you have the right to license your work that way.
