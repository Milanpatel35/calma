<!-- Pull requests go into `dev`. Only maintainers open the `dev` → `main` release PR. -->

## What does this change?

<!-- A short description. Link the issue: "Closes #123" -->

## Type

- [ ] Bug fix
- [ ] Feature
- [ ] Docs / website
- [ ] Translation
- [ ] Refactor / chore

## Hardware tested

<!-- Required for anything touching calmad, CalmaHardware or ChargeEngine. -->

| Model id (`sysctl -n hw.model`) | macOS | Backend | What you tested |
|---|---|---|---|
| | | | |

- [ ] Not applicable: this change doesn't affect hardware behaviour

## Checklist

- [ ] `swift build` and `swift test` pass
- [ ] `swiftlint --strict` passes
- [ ] New logic has unit tests (the SMC is faked, not touched)
- [ ] No new keys in the SMC write allowlist, **or** they're documented in `docs/SMC_KEYS.md`
- [ ] No telemetry, no network calls, no paid or gated features
- [ ] `CHANGELOG.md` updated under `[Unreleased]`
- [ ] Docs updated if behaviour changed
