#!/bin/sh
# Renders mock.html's four looks to PNG with headless chromium.
cd "$(dirname "$0")"
for v in now steps swap lift; do
  chromium --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --window-size=1600,1000 --screenshot="$PWD/$v.png" "file://$PWD/mock.html?v=$v" 2>/dev/null
done
