#!/bin/zsh
# Builds Brimtune.app into build.noindex/ (Spotlight skips *.noindex folders, so
# the build never shows up as a second Brimtune). With --install it also replaces
# /Applications/Brimtune.app and relaunches it.
set -euo pipefail
cd "${0:A:h}"

# One binary for both Apple Silicon and Intel Macs.
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
PRODUCTS="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"
BIN="$PRODUCTS/Brimtune"

OUT="build.noindex"
APP="$OUT/Brimtune.app"
mkdir -p "$OUT"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/Brimtune"

# Sparkle (auto-updates). Brimtune isn't sandboxed, so Sparkle's XPC services aren't needed.
ditto "$PRODUCTS/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices"

# Find frameworks inside the app, and drop rpaths that only exist on this build machine.
EXE="$APP/Contents/MacOS/Brimtune"
otool -l "$EXE" | awk '/LC_RPATH/{getline; getline; print $2}' | sort -u | while read -r rpath; do
    [[ "$rpath" == /usr/lib/swift ]] || install_name_tool -delete_rpath "$rpath" "$EXE" 2>/dev/null || true
done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with the "Brimtune Developer" certificate (self-signed, in the login keychain).
# An unchanging signature lets macOS remember permissions (Safari, calendar, audio)
# across updates. Override with BRIMTUNE_SIGN_IDENTITY; falls back to ad-hoc.
IDENTITY="${BRIMTUNE_SIGN_IDENTITY:-$(security find-identity -p codesigning | awk -F'"' '/"Brimtune Developer"/ {split($1, a, " "); print a[2]; exit}')}"
IDENTITY="${IDENTITY:--}"
# Inside out: nested code first, the app last (never --deep).
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" "$SPARKLE/Versions/B/Autoupdate"
codesign --force --sign "$IDENTITY" "$SPARKLE/Versions/B/Updater.app"
codesign --force --sign "$IDENTITY" "$SPARKLE"
codesign --force --sign "$IDENTITY" "$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Brimtune 2>/dev/null || true
    rm -rf /Applications/Brimtune.app
    cp -R "$APP" /Applications/
    open /Applications/Brimtune.app
    echo "Installed /Applications/Brimtune.app"
else
    echo "Built $PWD/$APP (./build.sh --install to put it in /Applications)"
fi
