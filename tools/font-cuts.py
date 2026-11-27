#!/usr/bin/env python3
"""The page's own Adwaita Sans (plugin-page/fonts/README.md).

Fixed cuts made from GNOME's variable files, named as ordinary styles, so
every font engine finds "Regular", "SemiBold", "Bold" by name:

    python tools/font-cuts.py /usr/share/fonts/Adwaita plugin-page/fonts

Needs fonttools.
"""
import sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
src, out = sys.argv[1], sys.argv[2]
cuts = [("Regular", 400, False), ("SemiBold", 600, False), ("Bold", 700, False),
        ("Italic", 400, True), ("SemiBold Italic", 600, True), ("Bold Italic", 700, True)]
FAM = "Adwaita Sans"
for style, wght, italic in cuts:
    f = TTFont(src + ("/AdwaitaSans-Italic.ttf" if italic else "/AdwaitaSans-Regular.ttf"))
    axes = {a.axisTag: (wght if a.axisTag == "wght" else a.defaultValue) for a in f["fvar"].axes}
    g = instancer.instantiateVariableFont(f, axes)
    ribbi = style in ("Regular", "Bold", "Italic", "Bold Italic")
    fam1 = FAM if ribbi else FAM + " SemiBold"
    sub2 = style if ribbi else ("Italic" if italic else "Regular")
    ps = FAM.replace(" ", "") + "-" + style.replace(" ", "")
    name = g["name"]
    version = name.getDebugName(5) or "Version 51.0"
    for nid in (1, 2, 3, 4, 6, 16, 17, 21, 22, 25):
        name.removeNames(nameID=nid)
    for nid, val in ((1, fam1), (2, sub2), (3, ps + ";" + version), (4, FAM + " " + style), (6, ps), (16, FAM), (17, style)):
        name.setName(val, nid, 3, 1, 0x409)
        name.setName(val, nid, 1, 0, 0)
    os2 = g["OS/2"]
    os2.usWeightClass = wght
    sel = os2.fsSelection & ~(0b1100001)          # italic, bold, regular bits off
    if italic: sel |= 1
    if wght == 700: sel |= 1 << 5
    if not italic and wght != 700: sel |= 1 << 6
    os2.fsSelection = sel
    head = g["head"]
    head.macStyle = (1 if wght == 700 else 0) | (2 if italic else 0)
    if "STAT" in g: del g["STAT"]
    fn = ps + ".ttf"
    g.save(out + "/" + fn)
    print(fn, "|", name.getDebugName(1), "|", name.getDebugName(2), "|", name.getDebugName(16), "/", name.getDebugName(17), "| w", wght)
