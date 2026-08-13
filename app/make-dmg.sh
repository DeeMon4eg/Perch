#!/bin/bash
# make-dmg.sh — build the app and package it into a drag-to-Applications DMG.
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
APP="$ROOT/Perch.app"
DMG="$ROOT/Perch.dmg"
STAGE="$(mktemp -d)"
VOLNAME="Perch"

./build-app.sh

# Staging: the app + a symlink to /Applications for drag-and-drop
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "done: $DMG"
echo "Open it and drag Perch into Applications."
