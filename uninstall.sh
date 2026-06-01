#!/usr/bin/env bash
# alter — uninstaller. Unloads and removes the launchd agents.
# Source files, binaries, and affirmations.txt are left in place.

set -euo pipefail

AGENTS="$HOME/Library/LaunchAgents"

for label in local.alter.breathe local.alter.affirm; do
    plist="$AGENTS/$label.plist"
    if [ -f "$plist" ]; then
        launchctl unload "$plist" 2>/dev/null || true
        rm "$plist"
        echo "✓ removed $label"
    fi
done

echo
echo "alter is uninstalled. Source and binaries remain at:"
echo "  $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
