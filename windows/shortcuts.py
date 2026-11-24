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
- the commands by name in any new terminal, as Omarchy's `~/.local/bin`
  has them: a copy of each launcher `pip install -e windows` made beside
  python.exe (`COMMANDS`) in `~/.local/bin`, and that folder on the
  person's PATH (HKCU\\Environment, the type of the value kept). Not the
  venv's Scripts folder itself: that would put its python.exe, pip.exe and
  pyside6-*.exe on PATH too. A copy is enough: each launcher holds the
  path of the python.exe it starts, and runs the script in the repo, so a
  pull is still the update (`with_path=False`, `--no-path`, leaves this out).

`longhand uninstall` takes them away, and the icon: the copies, and the
folder off PATH when nothing else is left in it (uv puts its tools there too).

Where they go can be moved for a test: APPDATA (the Start menu is under
it), XDG_STATE_HOME (the icon), LONGHAND_RUN_KEY (the key under
HKEY_CURRENT_USER), LONGHAND_BIN (the commands' folder), LONGHAND_ENV_KEY
(the key under HKEY_CURRENT_USER whose Path is the person's PATH; Windows
is told of a change only to the real one).
"""
from __future__ import annotations

import json
import os
import shutil
import struct
import subprocess
import sys
from pathlib import Path

from pyshim.longhand_replace import replace

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
APP_ID = "Longhand"
NAME = "Longhand"
# launcher/longhand.desktop's Comment.
COMMENT = "Today's page: you write, the agent answers in the margin"
SIZES = (16, 20, 24, 32, 40, 48, 64, 256)
RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
ENV_KEY = "Environment"
MACHINE_ENV_KEY = r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
# What Omarchy's tools/install links into ~/.local/bin, and the page.
COMMANDS = ("pomo", "longhand-agent", "longhand-check", "longhand-read", "longhand-doctor", "longhand")


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
    # The same name each install, and Explorer reads it to draw the shortcut:
    # tried again while it does, as every Longhand script's replace is (this
    # is the host's process, which is not given the patient one; but here no
    # window waits). Should it still be held, the icon already there stays.
    try:
        replace(tmp, out)
    except OSError:
        tmp.unlink(missing_ok=True)
        if not out.is_file():
            raise
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


def bin_dir() -> Path:
    return Path(os.environ.get("LONGHAND_BIN") or Path.home() / ".local" / "bin")


def env_key() -> str:
    return os.environ.get("LONGHAND_ENV_KEY") or ENV_KEY


def _read_path(root, subkey: str) -> tuple[str, int | None]:
    """A key's Path as it is written, and its type; ("", None) when none."""
    import winreg
    try:
        with winreg.OpenKey(root, subkey) as key:
            value, kind = winreg.QueryValueEx(key, "Path")
            return str(value), kind
    except OSError:
        return "", None


def _same_folder(entry: str) -> str:
    """A PATH entry as it compares: %VARS% expanded, no slash at the end, case
    and "/" as Windows takes them."""
    import winreg
    entry = winreg.ExpandEnvironmentStrings(entry.strip().strip('"'))
    return os.path.normcase(os.path.normpath(entry)) if entry else ""


def new_terminal_path() -> list[str]:
    """The PATH a terminal opened now starts with, as the registry holds it:
    the machine's, then the person's, expanded. A process keeps the PATH it
    started with, so what winget or `longhand install` added is only here."""
    import winreg
    entries = []
    for root, subkey in ((winreg.HKEY_LOCAL_MACHINE, MACHINE_ENV_KEY), (winreg.HKEY_CURRENT_USER, env_key())):
        value, _ = _read_path(root, subkey)
        entries += [winreg.ExpandEnvironmentStrings(e) for e in value.split(";") if e.strip()]
    return entries


def reachable(name: str) -> str:
    """Where a new terminal finds `name`; "" when it does not."""
    return shutil.which(name, path=os.pathsep.join(new_terminal_path())) or ""


def _broadcast_environment() -> None:
    """Tell the open windows (Explorer first: what it starts next) that the
    environment changed, as setx and the System dialog do."""
    import ctypes
    from ctypes import wintypes
    user32 = ctypes.WinDLL("user32")   # its own: the host's windll.user32 keeps its argtypes
    send = user32.SendMessageTimeoutW
    send.argtypes = (wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPCWSTR, wintypes.UINT, wintypes.UINT,
                     ctypes.POINTER(ctypes.c_size_t))
    send.restype = ctypes.c_ssize_t
    result = ctypes.c_size_t()
    HWND_BROADCAST, WM_SETTINGCHANGE, SMTO_ABORTIFHUNG = 0xFFFF, 0x001A, 0x0002
    send(HWND_BROADCAST, WM_SETTINGCHANGE, 0, "Environment", SMTO_ABORTIFHUNG, 2000, ctypes.byref(result))


def set_on_path(folder: Path, on: bool) -> bool:
    """`folder` on the person's PATH (on) or off it, everything else in the
    value left as it was written, its type kept (REG_EXPAND_SZ when there was
    none). True when the value changed. Already on the machine's PATH counts
    as on."""
    import winreg
    value, kind = _read_path(winreg.HKEY_CURRENT_USER, env_key())
    target = _same_folder(str(folder))
    entries = value.split(";") if value else []
    if on:
        machine, _ = _read_path(winreg.HKEY_LOCAL_MACHINE, MACHINE_ENV_KEY)
        if any(_same_folder(e) == target for e in entries + machine.split(";")):
            return False
        new = (value.rstrip(";") + ";" if value.strip(";") else "") + str(folder)
    else:
        kept = [e for e in entries if _same_folder(e) != target]
        if len(kept) == len(entries):
            return False
        new = ";".join(kept)
    if kind not in (winreg.REG_SZ, winreg.REG_EXPAND_SZ):
        kind = winreg.REG_EXPAND_SZ
    with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, env_key(), 0, winreg.KEY_SET_VALUE) as key:
        winreg.SetValueEx(key, "Path", 0, kind, new)
    if env_key() == ENV_KEY:
        _broadcast_environment()
    return True


def place_commands(say) -> bool:
    """A copy of each command's launcher in `bin_dir()`, and that folder on
    the person's PATH. False when one there could not be replaced; one
    `pip install -e windows` has not made is said, and left out."""
    scripts = Path(sys.executable).parent
    folder = bin_dir()
    unmade = [name for name in COMMANDS if not (scripts / f"{name}.exe").is_file()]
    if unmade:
        say(f"longhand: no {', '.join(unmade)} in {scripts}: `pip install -e windows` (from the repo) makes "
            f"{'it' if len(unmade) == 1 else 'them'}, then `longhand install` again")
    if len(unmade) == len(COMMANDS):
        return True
    folder.mkdir(parents=True, exist_ok=True)
    placed, failed = [], []
    for name in COMMANDS:
        src, dst = scripts / f"{name}.exe", folder / f"{name}.exe"
        if name in unmade:
            continue
        try:
            if dst.is_file() and dst.read_bytes() == src.read_bytes():
                placed.append(name)
                continue
            tmp = dst.with_name(dst.name + ".tmp")
            shutil.copyfile(src, tmp)
            os.replace(tmp, dst)
            placed.append(name)
        except OSError as e:
            # A copy running (`longhand` started from a terminal) cannot be replaced.
            dst.with_name(dst.name + ".tmp").unlink(missing_ok=True)
            failed.append(f"{name} ({e.strerror or e}: run `longhand install` again once it is closed)")
    if placed:
        say(f"commands → {folder} ({', '.join(placed)})")
    for problem in failed:
        say(f"longhand: not replaced: {problem}")
    try:
        if set_on_path(folder, True):
            say(f"PATH → {folder} added to yours: open a new terminal to start them by name")
    except OSError as e:
        say(f"longhand: {folder} not put on your PATH ({e.strerror or e}): add it in Settings → System → "
            "About → Advanced system settings → Environment Variables")
        return False
    return not failed


def remove_commands(say) -> None:
    """The copies away; the folder, and its place on PATH, too when nothing
    else is in it."""
    folder = bin_dir()
    for name in COMMANDS:
        path = folder / f"{name}.exe"
        try:
            path.unlink()
            say(f"removed {path}")
        except FileNotFoundError:
            pass
        except OSError as e:
            say(f"longhand: {path} not removed ({e.strerror or e}): it is running")
    try:
        if folder.is_dir() and not any(folder.iterdir()):
            folder.rmdir()
    except OSError:
        pass
    if not folder.exists() and set_on_path(folder, False):
        say(f"PATH → {folder} taken off yours")


def install(with_autostart: bool = True, out=None, with_path: bool = True) -> int:
    say = (lambda line: print(line, file=out or sys.stdout, flush=True))
    if os.name != "nt":
        say("longhand install is for Windows; on Omarchy: tools/install")
        return 2
    if with_path:
        placed = place_commands(say)
    else:
        remove_commands(say)
        placed = True
        say(f"commands → not on PATH (--no-path): they are in {Path(sys.executable).parent}")
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
    return 0 if placed else 1


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
    remove_commands(say)
    return 0
