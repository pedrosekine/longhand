"""The launcher icon in the theme's colours (tools/theme_icon.py): readable in
every stock theme, the canonical geometry untouched, a new file for new
colours (the launcher's image cache is keyed by path), and the desktop entry
written from the repo's, never through a symlink into it.

Run: python3 tests/test_theme_icon.py
"""
import pathlib
import re
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import theme_icon as ti  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def main() -> int:
    themes = sorted(pathlib.Path("/usr/share/omarchy/themes").glob("*/colors.toml"))
    worst = min((ti.contrast(*reversed(ti.colours(ti.theme(t)))), t.parent.name) for t in themes) if themes else (9, "")
    check(not themes or worst[0] >= ti.TARGET, f"the seal reads against its tile in every stock theme (lowest {worst[0]:.1f}:1, {worst[1]})")
    check(ti.colours({"background": "#ffffff", "accent": "#fafafa", "foreground": "#111111"})[1] != "#fafafa",
          "an accent too close to the background is moved towards the foreground")

    canon = ti.CANONICAL.read_text()
    svg = ti.render("#101010", "#abcdef")
    path_of = lambda s: re.search(r'<path d="([^"]+)"', s).group(1)  # noqa: E731
    check(path_of(svg) == path_of(canon) and 'fill="#abcdef"' in svg and 'fill="#101010"' in svg,
          "the seal's geometry is the canonical one; only its two colours change")
    check('data-longhand-status="theme-derived"' in svg, "…and the copy does not call itself canonical")

    tmp = pathlib.Path(tempfile.mkdtemp(prefix="icon-test-"))
    out, desktop = tmp / "icon", tmp / "apps" / "longhand.desktop"
    desktop.parent.mkdir()
    template = tmp / "repo-entry.desktop"
    template.write_text(ti.ENTRY.read_text())
    desktop.symlink_to(template)
    a = ti.write({"background": "#1a1b26", "accent": "#7aa2f7", "foreground": "#c0caf5"}, out, desktop)
    check(not desktop.is_symlink() and template.read_text() == ti.ENTRY.read_text(),
          "a symlinked entry is replaced by a file, never written through into the repo")
    entry = desktop.read_text()
    check(f"Icon={a}" in entry and re.sub(r"(?m)^Icon=.*$", "", entry) == re.sub(r"(?m)^Icon=.*$", "", ti.ENTRY.read_text()),
          "the entry is the repo's, with only Icon= pointing at the icon")
    b = ti.write({"background": "#eff1f5", "accent": "#1e66f5", "foreground": "#4c4f69"}, out, desktop)
    check(a != b and b.exists() and not a.exists() and f"Icon={b}" in desktop.read_text(),
          "another theme: a new file (a new path for the launcher's cache), the old one gone")
    check(ti.write({"background": "#eff1f5", "accent": "#1e66f5", "foreground": "#4c4f69"}, out, desktop) == b,
          "the same theme again: the same file")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
