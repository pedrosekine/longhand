#!/bin/sh
# Renders controls.html's scenes to shots/ with headless chromium.
cd "$(dirname "$0")"; mkdir -p shots
shot() { # name width height scale
  chromium --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --force-device-scale-factor="$4" --window-size="$2,$3" \
    --screenshot="$PWD/shots/$1.png" "file://$PWD/controls.html?s=$1" 2>/dev/null
}
shot big-read 1920 1280 1; shot big-disc 1920 1280 1
for s in lap-read lap-disc lap-hover lap-edge lap-drag lap-below note-read note-disc long; do shot $s 1440 900 1; done
shot half-chat 710 900 1; shot half-paper 710 900 1
shot keys 980 430 2
for l in word glyph key; do for st in reading discussing; do
  shot head-$l-$st 520 64 2; shot head-$l-$st-hover 520 64 2; done; done
shot glyph-hover-read 1440 900 1; shot glyph-hover-disc 1440 900 1
shot tip-glyph-reading 560 170 2; shot tip-glyph-discussing 560 170 2
# The boards gather the scenes; then the blank rows under each are trimmed.
for b in 1-screens 2-controls 3-hand 4-elsewhere 5-glyph; do
  chromium --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --window-size=1700,1400 --screenshot="$PWD/board-$b.png" "file://$PWD/board-$b.html" 2>/dev/null
done
python3 - <<'PY'
from PIL import Image
import glob
for f in glob.glob("board-*.png"):
    im = Image.open(f).convert("RGB"); w, h = im.size; px = im.load(); y = h - 1
    while y > 0 and all(px[x, y] == (27, 27, 24) for x in range(0, w, 7)): y -= 1
    im.crop((0, 0, w, min(h, y + 24))).save(f)
PY
