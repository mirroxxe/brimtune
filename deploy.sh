#!/bin/zsh
# Builds the website into public.noindex/ and publishes it to Cloudflare Pages
# (brimtune.pages.dev), together with the latest release from dist.noindex/.
#
# Usage:
#   ./deploy.sh            build and publish (first time: npx wrangler login)
#   ./deploy.sh --preview  build and serve locally on http://localhost:8899
set -euo pipefail
cd "${0:A:h}"

OUT=public.noindex
rm -rf "$OUT"
mkdir -p "$OUT"

# Static pages and assets.
rsync -a --exclude 'doc-template.html' --exclude 'build-pages.mjs' site/ "$OUT/"
node site/build-pages.mjs "$OUT"

# The release: DMG for the Download button, versioned DMGs and the feed for auto-updates.
if [[ -f dist.noindex/Brimtune.dmg ]]; then
    cp dist.noindex/Brimtune.dmg "$OUT/"
    cp dist.noindex/appcast.xml "$OUT/"
    mkdir -p "$OUT/updates"
    # Files only: Sparkle parks superseded deltas in updates/old_updates/.
    find dist.noindex/updates -maxdepth 1 -type f -exec cp {} "$OUT/updates/" \;
else
    echo "warning: no release in dist.noindex/ — run ./release.sh first; the Download button will 404" >&2
fi

cat > "$OUT/_redirects" <<'EOF'
/download /Brimtune.dmg 302
EOF
cat > "$OUT/_headers" <<'EOF'
/appcast.xml
  Cache-Control: no-cache
/Brimtune.dmg
  Cache-Control: no-cache
  Content-Disposition: attachment; filename="Brimtune.dmg"
EOF

if [[ "${1:-}" == "--preview" ]]; then
    echo "Preview: http://localhost:8899"
    exec npx --yes serve@14.2.4 "$OUT" -l 8899
fi

npx --yes wrangler@4 pages deploy "$OUT" --project-name brimtune --branch main --commit-dirty=true
