#!/usr/bin/env bash
# alter — installer.
# Builds both binaries from source, generates launchd plists pointed at this
# directory, copies them to ~/Library/LaunchAgents, and loads them.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS="$HOME/Library/LaunchAgents"
mkdir -p "$AGENTS"

# --- 1. Build ----------------------------------------------------------------
echo "▸ building breathe + affirm + alterprefs..."
swiftc -O "$DIR/breathe.swift"    -o "$DIR/breathe"
swiftc -O "$DIR/affirm.swift"     -o "$DIR/affirm"
swiftc -O -parse-as-library "$DIR/alterprefs.swift" -o "$DIR/alterprefs"

# --- 2. Seed affirmations.txt if missing -------------------------------------
if [ ! -f "$DIR/affirmations.txt" ]; then
    cp "$DIR/affirmations.example.txt" "$DIR/affirmations.txt"
    echo "▸ created affirmations.txt from example (edit it with your own)"
fi

# --- 3. Generate plists with this install path -------------------------------
echo "▸ generating launchd plists with INSTALL_DIR=$DIR"
ESC=$(printf '%s\n' "$DIR" | sed 's/[\/&]/\\&/g')
sed "s/__INSTALL_DIR__/$ESC/g" "$DIR/breathe.plist.template"    \
    > "$AGENTS/local.alter.breathe.plist"
sed "s/__INSTALL_DIR__/$ESC/g" "$DIR/affirm.plist.template"     \
    > "$AGENTS/local.alter.affirm.plist"
sed "s/__INSTALL_DIR__/$ESC/g" "$DIR/alterprefs.plist.template" \
    > "$AGENTS/local.alter.prefs.plist"

# --- 4. (Re)load agents -------------------------------------------------------
echo "▸ loading agents into launchd"
for label in local.alter.breathe local.alter.affirm local.alter.prefs; do
    launchctl unload "$AGENTS/$label.plist" 2>/dev/null || true
    launchctl load   "$AGENTS/$label.plist"
done

echo
echo "✓ installed."
echo
echo "  breathe — visible word every ~3-10 min (while active)."
echo "  affirm  — subliminal affirmation flash every 15-60 s (while active)."
echo "  alter   — menu-bar app for tweaking everything live (waveform icon, top right)."
echo
echo "Edit your affirmations:   $DIR/affirmations.txt"
echo "Uninstall later:          $DIR/uninstall.sh"
