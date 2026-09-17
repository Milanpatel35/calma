#!/bin/bash
# Removes calmad and restores stock charging behaviour.
#
#   sudo Scripts/uninstall-daemon.sh [--keep-settings]
set -uo pipefail

LABEL="io.github.milanpatel35.calmad"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "error: run with sudo" >&2
    exit 1
fi

# Ask the running daemon for an emergency reset first, so keys are restored even if
# "Keep Limit After Quit" is on. Fall back to plain bootout if the CLI isn't beside us.
for cli in "${SCRIPT_DIR}/calma" /usr/local/bin/calma; do
    if [[ -x "${cli}" && -S /var/run/calmad.sock ]]; then
        "${cli}" reset || true
        break
    fi
done

launchctl bootout "system/${LABEL}" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/${LABEL}.plist" /Library/PrivilegedHelperTools/calmad /var/run/calmad.sock

# Remove the CLI symlink only if it points into a Calma bundle.
if [[ -L /usr/local/bin/calma ]] && readlink /usr/local/bin/calma | grep -q "Calma"; then
    rm -f /usr/local/bin/calma
fi

if [[ "${1:-}" != "--keep-settings" ]]; then
    rm -rf "/Library/Application Support/Calma"
fi

echo "calmad removed. Charging is back to macOS defaults. Logs remain in /Library/Logs/Calma."
