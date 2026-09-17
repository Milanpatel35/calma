#!/bin/bash
# Installs calmad, Calma's privileged helper, as a system LaunchDaemon.
#
#   sudo Scripts/install-daemon.sh [directory-containing-calmad]
#
# Calma.app runs the bundled copy of this script (with an administrator prompt) from
# Calma.app/Contents/Resources. Developers can point it at .build/debug.
set -euo pipefail

LABEL="io.github.milanpatel35.calmad"
BIN="/Library/PrivilegedHelperTools/calmad"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
LOG_DIR="/Library/Logs/Calma"
SOURCE_DIR="${1:-$(cd "$(dirname "$0")" && pwd)}"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "error: run with sudo" >&2
    exit 1
fi
if [[ ! -x "${SOURCE_DIR}/calmad" ]]; then
    echo "error: calmad not found in ${SOURCE_DIR}" >&2
    exit 1
fi

# Stop a previous version first. Its SIGTERM handler restores stock charging.
launchctl bootout "system/${LABEL}" 2>/dev/null || true

mkdir -p /Library/PrivilegedHelperTools "${LOG_DIR}" "/Library/Application Support/Calma"
# Copy (never symlink) so the root-run binary can't be swapped from a user-writable location.
install -m 755 -o root -g wheel "${SOURCE_DIR}/calmad" "${BIN}"
xattr -c "${BIN}" 2>/dev/null || true

cat > "${PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BIN}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/calmad.stderr.log</string>
</dict>
</plist>
PLIST
chown root:wheel "${PLIST}"
chmod 644 "${PLIST}"

launchctl bootstrap system "${PLIST}"
launchctl enable "system/${LABEL}"

for _ in {1..20}; do
    [[ -S /var/run/calmad.sock ]] && break
    sleep 0.25
done

if [[ -S /var/run/calmad.sock ]]; then
    echo "calmad installed and running."
else
    echo "warning: calmad was installed but its socket hasn't appeared yet. See ${LOG_DIR}/calmad.log" >&2
fi
