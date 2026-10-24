#!/bin/zsh
# Renders Tools/og.html (it reuses the site's own CSS) to site/assets/og.png, 1200x630.
set -euo pipefail
cd "${0:A:h}/.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=1200,630 \
  --virtual-time-budget=8000 --screenshot=site/assets/og.png "file://$PWD/Tools/og.html" >/dev/null 2>&1
echo "Wrote site/assets/og.png"
