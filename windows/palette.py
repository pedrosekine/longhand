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


def dark() -> bool:
    try:
        from PySide6.QtCore import Qt
        from PySide6.QtGui import QGuiApplication
        hints = QGuiApplication.styleHints()
        return hints is not None and hints.colorScheme() == Qt.ColorScheme.Dark
    except Exception:  # noqa: BLE001 — no application yet: light, as Windows starts
        return False


def colors_toml(is_dark: bool | None = None) -> str:
    keys = DARK if (dark() if is_dark is None else is_dark) else LIGHT
    lines = ["# Windows' palette, said by Longhand's host (windows/palette.py)"]
    lines += [f'{k} = "{v}"' for k, v in keys.items()]
    return "\n".join(lines) + "\n"
