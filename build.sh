#!/bin/zsh
# Builds Brimtune.app into build.noindex/ (Spotlight skips *.noindex folders, so
# the build never shows up as a second Brimtune). With --install it also replaces
# /Applications/Brimtune.app and relaunches it.
set -euo pipefail
cd "${0:A:h}"

# One binary for both Apple Silicon and Intel Macs.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/Brimtune"

OUT="build.noindex"
APP="$OUT/Brimtune.app"
mkdir -p "$OUT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Brimtune"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with a real identity when there is one: an unchanging signature lets macOS
# remember permissions (Safari automation, calendar, audio) across rebuilds.
IDENTITY="${BRIMTUNE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID Application/ {print $2; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Brimtune 2>/dev/null || true
    rm -rf /Applications/Brimtune.app
    cp -R "$APP" /Applications/
    open /Applications/Brimtune.app
    echo "Installed /Applications/Brimtune.app"
else
    echo "Built $PWD/$APP (./build.sh --install to put it in /Applications)"
fi
