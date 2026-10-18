#!/usr/bin/env python3
"""theme_icon — the launcher's icon in the current Omarchy theme's colours
(2026-10-18; docs/brand/README.md, "Colour and theme adaptation").

The canonical icon (launcher/longhand.svg: the seal on a rounded tile) has
fixed colours. This writes a copy with the theme's: the tile in the theme's
background, the seal in its accent — moved towards the foreground until it
reads against the tile (3:1), the foreground itself when the accent cannot.
A neutral theme gives a neutral seal, as intended. The geometry is the
canonical file's, untouched; the copy is user state, never in the repo.

The copy's name carries a hash of its colours, and the desktop entry's
`Icon=` is pointed at it: the launcher draws icons through an image cache
keyed by path, so a theme change must be a new path to be seen at once.
Older copies are removed. The installed entry is written from the repo's
(launcher/longhand.desktop) with only `Icon=` changed, on every run — so a
change to the repo's entry still reaches the install — where it used to be
a symlink to it.

  python3 tools/theme_icon.py                 # write the icon for the current theme
  python3 tools/theme_icon.py --print         # say which colours it would use
  python3 tools/theme_icon.py --install-hook  # run it on every theme change (omarchy hook)
"""
from __future__ import annotations

import hashlib
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CANONICAL = ROOT / "launcher" / "longhand.svg"
ENTRY = ROOT / "launcher" / "longhand.desktop"  # the desktop entry's template
TILE, MARK = "#26262b", "#f2efe8"            # the canonical file's own fills
HOME = Path.home()
STATE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local" / "state")
COLORS = STATE / "omarchy" / "current" / "theme" / "colors.toml"
OUT = STATE / "longhand" / "icon"
DESKTOP = Path(os.environ.get("XDG_DATA_HOME") or HOME / ".local" / "share") / "applications" / "longhand.desktop"
TARGET = 3.0                                  # contrast a mark needs to read as a mark


def theme(path: Path = COLORS) -> dict:
    out = {}
    for line in path.read_text().splitlines():
        m = re.match(r'\s*([\w]+)\s*=\s*"(#[0-9a-fA-F]{6})"', line)
        if m:
            out[m.group(1)] = m.group(2).lower()
    return out


def rgb(h: str) -> tuple[float, float, float]:
    return tuple(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5))


def hexof(c) -> str:
    return "#" + "".join(f"{round(max(0, min(1, x)) * 255):02x}" for x in c)


def luminance(h: str) -> float:
    def ch(x):
        return x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4
    r, g, b = rgb(h)
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def mix(a: str, b: str, t: float) -> str:
    return hexof(tuple(x + (y - x) * t for x, y in zip(rgb(a), rgb(b))))


def colours(t: dict) -> tuple[str, str]:
    """(tile, mark) for a theme."""
    tile = t.get("background") or TILE
    fg = t.get("foreground") or MARK
    accent = t.get("accent") or fg
    if contrast(accent, tile) >= TARGET:
        return tile, accent
    for i in range(1, 21):                    # towards the foreground, a step at a time
        c = mix(accent, fg, i / 20)
        if contrast(c, tile) >= TARGET:
            return tile, c
    return tile, fg if contrast(fg, tile) >= TARGET else MARK


def render(tile: str, mark: str) -> str:
    svg = CANONICAL.read_text()
    assert f'fill="{TILE}"' in svg and f'fill="{MARK}"' in svg, "the canonical icon's fills changed"
    return (svg.replace(f'fill="{TILE}"', f'fill="{tile}"').replace(f'fill="{MARK}"', f'fill="{mark}"')
            .replace('data-longhand-status="canonical"', 'data-longhand-status="theme-derived"'))


def write(t: dict, out: Path = OUT, desktop: Path = DESKTOP) -> Path:
    tile, mark = colours(t)
    svg = render(tile, mark)
    out.mkdir(parents=True, exist_ok=True)
    path = out / f"longhand-{hashlib.sha256(svg.encode()).hexdigest()[:10]}.svg"
    if not path.exists():
        tmp = path.with_suffix(".tmp")
        tmp.write_text(svg)
        os.replace(tmp, path)
    for old in out.glob("longhand-*.svg"):
        if old != path:
            old.unlink()
    if desktop.exists() or desktop.is_symlink():
        new = re.sub(r"(?m)^Icon=.*$", f"Icon={path}", ENTRY.read_text())
        if desktop.is_symlink() or desktop.read_text() != new:
            tmp = desktop.with_name(desktop.name + ".tmp")
            tmp.write_text(new)
            os.replace(tmp, desktop)          # (a symlink is replaced, never written through)
    return path


HOOK = """#!/bin/bash
# Longhand's launcher icon in the new theme's colours (tools/theme_icon.py).
exec python3 "{script}"
"""


def install_hook() -> int:
    with tempfile.TemporaryDirectory() as d:
        hook = Path(d) / "longhand-icon"
        hook.write_text(HOOK.format(script=Path(__file__).resolve()))
        hook.chmod(0o755)
        return subprocess.run(["omarchy", "hook", "install", "theme-set", str(hook)]).returncode


def main(argv: list[str]) -> int:
    if "--install-hook" in argv:
        return install_hook()
    t = theme()
    if "--print" in argv:
        tile, mark = colours(t)
        print(f"tile {tile} · mark {mark} · contrast {contrast(mark, tile):.1f}:1 (accent {t.get('accent')})")
        return 0
    print(write(t))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
