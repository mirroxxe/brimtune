#!/bin/zsh
# Makes a release: builds Brimtune, packs and signs the DMG, and updates Sparkle's
# appcast. Everything lands in dist.noindex/, ready to upload to the site:
#
#   dist.noindex/Brimtune.dmg              always the latest (the site's Download button)
#   dist.noindex/updates/Brimtune-X.Y.Z.dmg  every release (what auto-updates download)
#   dist.noindex/appcast.xml               the update feed (served at /appcast.xml)
#
# Usage:
#   ./release.sh           release the version already in Info.plist
#   ./release.sh 1.0.1     set the version, bump the build number, then release
#
# Release notes: put them in ReleaseNotes/X.Y.Z.html; Sparkle shows them in the update window.
set -euo pipefail
cd "${0:A:h}"

PLIST=Resources/Info.plist
SITE="https://brimtune.pages.dev"
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
plist() { /usr/libexec/PlistBuddy -c "$1" "$PLIST"; }

if [[ -n "${1:-}" ]]; then
    plist "Set :CFBundleShortVersionString $1"
    plist "Set :CFBundleVersion $(( $(plist 'Print :CFBundleVersion') + 1 ))"
fi
VERSION=$(plist 'Print :CFBundleShortVersionString')
BUILD=$(plist 'Print :CFBundleVersion')
echo "==> Brimtune $VERSION ($BUILD)"

./build.sh

OUT=dist.noindex
mkdir -p "$OUT/updates"
DMG="$OUT/updates/Brimtune-$VERSION.dmg"
rm -f "$DMG"

echo "==> Packing $DMG"
STAGE=$(mktemp -d)
ditto build.noindex/Brimtune.app "$STAGE/Brimtune.app"
# The install guide, from Resources/ReadMe.html.
textutil -convert rtf Resources/ReadMe.html -output "$STAGE/Read Me.rtf"
create-dmg \
    --volname "Brimtune" \
    --background Resources/dmg-background.tiff \
    --window-pos 200 120 \
    --window-size 660 500 \
    --icon-size 112 \
    --text-size 13 \
    --icon "Brimtune.app" 165 185 \
    --hide-extension "Brimtune.app" \
    --app-drop-link 495 185 \
    --icon "Read Me.rtf" 330 295 \
    --hide-extension "Read Me.rtf" \
    --no-internet-enable \
    "$DMG" "$STAGE" >/dev/null
rm -rf "$STAGE"

IDENTITY="${BRIMTUNE_SIGN_IDENTITY:-$(security find-identity -p codesigning | awk -F'"' '/"Brimtune Developer"/ {split($1, a, " "); print a[2]; exit}')}"
codesign --force --sign "${IDENTITY:--}" "$DMG"

if [[ -f "ReleaseNotes/$VERSION.html" ]]; then
    cp "ReleaseNotes/$VERSION.html" "$OUT/updates/Brimtune-$VERSION.html"
fi

echo "==> Updating appcast"
# Signs each update with the EdDSA key from the login keychain (made by generate_keys).
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "$SITE/updates/" \
    --link "$SITE" \
    -o "$OUT/appcast.xml" \
    "$OUT/updates"

cp "$DMG" "$OUT/Brimtune.dmg"

echo
echo "Done: Brimtune $VERSION"
echo "  $OUT/Brimtune.dmg"
echo "  $OUT/updates/Brimtune-$VERSION.dmg"
echo "  $OUT/appcast.xml"
echo "Upload the contents of $OUT/ to the site to publish."
