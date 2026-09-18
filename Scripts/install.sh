#!/bin/bash
# Downloads a Calma release, verifies its checksum, installs it and clears the
# quarantine flag, so macOS doesn't show the "Apple could not verify" dialog.
#
#   curl -fsSL https://raw.githubusercontent.com/Milanpatel35/calma/main/Scripts/install.sh | bash
#
# Options (environment):
#   VERSION     Tag to install, e.g. v0.1.1 (default: latest release)
#   APP_DIR     Where to install (default: /Applications)
#   SKIP_OPEN   Set to 1 to install without launching Calma
set -euo pipefail

REPO="Milanpatel35/calma"
APP_DIR="${APP_DIR:-/Applications}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"; [[ -n "${MOUNT:-}" ]] && hdiutil detach -quiet "${MOUNT}" 2>/dev/null || true' EXIT

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "error: Calma only runs on macOS" >&2
    exit 1
fi

# Resolve the tag to install.
if [[ -z "${VERSION:-}" ]]; then
    echo "==> Finding the latest release"
    VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
if [[ -z "${VERSION}" ]]; then
    echo "error: couldn't determine the latest version. Set VERSION=v0.1.1 and retry." >&2
    exit 1
fi
PLAIN="${VERSION#v}"
BASE="https://github.com/${REPO}/releases/download/${VERSION}"
DMG="Calma-${PLAIN}.dmg"

echo "==> Downloading Calma ${VERSION}"
curl -fL --progress-bar -o "${TMP}/${DMG}" "${BASE}/${DMG}"
curl -fsSL -o "${TMP}/SHA256SUMS.txt" "${BASE}/SHA256SUMS.txt"

echo "==> Verifying checksum"
EXPECTED="$(awk -v f="${DMG}" '$2 == f || $2 == "*"f {print $1}' "${TMP}/SHA256SUMS.txt" | head -1)"
ACTUAL="$(shasum -a 256 "${TMP}/${DMG}" | awk '{print $1}')"
if [[ -z "${EXPECTED}" ]]; then
    echo "error: ${DMG} isn't listed in SHA256SUMS.txt — refusing to install" >&2
    exit 1
fi
if [[ "${EXPECTED}" != "${ACTUAL}" ]]; then
    echo "error: checksum mismatch — refusing to install" >&2
    echo "  expected ${EXPECTED}" >&2
    echo "  actual   ${ACTUAL}" >&2
    exit 1
fi
echo "    ${ACTUAL}  ok"

echo "==> Installing to ${APP_DIR}"
MOUNT="$(hdiutil attach -nobrowse -readonly "${TMP}/${DMG}" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)"
if [[ -z "${MOUNT}" || ! -d "${MOUNT}/Calma.app" ]]; then
    echo "error: couldn't mount ${DMG}" >&2
    exit 1
fi

# Quit a running copy so the bundle isn't replaced underneath it.
if pgrep -x Calma >/dev/null; then
    echo "    quitting the running copy"
    osascript -e 'quit app "Calma"' 2>/dev/null || pkill -x Calma || true
    sleep 1
fi

mkdir -p "${APP_DIR}"
SUDO=""
if [[ ! -w "${APP_DIR}" ]]; then
    echo "    ${APP_DIR} needs administrator rights"
    SUDO="sudo"
fi
${SUDO} rm -rf "${APP_DIR}/Calma.app"
${SUDO} ditto "${MOUNT}/Calma.app" "${APP_DIR}/Calma.app"
hdiutil detach -quiet "${MOUNT}"
MOUNT=""

# Nothing here bypasses a security check: the file was fetched over HTTPS and its
# checksum verified above, so the quarantine prompt would add no information.
echo "==> Clearing the quarantine flag"
${SUDO} xattr -dr com.apple.quarantine "${APP_DIR}/Calma.app" 2>/dev/null || true

echo "==> Installed ${APP_DIR}/Calma.app (${VERSION})"
if [[ "${SKIP_OPEN:-0}" != "1" ]]; then
    open "${APP_DIR}/Calma.app"
    echo "    Calma is in your menu bar. Click \"Install Helper…\" to finish setup."
else
    echo "    Open it from ${APP_DIR} when you're ready."
fi
