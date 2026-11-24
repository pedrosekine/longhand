"""Windows' palette, as an Omarchy theme's colors.toml says one.

The page draws with a theme's named colours — red, yellow, orange, green,
cyan, blue, magenta (plugin-page/ThemeColors.qml) — read from
`~/.local/state/omarchy/current/theme/colors.toml`. Windows has no such file,
and without it every one of them fell back to the accent: a heading, a
link, a done task and a warning in one colour. Where the file is not there,
the host answers its path with this (qs_io.FileView): Windows 11's own
colours for those roles (Fluent's signal colours, text-strength for the
mode), for light or dark as the apps are, asked again each time it is read
— and ThemeColors reads it again whenever the shell's palette changes.

The accent, the ground and the text are not said here: the shell's palette
(shim/qs/Commons/Color.qml) has them from Windows, live, and the page takes
them from there. A real colors.toml, where someone has put one, still wins.
"""
from __future__ import annotations

# Windows 11's signal colours, light and dark: what Fluent uses for text
# and marks in each role on that mode's ground.
LIGHT = {
    "red": "#c42b1c", "yellow": "#9d5d00", "orange": "#ca5010", "green": "#0f7b0f",
    "cyan": "#038387", "blue": "#005fb8", "magenta": "#b4009e", "muted": "#6b6b6b",
}
DARK = {
    "red": "#ff99a4", "yellow": "#fce100", "orange": "#f7630c", "green": "#6ccb5f",
    "cyan": "#00b7c3", "blue": "#60cdff", "magenta": "#ff7ad9", "muted": "#9a9a9a",
}
SUFFIX = "/.local/state/omarchy/current/theme/colors.toml"

# The grounds and text the shell's palette draws with (shim/qs/Commons/Color.qml).
GROUND = {False: ("#f9f9f9", "#1b1b1b"), True: ("#202020", "#f3f3f3")}


def dark() -> bool:
    try:
        from PySide6.QtCore import Qt
        from PySide6.QtGui import QGuiApplication
        hints = QGuiApplication.styleHints()
        return hints is not None and hints.colorScheme() == Qt.ColorScheme.Dark
    except Exception:  # noqa: BLE001 — no application yet: light, as Windows starts
        return False


def registry_dark() -> bool:
    """Whether apps are dark, from the registry: for what runs without Qt
    (the export), where dark() above cannot ask."""
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                            r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize") as key:
            return winreg.QueryValueEx(key, "AppsUseLightTheme")[0] == 0
    except (ImportError, OSError):
        return False


def accent_text(is_dark: bool) -> str | None:
    """The accent as Windows sets text in it on that mode's ground (Fluent's
    AccentTextFillColorPrimary: the accent's second-darkest shade on light,
    its lightest on dark), from the eight shades Settings keeps. None where
    there is no such key."""
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                            r"Software\Microsoft\Windows\CurrentVersion\Explorer\Accent") as key:
            shades = bytes(winreg.QueryValueEx(key, "AccentPalette")[0])
    except (ImportError, OSError, TypeError):
        return None
    i = 0 if is_dark else 5                       # Light3, else Dark2
    if len(shades) < 4 * (i + 1):
        return None
    r, g, b = shades[4 * i:4 * i + 3]
    return f"#{r:02x}{g:02x}{b:02x}"


def theme(is_dark: bool | None = None) -> dict:
    """Windows' colours under a theme's names, ground and text and accent
    too: what a colors.toml would say, for what reads one outside the page
    (the export's omarchy look)."""
    is_dark = registry_dark() if is_dark is None else is_dark
    ground, text = GROUND[is_dark]
    out = dict(DARK if is_dark else LIGHT, background=ground, foreground=text)
    out["accent"] = accent_text(is_dark) or out["blue"]
    return out


def colors_toml(is_dark: bool | None = None) -> str:
    keys = DARK if (dark() if is_dark is None else is_dark) else LIGHT
    lines = ["# Windows' palette, said by Longhand's host (windows/palette.py)"]
    lines += [f'{k} = "{v}"' for k, v in keys.items()]
    return "\n".join(lines) + "\n"
