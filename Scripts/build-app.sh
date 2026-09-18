#!/bin/bash
# Builds Calma.app (universal), then packages a DMG, a ZIP and SHA-256 checksums in dist/.
#
#   Scripts/build-app.sh
#
# Environment:
#   VERSION              Version string (default: CalmaVersion.current)
#   ARCHS                "arm64 x86_64" (default) or a single architecture for faster local builds
#   DEVELOPER_ID         Signing identity, e.g. "Developer ID Application: Name (TEAMID)". Ad-hoc if unset.
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD   Notarize + staple when all are set.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

DEFAULT_VERSION="$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/CalmaKit/Models.swift)"
VERSION="${VERSION:-${DEFAULT_VERSION}}"
VERSION="${VERSION#v}"
ARCHS="${ARCHS:-arm64 x86_64}"
DIST="${ROOT}/dist"
APP="${DIST}/Calma.app"

arch_flags=()
for arch in ${ARCHS}; do arch_flags+=(--arch "${arch}"); done

echo "==> Building Calma ${VERSION} (${ARCHS})"
swift build -c release "${arch_flags[@]}"
BIN_DIR="$(swift build -c release "${arch_flags[@]}" --show-bin-path)"

echo "==> Assembling ${APP}"
rm -rf "${DIST}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BIN_DIR}/CalmaApp" "${APP}/Contents/MacOS/Calma"
cp "${BIN_DIR}/calmad" "${APP}/Contents/Resources/calmad"
cp "${BIN_DIR}/calma" "${APP}/Contents/Resources/calma"
cp Scripts/install-daemon.sh Scripts/uninstall-daemon.sh "${APP}/Contents/Resources/"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "${APP}/Contents/Resources/"
if [[ -d Resources/Localization ]]; then
    cp -R Resources/Localization/*.lproj "${APP}/Contents/Resources/"
fi
# SwiftPM resource bundles, if any target declares resources.
find "${BIN_DIR}" -maxdepth 1 -name "*.bundle" -exec cp -R {} "${APP}/Contents/Resources/" \;
printf "APPL????" > "${APP}/Contents/PkgInfo"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP}/Contents/Info.plist"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP}/Contents/Info.plist"

echo "==> Signing"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    sign=(codesign --force --timestamp --options runtime --sign "${DEVELOPER_ID}")
else
    echo "    DEVELOPER_ID not set — ad-hoc signing (users will need right-click → Open on first launch)"
    sign=(codesign --force --sign -)
fi
"${sign[@]}" "${APP}/Contents/Resources/calmad"
"${sign[@]}" "${APP}/Contents/Resources/calma"
"${sign[@]}" "${APP}"
codesign --verify --strict --verbose=1 "${APP}"

if [[ -n "${DEVELOPER_ID:-}" && -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_TEAM_ID:-}" && -n "${NOTARY_PASSWORD:-}" ]]; then
    echo "==> Notarizing"
    ditto -c -k --keepParent "${APP}" "${DIST}/notarize.zip"
    xcrun notarytool submit "${DIST}/notarize.zip" --apple-id "${NOTARY_APPLE_ID}" \
        --team-id "${NOTARY_TEAM_ID}" --password "${NOTARY_PASSWORD}" --wait
    xcrun stapler staple "${APP}"
    rm -f "${DIST}/notarize.zip"
fi

echo "==> Packaging"
ZIP="${DIST}/Calma-${VERSION}.zip"
DMG="${DIST}/Calma-${VERSION}.dmg"
ditto -c -k --keepParent "${APP}" "${ZIP}"

STAGING="$(mktemp -d)"
cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"
# Ad-hoc builds are blocked by Gatekeeper on first launch; spell out the way through.
if [[ -z "${DEVELOPER_ID:-}" ]]; then
    cat > "${STAGING}/READ ME FIRST.txt" <<'NOTE'
Opening Calma the first time
============================

1. Drag Calma onto the Applications folder in this window.

2. Open Calma from Applications. macOS will say:

     "Apple could not verify 'Calma' is free of malware..."

   Click "Done". Do NOT click "Move to Trash".

3. Approve it once:

   macOS 15 or later (including 26 and 27)
     Apple menu > System Settings > Privacy & Security
     Scroll to "Security", then click "Open Anyway" next to
     '"Calma" was blocked to protect your Mac' and confirm.

   macOS 13 or 14
     Right-click Calma in Applications and choose "Open", then "Open".

   Terminal (any version)
     xattr -dr com.apple.quarantine /Applications/Calma.app

4. Click "Install Helper..." in Calma's menu bar popover and enter your
   administrator password once.

Why does this happen?
---------------------
Calma is free and open source, and these builds are not notarized by Apple
(notarization needs a paid Apple Developer membership). Gatekeeper can't
confirm who built the app, so it warns you. Nothing was found inside the app.

Verify your download with the release's SHA256SUMS.txt:
  shasum -a 256 -c SHA256SUMS.txt

Full guide: https://github.com/Milanpatel35/calma/blob/main/docs/INSTALL.md
Source code: https://github.com/Milanpatel35/calma
NOTE
fi
hdiutil create -volname "Calma ${VERSION}" -srcfolder "${STAGING}" -ov -format UDZO "${DMG}" >/dev/null
rm -rf "${STAGING}"
if [[ -n "${DEVELOPER_ID:-}" ]]; then
    codesign --force --timestamp --sign "${DEVELOPER_ID}" "${DMG}"
fi

(cd "${DIST}" && shasum -a 256 "Calma-${VERSION}.zip" "Calma-${VERSION}.dmg" > SHA256SUMS.txt)

echo "==> Done"
ls -lh "${DIST}"
lipo -info "${APP}/Contents/MacOS/Calma"
