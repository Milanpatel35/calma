# Launch checklist

## Before making the repo public

- [ ] `swift build -c release` and `swift test` pass locally
- [ ] `Scripts/build-app.sh` produces `dist/Calma.app`, `.dmg`, `.zip`
- [ ] Screenshots regenerated: `swift run CalmaApp --render-screenshots screenshots`, then copied to `site/assets/screenshots/`
- [ ] README images render (icon, popover light/dark, gallery)
- [ ] `docs/SAFETY.md` and `docs/RECOVERY.md` reviewed
- [ ] Emergency Reset tested from a paused/draining state on real hardware
- [ ] Tested on at least two Mac models (ask friends for `calma probe` output)
- [ ] macOS 27 monitoring-mode banner verified
- [ ] No secrets, personal paths or email addresses in the repo (`git grep -i -E "password|token|@gmail"`)

## GitHub settings

- [ ] Repo **About**: description, website `https://milanpatel35.github.io/calma/`, topics (see `POSTS.md`)
- [ ] Social preview image: Settings → General → Social preview (use `screenshots/popover-light.png` or a 1280×640 banner)
- [ ] Enable **Issues**, **Discussions** (categories: Q&A, Ideas, Show and tell, Hardware)
- [ ] Enable **Private vulnerability reporting** (Settings → Code security)
- [ ] **Pages**: Settings → Pages → Source: *GitHub Actions* (the `Website` workflow deploys `site/`)
- [ ] Branch protection on `main`: require CI, require PR review
- [ ] Create labels: `good first issue`, `help wanted`, `hardware-report`, `needs-triage`, `macos-27`, `i18n`, `safety`
- [ ] Optional: enable GitHub Sponsors (donations never unlock features)

## First release

- [ ] `git tag -a v0.1.0 -m "Calma 0.1.0" && git push --tags`
- [ ] Release workflow succeeded, with DMG, ZIP and `SHA256SUMS.txt` attached
- [ ] Release notes include install steps, the Privacy & Security "Open Anyway" note (link docs/INSTALL.md) and the macOS 27 status
- [ ] Download link on the website works (`/releases/latest`)
- [ ] Open the good-first-issues below and pin "macOS 27 charge control" and "Hardware reports wanted"

## Announce

- [ ] LinkedIn, X thread, r/macapps, Show HN, Product Hunt (see `POSTS.md`); space them over a few days
- [ ] Reply to every early issue and comment within a day, because early responsiveness builds trust

---

## Good first issues (drafts)

### 1. Add Gujarati translation
**Labels:** `good first issue`, `i18n`

> Calma currently ships English and a partial Hindi translation. Add a Gujarati (`gu`) translation.
>
> **Steps**
> 1. Copy `Resources/Localization/en.lproj/Localizable.strings` to `Resources/Localization/gu.lproj/`.
> 2. Translate the right-hand values, keeping placeholders like `%@` and `%lld` intact.
> 3. Add `gu` to `CFBundleLocalizations` in `Resources/Info.plist`.
> 4. Run `plutil -lint` on the file.
>
> See `docs/TRANSLATING.md`. Partial translations are welcome.

### 2. Hardware report: M1 MacBook Air
**Labels:** `good first issue`, `hardware-report`, `help wanted`

> We have no confirmed report for the M1 MacBook Air (`MacBookAir10,1`). If you own one:
>
> 1. Run `calma probe` (read-only, no root) and paste the output.
> 2. Install Calma and test charge limit, drain, Full Charge and Emergency Reset.
> 3. File the results with the **Hardware report** template.
>
> We'll add the results to the table in `docs/SMC_KEYS.md`.

### 3. macOS 27 charge control research
**Labels:** `help wanted`, `macos-27`, `safety`

> macOS 27 firmware removed `CH0B`, `CH0C`, `CHTE` and `CH0I`. On `Mac16,1`, `CHIE`, `ACLC`, `CHLT`/`bfG0` (`50 05 05`) are present, and `bfD0`/`bfE0`/`bfF0` exist but are unreadable.
>
> We're looking for a **documented, safe** way to inhibit charging on this firmware. Please share:
> - `calma probe` output from different models on macOS 27
> - public references (open-source code, driver patches, Apple frameworks) describing the new interface
>
> **Out of scope:** adapter toggling via `CHIE` (micro-cycles the battery), and writing guessed values to `bf*` keys. Research first, code second.

### 4. Homebrew cask
**Labels:** `good first issue`, `distribution`

> Add a Homebrew cask so users can `brew install --cask calma`.
>
> - Draft `calma.rb` pointing at `https://github.com/Milanpatel35/calma/releases/download/v#{version}/Calma-#{version}.dmg` with `sha256` from `SHA256SUMS.txt`.
> - Include `uninstall` steps that run the helper uninstall script and a `zap` stanza for `/Library/Application Support/Calma` and `/Library/Logs/Calma`.
> - Note: homebrew-cask generally requires notarized apps, so this may start as a tap (`Milanpatel35/homebrew-tap`).

### 5. Native App Intents via an Xcode project
**Labels:** `enhancement`, `help wanted`

> Shortcuts support currently uses `calma://` URLs and the CLI. Native App Intents (Get Battery Percentage, Set Charge Limit, Full Charge, Drain To, etc.) need the App Intents metadata processor, which only runs in Xcode builds, not `swift build`.
>
> Proposal: add an Xcode project (or XcodeGen `project.yml`) that wraps the existing Swift package targets, add an `Intents/` folder in `CalmaApp`, and update `Scripts/build-app.sh` and CI.

### 6. Migrate the helper to SMAppService + XPC for signed builds
**Labels:** `enhancement`, `security`

> For notarized builds, register `calmad` with `SMAppService.daemon` and communicate over XPC with mutual code-signing checks (`SecCodeCheckValidity` + designated requirement), keeping the Unix-socket path for unsigned community builds.
>
> Requirements: identical command set, the same admin authorization semantics, and a migration path that removes the old LaunchDaemon plist cleanly. See `docs/ARCHITECTURE.md`.

### 7. Menu bar icon style options
**Labels:** `good first issue`, `ui`

> Add an **Appearance** option for the menu bar item: *icon only*, *icon + percentage*, *percentage only*, and a monochrome vs. colour state glyph. Keep VoiceOver labels accurate for every style, and store the preference in the app's `UserDefaults`, not in daemon settings.

### 8. Export battery history as CSV
**Labels:** `enhancement`, `good first issue`

> Record a lightweight local history (for example every 5 minutes: timestamp, percentage, hardware percentage, temperature, cycle count, state, adapter watts) and add **Settings → Dashboard → Export CSV…**.
>
> Keep it local only, cap it (for example 90 days), and document the file location in the README's Privacy section.
