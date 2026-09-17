# Releasing

Releases are built by `.github/workflows/release.yml` whenever a maintainer pushes a `vX.Y.Z` tag.

## Steps

1. Make sure `main` is green.
2. Update the version:
   - `CalmaVersion.current` in `Sources/CalmaKit/Models.swift`
   - `CFBundleShortVersionString` / `CFBundleVersion` in `Resources/Info.plist`, if you're not letting `Scripts/build-app.sh` stamp it
3. In `CHANGELOG.md`, move `[Unreleased]` entries under a new `## [X.Y.Z] - YYYY-MM-DD` heading and update the compare links.
4. Commit: `chore: release vX.Y.Z`.
5. Tag and push:
   ```sh
   git tag -a vX.Y.Z -m "Calma X.Y.Z"
   git push origin main --tags
   ```
6. The workflow builds a universal `Calma.app`, packages `Calma-X.Y.Z.dmg`, `Calma-X.Y.Z.zip` and `SHA256SUMS.txt`, and publishes a GitHub Release with generated notes. Tags containing `-` (such as `v0.2.0-beta.1`) are marked as pre-releases.
7. Edit the release notes: add highlights, the macOS 27 status, and install instructions.

## Local build

```sh
VERSION=0.1.0 Scripts/build-app.sh
ls dist/
```

## Signing and notarization (optional)

Without secrets, builds are **ad-hoc signed**. They work, but users must right-click → Open the first time. To produce Developer ID–signed, notarized builds, add these **repository secrets**:

| Secret | Contents |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | Your *Developer ID Application* certificate and private key exported as `.p12`, base64-encoded (`base64 -i cert.p12 \| pbcopy`) |
| `DEVELOPER_ID_CERT_PASSWORD` | The password of that `.p12` |
| `DEVELOPER_ID` | The signing identity name, e.g. `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_APPLE_ID` | The Apple ID email used for notarization |
| `NOTARY_TEAM_ID` | Your 10-character Team ID |
| `NOTARY_PASSWORD` | An [app-specific password](https://support.apple.com/102654) for that Apple ID |

When `DEVELOPER_ID_CERT_P12_BASE64` is present, the workflow imports the certificate into a temporary keychain and runs the build with `DEVELOPER_ID` set, so the script signs with the hardened runtime. When the notary secrets are also present, it submits the DMG with `xcrun notarytool submit --wait` and staples the ticket.

Signing requires a paid Apple Developer Program membership.

## After releasing

- Check that the download link on the website (`releases/latest`) points to the new build.
- Post in Discussions and update `launch/POSTS.md` if you're announcing it.
- Once notarized releases exist, update or submit the Homebrew cask (planned).
