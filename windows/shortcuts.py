"""Longhand in the Start menu, and started with the session.

On Omarchy `tools/install` writes the launcher's desktop entry and the
shell starts the plugins. Here `longhand install` does the two things
Windows asks for in their place, both the person's own (nothing for all
users, nothing that needs an administrator):

- a shortcut, Longhand, in the Start menu's Programs: today's note as a
  window, as the desktop entry opens it. Its icon is the launcher's
  (launcher/longhand.svg, the seal on its tile), drawn at the sizes Windows
  asks for into one .ico in Longhand's state folder: a derivative, made
  where it is used, the geometry staying in the repo (docs/brand/README.md).
  The shortcut carries the name the running Longhand gives itself to
  Windows (`APP_ID`), so the taskbar knows the window for the shortcut's:
  one button, the seal on it, and pinning it pins Longhand, not Python.
- `longhand --tray` under the person's Run key: Longhand by the clock when
  the session starts, nothing opened.

`longhand uninstall` takes both away, and the icon.

Where they go can be moved for a test: APPDATA (the Start menu is under
it), XDG_STATE_HOME (the icon), LONGHAND_RUN_KEY (the key under
HKEY_CURRENT_USER).
"""
from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
APP_ID = "Longhand"
NAME = "Longhand"
# launcher/longhand.desktop's Comment.
COMMENT = "Today's page: you write, the agent answers in the margin"
SIZES = (16, 20, 24, 32, 40, 48, 64, 256)
RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"


def programs() -> Path:
    return Path(os.environ["APPDATA"]) / "Microsoft" / "Windows" / "Start Menu" / "Programs"


def shortcut_path() -> Path:
    return programs() / f"{NAME}.lnk"


def icon_path() -> Path:
    state = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state")
    return state / "longhand" / "icon" / "longhand.ico"


def run_key() -> str:
    return os.environ.get("LONGHAND_RUN_KEY") or RUN_KEY


def launcher() -> tuple[str, str]:
    """(program, arguments before any of ours): `longhand.exe` beside this
    Python, as `pip install -e windows` makes it, else this Python without a
    console and the host's file."""
    exe = Path(sys.executable).with_name("longhand.exe")
    if exe.is_file():
        return str(exe), ""
    windowless = Path(sys.executable).with_name("pythonw.exe")
    return str(windowless if windowless.is_file() else sys.executable), f'"{HERE / "longhand_host.py"}"'


def write_icon(svg: Path, out: Path) -> Path:
    """The launcher's SVG as one .ico holding every size in `SIZES`, each a
    PNG drawn from the vector at that size (never one picture scaled)."""
    from PySide6.QtCore import QBuffer, QByteArray, QIODevice, QRectF
    from PySide6.QtGui import QGuiApplication, QImage, QPainter
    from PySide6.QtSvg import QSvgRenderer

    app = QGuiApplication.instance() or QGuiApplication(sys.argv[:1])   # held while the pictures are drawn
    renderer = QSvgRenderer(str(svg))
    if not renderer.isValid():
        raise OSError(f"{svg} is not an SVG Qt can draw")
    pictures = []
    for size in SIZES:
        image = QImage(size, size, QImage.Format.Format_ARGB32)
        image.fill(0)
        painter = QPainter(image)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)
        painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)
        renderer.render(painter, QRectF(0, 0, size, size))
        painter.end()
        data = QByteArray()
        buffer = QBuffer(data)
        buffer.open(QIODevice.OpenModeFlag.WriteOnly)
        image.save(buffer, "PNG")
        buffer.close()
        pictures.append((size, bytes(data)))
    del app
    head = struct.pack("<HHH", 0, 1, len(pictures))
    entries, body, at = b"", b"", 6 + 16 * len(pictures)
    for size, png in pictures:
        entries += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(png), at)
        body += png
        at += len(png)
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_name(out.name + ".tmp")
    tmp.write_bytes(head + entries + body)
    os.replace(tmp, out)
    return out


def icon_sizes(ico: Path) -> list[int]:
    """The sizes an .ico holds (for the tests, and for looking)."""
    data = ico.read_bytes()
    _, kind, count = struct.unpack_from("<HHH", data, 0)
    if kind != 1:
        return []
    return [struct.unpack_from("<B", data, 6 + 16 * i)[0] or 256 for i in range(count)]


def powershell(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File",
                           str(HERE / "shortcut.ps1"), *args],
                          capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120,
                          creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))


def write_shortcut(path: Path, program: str, arguments: str, icon: Path) -> str:
    """The shortcut, through Windows' own shell (shortcut.ps1). Says what
    went wrong, or ""; the name for the taskbar may fail alone ("appid: …"),
    the shortcut standing all the same."""
    path.parent.mkdir(parents=True, exist_ok=True)
    r = powershell("-Path", str(path), "-Target", program, "-Arguments", arguments, "-Icon", str(icon),
                   "-Description", COMMENT, "-WorkDir", str(Path.home()), "-AppId", APP_ID)
    if r.returncode != 0 or not path.is_file():
        return (r.stderr or r.stdout or "the shortcut was not made").strip()[-600:]
    return next((line.strip() for line in r.stdout.splitlines() if line.startswith("appid:")), "")


def read_shortcut(path: Path) -> dict:
    r = powershell("-Path", str(path), "-Read")
    try:
        return json.loads(r.stdout)
    except ValueError:
        return {"error": (r.stderr or r.stdout).strip()[-600:]}


def autostart_command() -> str:
    program, arguments = launcher()
    return " ".join(part for part in (f'"{program}"', arguments, "--tray") if part)


def set_autostart(on: bool) -> None:
    import winreg
    with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, run_key(), 0, winreg.KEY_SET_VALUE) as key:
        if on:
            winreg.SetValueEx(key, NAME, 0, winreg.REG_SZ, autostart_command())
        else:
            try:
                winreg.DeleteValue(key, NAME)
            except FileNotFoundError:
                pass


def autostart() -> str:
    """What the session starts for Longhand; "" when nothing."""
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, run_key()) as key:
            return str(winreg.QueryValueEx(key, NAME)[0])
    except OSError:
        return ""


def install(with_autostart: bool = True, out=None) -> int:
    say = (lambda line: print(line, file=out or sys.stdout, flush=True))
    if os.name != "nt":
        say("longhand install is for Windows; on Omarchy: tools/install")
        return 2
    icon = write_icon(REPO / "launcher" / "longhand.svg", icon_path())
    program, arguments = launcher()
    problem = write_shortcut(shortcut_path(), program, arguments, icon)
    if problem and not problem.startswith("appid:"):
        say(f"longhand: no Start menu entry: {problem}")
        return 1
    say(f"Start menu → {shortcut_path()}")
    say(f"icon → {icon}")
    if problem:
        say(f"note: the taskbar will not know the window for the shortcut's ({problem[6:].strip()})")
    set_autostart(with_autostart)
    say(f"with the session → {autostart()}" if with_autostart else "with the session → not started (--no-autostart)")
    return 0


def uninstall(out=None) -> int:
    say = (lambda line: print(line, file=out or sys.stdout, flush=True))
    if os.name != "nt":
        say("longhand uninstall is for Windows")
        return 2
    for path in (shortcut_path(), icon_path()):
        try:
            path.unlink()
            say(f"removed {path}")
        except FileNotFoundError:
            pass
    if autostart():
        set_autostart(False)
        say("no longer started with the session")
    return 0
