# Installing Calma

Calma is free, open-source software distributed outside the App Store. Releases are **not notarized by Apple yet**, because notarization requires a paid Apple Developer Program membership. So the first time you open Calma, macOS shows a warning. This page explains the warning and how to get past it safely.

## 1. Install the app

1. Download `Calma-<version>.dmg` from the [latest release](https://github.com/Milanpatel35/calma/releases/latest).
2. Open the `.dmg` and drag **Calma** onto **Applications**.
3. Eject the disk image.

## 2. Open it the first time

Double-click **Calma** in Applications. macOS blocks it and shows:

> **"Calma" Not Opened**
> Apple could not verify "Calma" is free of malware that may harm your Mac or compromise your privacy.

The dialog offers only **Move to Trash** and **Done**.

**Click "Done".** Don't click *Move to Trash*.

### macOS 15 Sequoia and later (including macOS 26 and 27)

1. Open  **> System Settings > Privacy & Security**.
2. Scroll down to **Security**. You'll see: *""Calma" was blocked to protect your Mac."*
3. Click **Open Anyway**.
4. Confirm with Touch ID or your password, then click **Open Anyway** once more if asked.

Calma's icon appears in the menu bar. macOS remembers the choice, so this is a one-time step.

> On macOS 15 and later, Apple removed the old Control-click **> Open** shortcut for apps that aren't notarized. **System Settings > Privacy & Security** is now the only way through the dialog.

### macOS 13 Ventura and macOS 14 Sonoma

1. Right-click (or Control-click) **Calma** in Applications and choose **Open**.
2. Click **Open** in the dialog that appears.

### Terminal alternative (any macOS version)

This removes the quarantine flag macOS puts on downloaded files, so the app opens normally:

```sh
xattr -dr com.apple.quarantine /Applications/Calma.app
open /Applications/Calma.app
```

## 3. Install the helper

Click **Install Helper…** in Calma's menu bar popover and enter your administrator password once. `calmad` is the small background service that talks to the charging controller. Without it, Calma can only read your battery.

## Verifying what you downloaded

Every release publishes `SHA256SUMS.txt`. To check your download matches:

```sh
cd ~/Downloads
shasum -a 256 -c SHA256SUMS.txt
```

You can also inspect the ad-hoc code signature:

```sh
codesign -dvvv /Applications/Calma.app
```

Or skip binaries entirely and [build from source](../README.md#build-from-source). Apps you build yourself are never quarantined, so no warning appears.

## Why the warning appears

macOS Gatekeeper trusts apps that are signed with a paid **Developer ID** certificate and notarized by Apple. Calma's community builds are **ad-hoc signed**: the code is signed so macOS can detect tampering, but there's no Apple-issued identity behind it, and no notarization ticket. Gatekeeper therefore can't confirm who built the app and warns you.

The warning is about *provenance*, not about anything found inside the app. Apple didn't scan Calma and find a problem — it simply has nothing to check the build against.

Notarized releases are on the [roadmap](../README.md#roadmap). Maintainers with a Developer Program membership can produce them today; see [RELEASING.md](RELEASING.md#signing-and-notarization-optional).

## Uninstalling

```sh
sudo /Applications/Calma.app/Contents/Resources/uninstall-daemon.sh
```

Then drag `Calma.app` to the Trash. Removing the helper restores stock charging behaviour. See [RECOVERY.md](RECOVERY.md) if charging still looks wrong.
