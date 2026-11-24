"""What the QML shim asks the host itself — the environment, a detached run —
and what the host tells the page's holder (Main.qml): a summon, a global key."""
import os
import sys
from pathlib import Path

from PySide6.QtCore import QObject, QProcess, Signal, Slot
from PySide6.QtQml import QmlElement, QmlSingleton

import qs_io

REPO = Path(__file__).resolve().parent.parent

QML_IMPORT_NAME = "LonghandHost"
QML_IMPORT_MAJOR_VERSION = 1


class Bridge(QObject):
    """From the host to Main.qml, as signals: what a second `longhand`, a
    global key or the tray asked for. And the keys' names, for the menu."""
    summonRequested = Signal(str)       # a payload, as `omarchy-shell shell summon longhand.page` takes
    toggleRequested = Signal(str)
    pomoRequested = Signal(str)         # toggle | skip
    popupRequested = Signal(str)        # timer | deadlines: the bar's two popups
    quitRequested = Signal()
    keysChanged = Signal()
    notifyRequested = Signal(str, str)  # a title and what to say: `pomo`'s notify-send, here

    def __init__(self):
        super().__init__()
        self.keys = {}                  # action -> the key as shown
        self.problems = {}

    @Slot(str, result=str)
    def keyName(self, action):
        return self.keys.get(action, "")

    @Slot(result=str)
    def keyProblems(self):
        return "\n".join(self.problems.values())

    def act(self, action: str) -> None:
        """A global key's action, by Omarchy's name for it."""
        if action == "page":
            self.toggleRequested.emit("{}")
        elif action == "alongside":
            self.summonRequested.emit('{"shape":"alongside"}')
        elif action == "pomoToggle":
            self.pomoRequested.emit("toggle")
        elif action == "pomoSkip":
            self.pomoRequested.emit("skip")
        elif action == "pomoPopup":
            self.popupRequested.emit("timer")
        elif action == "deadlines":
            self.popupRequested.emit("deadlines")


BRIDGE = Bridge()


def state_dir() -> Path:
    return Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state") / "longhand"


def places_file() -> Path:
    return state_dir() / "windows.json"


def screen_here():
    from PySide6.QtGui import QCursor, QGuiApplication
    return QGuiApplication.screenAt(QCursor.pos()) or QGuiApplication.primaryScreen()


def themed_icon(background: str, foreground: str, accent: str) -> str:
    import hashlib
    import importlib.util
    spec = importlib.util.spec_from_file_location("longhand_theme_icon", REPO / "tools" / "theme_icon.py")
    ti = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(ti)
    tile, mark = ti.colours({"background": hexed(background), "foreground": hexed(foreground), "accent": hexed(accent)})
    svg = ti.render(tile, mark)
    out = state_dir() / "icon" / "tray"
    out.mkdir(parents=True, exist_ok=True)
    path = out / f"longhand-{hashlib.sha256(svg.encode()).hexdigest()[:10]}.svg"
    if not path.exists():
        tmp = path.with_suffix(".tmp")
        tmp.write_text(svg, encoding="utf-8")
        os.replace(tmp, path)
    for old in out.glob("longhand-*.svg"):
        if old != path:
            try:
                old.unlink()
            except OSError:
                pass
    return path.as_uri()


GLYPH_KEEP = 120          # glyph pictures kept: a minute each for two hours, and the deadlines'


def tray_glyph(text: str, role: str, background: str, foreground: str, accent: str, muted: str, urgent: str) -> str:
    """A tray icon that says a word or two, as the bar's labels do: the
    timer's minutes, the next deadline's distance. The tile in the ground,
    as the seal's; the text in the role's colour: "accent" (the accent
    moved towards the text until it reads, as the seal's mark), "text",
    "muted", "urgent". An SVG, so Windows draws it sharp at its own size;
    a file URL whose name carries a hash of what it shows."""
    import hashlib
    import html
    import importlib.util
    bg, fg = hexed(background), hexed(foreground)
    if role == "accent":
        spec = importlib.util.spec_from_file_location("longhand_theme_icon", REPO / "tools" / "theme_icon.py")
        ti = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(ti)
        ink = ti.colours({"background": bg, "foreground": fg, "accent": hexed(accent)})[1]
    else:
        ink = {"muted": hexed(muted), "urgent": hexed(urgent)}.get(role, fg)
    size = {1: 27, 2: 23}.get(len(text), 16)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" width="32" height="32">'
           f'<rect x="1" y="1" width="30" height="30" rx="7" fill="{bg}"/>'
           f'<text x="16" y="{16 + size * 0.36:.1f}" text-anchor="middle" font-family="Segoe UI" '
           f'font-weight="700" font-size="{size}" fill="{ink}">{html.escape(text)}</text></svg>')
    out = state_dir() / "icon" / "tray"
    out.mkdir(parents=True, exist_ok=True)
    path = out / f"glyph-{hashlib.sha256(svg.encode()).hexdigest()[:10]}.svg"
    if not path.exists():
        tmp = path.with_suffix(".tmp")
        tmp.write_text(svg, encoding="utf-8")
        os.replace(tmp, path)
        old = sorted(out.glob("glyph-*.svg"), key=lambda p: p.stat().st_mtime)
        for stale in old[:-GLYPH_KEEP]:
            try:
                stale.unlink()
            except OSError:
                pass
    return path.as_uri()


def hexed(c: str) -> str:
    """"#aarrggbb" (QML's colour as a string, with alpha) → "#rrggbb"."""
    c = str(c).strip().lower()
    return "#" + c[3:] if len(c) == 9 else c


@QmlElement
@QmlSingleton
class Host(QObject):
    @Slot(str, result="QVariant")
    def env(self, name):
        v = os.environ.get(name)
        if v:
            return v.replace("\\", "/") if name in ("HOME", "XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_DATA_HOME") else v
        if name == "HOME":
            # The page builds paths as HOME + "/.config/…": forward slashes,
            # which Windows and Qt both take.
            return Path.home().as_posix()
        return ""

    @Slot(result="QVariant")
    def workArea(self):
        """The room on the screen the pointer is on, the taskbar left out:
        where a popup by the clock may be put (shim/qs/Ui/KeyboardPanel.qml).
        Windows 11 has a clock on every screen's taskbar; the one by the
        person's hand is the one meant, as the bar's popup opens on the
        monitor that has the focus."""
        screen = screen_here()
        if screen is None:
            return {"x": 0, "y": 0, "width": 0, "height": 0}
        g = screen.availableGeometry()
        return {"x": g.x(), "y": g.y(), "width": g.width(), "height": g.height()}

    @Slot(result=str)
    def screenHere(self):
        """The name of the screen the pointer is on, for a window to open on
        (the overlay, the page's window the first time): where Hyprland puts
        a new window, the focused monitor."""
        screen = screen_here()
        return screen.name() if screen is not None else ""

    @Slot(str, result="QVariant")
    def savedPlace(self, name):
        """Where a window was left, `{x, y, width, height}`, or null: kept in
        the state folder across restarts (shim/Quickshell/FloatingWindow.qml),
        and only while the place is still on a screen."""
        import json
        try:
            g = json.loads(places_file().read_text(encoding="utf-8")).get(name)
            x, y, w, h = (int(g[k]) for k in ("x", "y", "width", "height"))
        except (OSError, ValueError, TypeError, AttributeError, KeyError):
            return None
        from PySide6.QtCore import QRect
        from PySide6.QtGui import QGuiApplication
        title_bar = QRect(x, y, w, 40)             # the part a hand must be able to reach
        if w < 200 or h < 150 or not any(s.availableGeometry().intersects(title_bar) for s in QGuiApplication.screens()):
            return None
        return {"x": x, "y": y, "width": w, "height": h}

    @Slot(str, "QVariant")
    def keepPlace(self, name, g):
        import json
        path = places_file()
        try:
            d = json.loads(path.read_text(encoding="utf-8"))
            d = d if isinstance(d, dict) else {}
        except (OSError, ValueError):
            d = {}
        try:
            d[name] = {k: int(g[k]) for k in ("x", "y", "width", "height")}
        except (TypeError, KeyError, ValueError):
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name("." + path.name + ".tmp")
        tmp.write_text(json.dumps(d, indent=2) + "\n", encoding="utf-8")
        os.replace(tmp, path)

    @Slot(str, str, str, result=str)
    def themedIcon(self, background, foreground, accent):
        """The tray's seal in Windows' colours, as tools/theme_icon.py gives
        the launcher's on Omarchy: the tile in the ground, the seal in the
        accent moved towards the text until it reads (3:1). A file URL; its
        name carries a hash of its colours, so a change is a new picture."""
        try:
            return themed_icon(background, foreground, accent)
        except Exception as e:  # noqa: BLE001 — the canonical icon stands in
            print(f"longhand: the tray's icon in the theme's colours: {e}", file=sys.stderr)
            return ""

    @Slot(str, str, str, str, str, str, str, result=str)
    def trayGlyph(self, text, role, background, foreground, accent, muted, urgent):
        """The timer's and the deadlines' tray icons (tray_glyph)."""
        try:
            return tray_glyph(text, role, background, foreground, accent, muted, urgent)
        except Exception as e:  # noqa: BLE001 — the tray keeps its last picture
            print(f"longhand: a tray icon's picture: {e}", file=sys.stderr)
            return ""

    @Slot("QVariantList")
    def execDetached(self, command):
        argv = [str(x) for x in command or []]
        if not argv:
            return
        # `omarchy-shell shell summon longhand.page '{…}'`: the shell is this
        # host, and the page is in it.
        if argv[:2] == ["omarchy-shell", "shell"] and len(argv) >= 4 and argv[3] == "longhand.page":
            payload = argv[4] if len(argv) > 4 else "{}"
            if argv[2] == "summon":
                BRIDGE.summonRequested.emit(payload)
                return
            if argv[2] == "toggle":
                BRIDGE.toggleRequested.emit(payload)
                return
        program, args = qs_io.resolve(argv)
        QProcess.startDetached(program, args)
