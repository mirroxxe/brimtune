#!/bin/zsh
# Builds Brimtune.app next to this script.
set -euo pipefail
cd "${0:A:h}"

# One binary for both Apple Silicon and Intel Macs.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Brimtune"

APP="Brimtune.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Brimtune"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with a real identity when there is one: an unchanging signature lets macOS
# remember permissions (Safari automation, calendar, audio) across rebuilds.
IDENTITY="${BRIMTUNE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$APP"

echo "Built $PWD/$APP — run: open \"$PWD/$APP\""
