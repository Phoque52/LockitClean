#!/bin/bash
# Builds build/LockitClean.app and build/LockitClean.dmg
#   ./build.sh            build the app + dmg
#   ./build.sh install    also copy the app into /Applications
set -euo pipefail
cd "$(dirname "$0")"

echo "🔨 Compiling…"
swift build -c release

APP="build/LockitClean.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LockitClean "$APP/Contents/MacOS/LockitClean"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "🎨 Making icon…"
swiftc -O scripts/make-icon.swift -framework AppKit -o build/make-icon
build/make-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"   # ad-hoc signature so macOS can remember the permission

echo "💿 Making DMG…"
mkdir -p build/dmg
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "LockitClean" -srcfolder build/dmg -ov -format UDZO build/LockitClean.dmg >/dev/null
rm -rf build/dmg build/AppIcon.iconset build/make-icon

if [[ "${1:-}" == "install" ]]; then
    rm -rf /Applications/LockitClean.app
    cp -R "$APP" /Applications/
    echo "📦 Installed to /Applications — find it in Launchpad or Spotlight."
fi

echo "✅ Done: $APP and build/LockitClean.dmg"
