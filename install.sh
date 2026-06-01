#!/usr/bin/env bash
# alter — installer.
# Builds both binaries from source, generates launchd plists pointed at this
# directory, copies them to ~/Library/LaunchAgents, and loads them.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS="$HOME/Library/LaunchAgents"
mkdir -p "$AGENTS"

# --- 1. Build ----------------------------------------------------------------
echo "▸ building breathe + affirm..."
swiftc -O "$DIR/breathe.swift" -o "$DIR/breathe"
swiftc -O "$DIR/affirm.swift"  -o "$DIR/affirm"

# --- 2. Seed affirmations.txt if missing -------------------------------------
if [ ! -f "$DIR/affirmations.txt" ]; then
    cp "$DIR/affirmations.example.txt" "$DIR/affirmations.txt"
    echo "▸ created affirmations.txt from example (edit it with your own)"
fi

# --- 3. Generate plists with this install path -------------------------------
echo "▸ generating launchd plists with INSTALL_DIR=$DIR"
ESC=$(printf '%s\n' "$DIR" | sed 's/[\/&]/\\&/g')
sed "s/__INSTALL_DIR__/$ESC/g" "$DIR/breathe.plist.template" \
    > "$AGENTS/local.alter.breathe.plist"
sed "s/__INSTALL_DIR__/$ESC/g" "$DIR/affirm.plist.template"  \
    > "$AGENTS/local.alter.affirm.plist"

# --- 4. (Re)load agents -------------------------------------------------------
echo "▸ loading agents into launchd"
launchctl unload "$AGENTS/local.alter.breathe.plist" 2>/dev/null || true
launchctl unload "$AGENTS/local.alter.affirm.plist"  2>/dev/null || true
launchctl load   "$AGENTS/local.alter.breathe.plist"
launchctl load   "$AGENTS/local.alter.affirm.plist"

echo
echo "✓ installed."
echo
echo "  breathe — visible word, every ~5 min while active."
echo "  affirm  — subliminal affirmation flash, every 45-180 s while active."
echo
echo "Edit your affirmations:   $DIR/affirmations.txt"
echo "Uninstall later:          $DIR/uninstall.sh"
