#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
DYLIB="$ROOT/foldertop_hook.dylib"
APP="$ROOT/Perch.app"

# Build the hook dylib. arm64e is required — otherwise it won't load into Finder.
if [ ! -f "$DYLIB" ]; then
  echo "Building foldertop_hook.dylib (arm64e)…"
  clang -dynamiclib -fobjc-arc -arch arm64e -framework Foundation \
        -o "$DYLIB" "$ROOT/foldertop_hook.m"
fi

# Icons
swiftc makeicons.swift -o /tmp/mkicons
/tmp/mkicons
iconutil -c icns AppIcon.iconset -o AppIcon.icns

# Bundle
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O main.swift -o "$APP/Contents/MacOS/Perch" -framework Cocoa
cp Info.plist "$APP/Contents/Info.plist"
cp "$DYLIB" "$APP/Contents/Resources/foldertop_hook.dylib"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp menubarTemplate.png "$APP/Contents/Resources/menubarTemplate.png"

# Sign inside-out (no --deep)
codesign -s - --force "$APP/Contents/Resources/foldertop_hook.dylib"
codesign -s - --force "$APP"
echo "done: $APP"
echo "For launch-at-login (SMAppService), move it to /Applications:"
echo "    cp -R \"$APP\" /Applications/  &&  open /Applications/Perch.app"
