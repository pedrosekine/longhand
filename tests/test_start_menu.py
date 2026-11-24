"""`longhand install` on Windows: the Start menu's shortcut, its icon, and
Longhand started with the session (windows/shortcuts.py) — in a Start menu,
a state folder and a registry key of the test's own. Elsewhere there is
nothing to test, and the file says so.

Run: python tests\\run_all.py start_menu
"""
import os
import pathlib
import subprocess
import sys
import tempfile
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOST = ROOT / "windows" / "longhand_host.py"
failures = 0

# A reader in another process: opens the file, says so, holds it.
HOLDER = """
import sys, time
f = open(sys.argv[1], "rb")
f.read()
print("held", flush=True)
time.sleep(float(sys.argv[2]))
"""


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def main() -> int:
    if os.name != "nt":
        print("skip: the Start menu and the Run key are Windows' (on Omarchy: tools/install)")
        return 0
    import winreg

    sys.path.insert(0, str(ROOT / "windows"))
    import shortcuts

    tmp = pathlib.Path(tempfile.mkdtemp(prefix="start-menu-test-"))
    base = rf"Software\LonghandTest-{uuid.uuid4().hex[:12]}"
    env = dict(os.environ, APPDATA=str(tmp / "appdata"), XDG_STATE_HOME=str(tmp / "state"),
               XDG_CONFIG_HOME=str(tmp / "config"), LONGHAND_RUN_KEY=base + r"\Run", QT_QPA_PLATFORM="offscreen")
    os.environ.update({k: env[k] for k in ("APPDATA", "XDG_STATE_HOME", "LONGHAND_RUN_KEY")})   # for reading back
    link = tmp / "appdata" / "Microsoft" / "Windows" / "Start Menu" / "Programs" / "Longhand.lnk"
    icon = tmp / "state" / "longhand" / "icon" / "longhand.ico"

    def host(*args):
        return subprocess.run([sys.executable, str(HOST), *args], capture_output=True, text=True, env=env, timeout=180)

    try:
        r = host("install")
        check(r.returncode == 0, "longhand install ends well: " + (r.stderr or r.stdout).strip()[-300:])
        check("Start menu" in r.stdout and "with the session" in r.stdout, "…and says what it made")

        # The icon: the launcher's, at every size Windows asks for, each drawn.
        check(icon.is_file() and shortcuts.icon_sizes(icon) == list(shortcuts.SIZES),
              f"the icon holds {', '.join(map(str, shortcuts.SIZES))} px")
        data = icon.read_bytes() if icon.is_file() else b""
        check(data.count(b"\x89PNG\r\n\x1a\n") == len(shortcuts.SIZES), "…each a picture of its own")

        # The shortcut: today's note as a window, the seal, Longhand's name for the taskbar.
        check(link.is_file(), "the shortcut is in the Start menu's Programs")
        held = shortcuts.read_shortcut(link)
        program, arguments = shortcuts.launcher()
        check(pathlib.Path(str(held.get("target"))) == pathlib.Path(program), f"it starts Longhand ({held.get('target')})")
        check(str(held.get("arguments") or "") == arguments, "…with no word more: today's note, as a window")
        check(str(held.get("icon") or "").lower().startswith(str(icon).lower()), "its icon is the one just drawn")
        check(held.get("description") == shortcuts.COMMENT, "it says what Longhand is, as the desktop entry does")
        check(held.get("appid") == shortcuts.APP_ID, f"it carries Longhand's name for the taskbar ({held.get('appid')!r})")

        # With the session: in the tray, nothing opened.
        started = shortcuts.autostart()
        check(started.endswith("--tray") and pathlib.Path(program).name in started, f"the session starts it in the tray ({started})")

        # Explorer reads the icon to draw the shortcut: an install while
        # something holds it open waits a moment for it, and one that never
        # lets go leaves the icon there as it was, rather than failing.
        def holding(seconds):
            p = subprocess.Popen([sys.executable, "-c", HOLDER, str(icon), str(seconds)], stdout=subprocess.PIPE, text=True)
            p.stdout.readline()
            return p

        before = icon.stat().st_mtime_ns
        reader = holding(2.0)
        r = host("install")
        reader.wait()
        check(r.returncode == 0 and icon.stat().st_mtime_ns != before and shortcuts.icon_sizes(icon) == list(shortcuts.SIZES),
              "install while a reader holds the icon for a moment: the new icon lands")
        before = icon.stat().st_mtime_ns
        reader = holding(30.0)
        try:
            r = host("install")
        finally:
            reader.kill()
            reader.wait()
        check(r.returncode == 0 and icon.stat().st_mtime_ns == before and not icon.with_name(icon.name + ".tmp").exists(),
              "…and with a reader that never lets go, the icon there stays: " + (r.stderr or "").strip()[-300:])

        # Again changes nothing; --no-autostart keeps the shortcut and takes the start away.
        r = host("install", "--no-autostart")
        check(r.returncode == 0 and link.is_file() and shortcuts.autostart() == "", "install --no-autostart: the shortcut, and no start with the session")

        host("install")
        r = host("uninstall")
        check(r.returncode == 0 and not link.exists() and not icon.exists() and shortcuts.autostart() == "",
              "uninstall takes the shortcut, the icon and the start away")
        check(host("uninstall").returncode == 0, "…and a second time has nothing to do")
    finally:
        for key in (base + r"\Run", base):
            try:
                winreg.DeleteKey(winreg.HKEY_CURRENT_USER, key)
            except OSError:
                pass

    print(f"\n{failures} failure(s)")
    return failures


if __name__ == "__main__":
    sys.exit(main())
