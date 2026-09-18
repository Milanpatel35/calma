#!/bin/bash
# Points git at the hooks tracked in .githooks, so this clone refuses direct
# pushes to main. Run once after cloning:
#
#   Scripts/setup-hooks.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

chmod +x .githooks/* 2>/dev/null || true
git config core.hooksPath .githooks

echo "Hooks enabled (core.hooksPath = .githooks)."
echo "Pushes to main are now blocked locally; work on dev and open a pull request."
