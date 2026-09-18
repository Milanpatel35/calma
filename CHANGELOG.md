# Changelog

All notable changes to Calma are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2026-09-18

### Added

- `docs/INSTALL.md`: first-launch guide covering Gatekeeper's "Apple could not verify" dialog.

### Fixed

- First-launch instructions everywhere now use System Settings → Privacy & Security → Open Anyway. Apple removed the right-click → Open shortcut for non-notarized apps in macOS 15.
- Charging controls no longer send commands the helper refuses in monitoring mode, which showed a red "Something went wrong" banner.

## [0.1.0] - 2026-09-17

First public pre-release.

### Added

- **Charge Limit** from 20% to 100%, enforced by the `calmad` LaunchDaemon so it keeps working while the app is closed and across user switches.
- **Drain to…** and **Auto Drain**, which run from the battery while plugged in on Macs that support disabling the adapter.
- **Drift Range**, to resume charging only after the level drops a set amount below the limit.
- **Heat Guard**, which pauses charging above a temperature threshold using 5-minute pause/resume windows.
- **Recalibrate**, a guided 100% → 10% → 100% → 1-hour hold cycle that persists across restarts.
- **True Percentage**, which uses the battery controller's raw state of charge.
- **Full Charge** (one-shot 100%, reverts on unplug) and **Pause Charging**.
- **Pause on Sleep**, **Stay Awake to Limit** and **Keep Limit After Quit**.
- **Schedule** with once/daily/weekdays/weekly/biweekly/monthly repeats, run-if-missed and task history.
- **MagSafe Light** control (system / status colours / off, optional blink while draining).
- **Power Flow**, a live diagram of adapter, battery and system power.
- Low Power Mode and High Power Mode toggles.
- Menu bar icon states for charging, paused, draining, on battery and paused for heat.
- The `calma` command-line tool and the `calma://` URL scheme for Shortcuts.
- A read-only `calma probe` SMC diagnostic.
- Safety: key write allowlist, admin-only IPC, first-run SMC probe record, write log, heartbeat watchdog, Emergency Reset.
- Hardware backends for Intel (`BCLM`), older Apple Silicon firmware (`CH0B`/`CH0C`/`CH0I`) and macOS 15–26 firmware (`CHTE`/`CHIE`).
- Monitoring mode on macOS 27 firmware, where no documented charge-control key exists.
- English localisation and a partial Hindi localisation.
- VoiceOver labels, keyboard navigation and reduced motion support.
- Documentation, a landing page, CI, and release and Pages workflows.

[Unreleased]: https://github.com/Milanpatel35/calma/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/Milanpatel35/calma/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/Milanpatel35/calma/releases/tag/v0.1.0
