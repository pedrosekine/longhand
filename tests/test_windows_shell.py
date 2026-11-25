"""What the shell and Hyprland do for Longhand, as the Windows host does it:

- the keys sheet's six keys from anywhere (windows/winkeys.py, in
  hyprkeys.py's words), and the agent's manual reading them;
- `hyprctl eval` answered inside the host (windows/compositor.py): the
  window raised, the pointer put, the keys let go while the sheet listens;
- Windows' palette under the theme's colors.toml (windows/palette.py);
- the bell at the shell's volume, Windows' Do Not Disturb asked, and a
  notification through the running Longhand (play_sound.py, notify.py);
- a window's place kept across restarts, the tray's seal in the theme's
  colours (host_api.py);
- the tray saying what the bar's page glyph says: replies waiting, and what
  the agent proposes (windows/Main.qml).

Elsewhere the shell and Hyprland do these, and there is nothing here to test.

Run: python tests\\run_all.py windows_shell
"""
import json
import os
import pathlib
import re
import sys
import tempfile
import time
import wave
from array import array

ROOT = pathlib.Path(__file__).resolve().parent.parent
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def main() -> int:
    if os.name != "nt":
        print("skip: the Windows host's stand-ins for the shell and Hyprland")
        return 0
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="windows-shell-test-"))
    os.environ["XDG_CONFIG_HOME"] = str(tmp / "config")
    os.environ["XDG_STATE_HOME"] = str(tmp / "state")
    os.environ["LONGHAND_SILENT"] = "1"
    os.environ["QT_QPA_PLATFORM"] = "offscreen"
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    sys.path.insert(0, str(ROOT / "windows"))
    sys.path.insert(0, str(ROOT / "agent"))

    keys(tmp)
    sounds(tmp)

    from PySide6.QtGui import QGuiApplication
    app = QGuiApplication(sys.argv[:1])
    inside(app)
    palette_file(tmp)
    places_and_icon(tmp)
    placed_again(app)
    notify_through_longhand(app)
    tray(app, tmp)
    print(f"\n{failures} failure(s)")
    return 1 if failures else 0


# ------------------------------------------------------------ the six keys

def keys(tmp):
    import winkeys
    import qs_io

    st = winkeys.state()
    page = st["actions"][0]
    check(st["owned"] and [a["id"] for a in st["actions"]] == ["page", "alongside", "deadlines", "pomoPopup", "pomoToggle", "pomoSkip"],
          "the sheet is told Longhand keeps the six already, in hyprkeys.py's order")
    check(page["keys"] == ["Alt+Super+="] and page["own"] == ["Alt+Super+="], f"…each on its own key, as the sheet writes one ({page})")

    for written, sheet in (("Win+Alt+=", "Alt+Super+="), ("Alt+Win+\\", "Alt+Super+\\"), ("Win+Shift+P", "Shift+Super+P"),
                           ("Win+Ctrl+F12", "Ctrl+Super+F12"), ("Win+Alt+Space", "Alt+Super+Space"), ("Win+Shift+5", "Super+5")):
        back, why = winkeys.from_sheet(winkeys.to_sheet(written))
        check(winkeys.to_sheet(written) == sheet and winkeys.parse(back) == winkeys.parse(written.replace("Shift+5", "5")),
              f"{written} is {sheet} to the sheet, and the same key back ({back or why})")
    check(winkeys.from_sheet("Ctrl+Alt+K")[0] == "" and "Win" in winkeys.from_sheet("Ctrl+Alt+K")[1],
          "a key without Win is refused, and why is said")
    check(winkeys.from_sheet("Alt+Super+?")[0] == "", "a key Windows cannot keep is refused")

    # Moving: the file says only what differs, and a key another of the six
    # had moves from it.
    free = winkeys.free
    winkeys.free = lambda key: True          # no asking Windows here: another Longhand may hold these keys
    try:
        st = winkeys.set_keys("alongside", ["Alt+Super+F9"])
        on_file = json.loads(winkeys.keys_file().read_text(encoding="utf-8"))
        check(not st.get("error") and on_file == {"alongside": "Win+Alt+F9"}, f"a moved key is written, and only it ({on_file})")
        st = winkeys.set_keys("page", ["Alt+Super+F9"])
        by = {a["id"]: a["keys"] for a in st["actions"]}
        check(by["page"] == ["Alt+Super+F9"] and by["alongside"] == [] and "Page alongside" in st["note"],
              f"a key another action had moves here, and the sheet is told from where ({st['note']})")
        st = winkeys.set_keys("page", ["Alt+Super+="], add=True)
        check({a["id"]: a["keys"] for a in st["actions"]}["page"] == ["Alt+Super+F9", "Alt+Super+="], "--add keeps the key it had")
        st = winkeys.set_keys("pomoSkip", [])
        check({a["id"]: a["keys"] for a in st["actions"]}["pomoSkip"] == [] and
              json.loads(winkeys.keys_file().read_text(encoding="utf-8"))["pomoSkip"] == "", "no key at all is written as \"\"")
        for aid in winkeys.ORDER:
            winkeys.set_keys(aid, [winkeys.to_sheet(winkeys.DEFAULTS[aid])])
        check(json.loads(winkeys.keys_file().read_text(encoding="utf-8")) == {}, "each back on its own key, the file says nothing")
        st = winkeys.set_keys("page", ["Ctrl+Alt+K"])
        check(st.get("error") and st["actions"][0]["keys"] == ["Alt+Super+="], "a refused key changes nothing")
        winkeys.keys_file().write_text(json.dumps({"page": ["Win+F9", "Win+Alt+="]}), encoding="utf-8")
        check(winkeys.state()["actions"][0]["keys"] == ["Super+F9", "Alt+Super+="], "a list written by hand is read")
    finally:
        winkeys.free = free
        winkeys.keys_file().unlink(missing_ok=True)

    for path in ("/C:/Users/someone/longhand/plugin-page/hyprkeys.py", "C:/Users/someone/longhand/plugin-page/hyprkeys.py"):
        program, args = qs_io.resolve(["python3", path, "set", "page", "Alt+Super+F9"])
        check(pathlib.Path(args[0]).name == "winkeys.py" and args[1:] == ["set", "page", "Alt+Super+F9"],
              f"the sheet's hyprkeys.py ({path[:4]}…) is answered by winkeys.py")

    import manual
    k = manual.keys(tmp / "config")
    check(k.get("sys:page") == ["Win+Alt+="] and k.get("sys:pomoToggle") == ["Win+Alt+P"],
          f"the agent's manual says Windows' keys, Win first ({k.get('sys:page')})")


# ------------------------------------------------------------ hyprctl

class FakeKeys:
    def __init__(self):
        self.said = []

    def register(self):
        self.said.append("register")

    def release(self):
        self.said.append("release")


def inside(app):
    import compositor
    import qs_io
    from PySide6.QtCore import QEventLoop, QPoint, QTimer
    from PySide6.QtGui import QCursor, QWindow

    page = (ROOT / "plugin-page" / "Page.qml").read_text(encoding="utf-8")
    for bit in ('hl.dsp.focus({ window = "title:^', 'hl.get_monitor("', "x = m.position.x + ", "x = w.at.x + ",
                'hl.define_submap("longhand-keys"', 'get_current_submap() == "longhand-keys"'):
        check(bit in page, f"the page still asks Hyprland in the words read here: {bit}")

    keys = FakeKeys()
    compositor.KEYS = keys
    code, _out, _err = compositor.hyprctl(["eval", 'hl.define_submap("longhand-keys", function() end); hl.dispatch(hl.dsp.submap("longhand-keys"))'])
    check(code == 0 and keys.said == ["release"] and compositor.listening(), "while the sheet listens, the host lets go of its keys")
    compositor.hyprctl(["eval", 'if hl.get_current_submap() == "longhand-keys" then hl.dispatch(hl.dsp.submap("reset")) end'])
    check(keys.said == ["release", "register"] and not compositor.listening(), "…and takes them back when it stops")
    compositor.KEYS = None

    w = QWindow()
    w.setTitle("Page — today's note")
    w.setGeometry(100, 120, 400, 300)
    w.show()
    other = QWindow()
    other.setTitle("something else")
    other.setGeometry(300, 300, 200, 200)
    other.show()
    other.requestActivate()
    app.processEvents()
    compositor.hyprctl(["eval", 'hl.dispatch(hl.dsp.focus({ window = "title:^Page — today\'s note$" }))'])
    loop_until(app, lambda: QGuiApplication_focus() is w, 2.0)
    check(QGuiApplication_focus() is w, "the page's window, behind another, is brought forward and given the keys")
    # Put in the taskbar, it comes back as it was put there (a second
    # `longhand`, Win+Alt+\, the Start menu: all come_forward). Maximized
    # first, Windows keeps both states while it is down; showNormal brought
    # it back at its old size.
    from PySide6.QtCore import Qt
    WS = Qt.WindowState
    for before, label in ((WS.WindowNoState, "at its size"), (WS.WindowMaximized, "maximized")):
        w.setWindowStates(before)
        app.processEvents()
        w.setWindowStates(before | WS.WindowMinimized)
        other.requestActivate()
        loop_until(app, lambda: QGuiApplication_focus() is other, 1.0)
        compositor.hyprctl(["eval", 'hl.dispatch(hl.dsp.focus({ window = "title:^Page — today\'s note$" }))'])
        loop_until(app, lambda: QGuiApplication_focus() is w, 2.0)
        check(w.windowStates() == before and QGuiApplication_focus() is w,
              f"the page's window, in the taskbar, comes back {label}, with the keys ({w.windowStates()})")
    w.setWindowStates(WS.WindowNoState)
    app.processEvents()
    check(not compositor.come_forward(None), "no such window: nothing to bring forward")
    compositor.hyprctl(["eval", 'local w = hl.get_window("title:^Page — today\'s note$"); '
                                'if w and w.active then hl.dispatch(hl.dsp.cursor.move({ x = w.at.x + 30, y = w.at.y + 40 })) end'])
    at = QCursor.pos()
    want = w.mapToGlobal(QPoint(30, 40))
    check(at == want or QGuiApplication_platform() == "offscreen" and at in (want, QPoint(0, 0)),
          f"the pointer is put where the page asks, from the window's corner ({at.x()},{at.y()} for {want.x()},{want.y()})")
    # The overlay's pointer, on every screen, named as the page names it
    # (only [A-Za-z0-9_.-]: a laptop's "\\.\DISPLAY1" comes as ".DISPLAY1",
    # matched no screen, and the pointer stayed put there).
    check(compositor.plain("\\\\.\\DISPLAY1") == ".DISPLAY1", "a screen's name, as the page writes it")
    from PySide6.QtGui import QGuiApplication
    for s in QGuiApplication.screens():
        compositor.hyprctl(["eval", f'local m = hl.get_monitor("{compositor.plain(s.name())}"); '
                                    'if m then hl.dispatch(hl.dsp.cursor.move({ x = m.position.x + 40, y = m.position.y + 50 })) end'])
        at, want = QCursor.pos(), s.geometry().topLeft() + QPoint(40, 50)
        check(at == want or QGuiApplication_platform() == "offscreen",
              f"the overlay's pointer goes to its own screen, {s.name()!r} ({at.x()},{at.y()} for {want.x()},{want.y()})")
    code, _out, err = compositor.hyprctl(["eval", "hl.exec_cmd('rm -rf /')"])
    check(code == 1 and "not Hyprland" in err, "anything else asked of Hyprland is refused, as without Hyprland")

    # Through a Process, as the page asks it: no program started.
    qs_io.INSIDE["hyprctl"] = compositor.hyprctl
    p = qs_io.Process()
    err_col = qs_io.StdioCollector()
    p._set_stderr(err_col)
    ended = []
    p.exited.connect(lambda code, status: ended.append(code))
    p._set_command(["hyprctl", "eval", "nothing the page says"])
    p._set_running(True)
    loop_until(app, lambda: ended, 2.0)
    check(ended == [1] and "not Hyprland" in err_col.property("text") and not p._get_running(),
          f"a Process of hyprctl ends as a program would, its words on stderr ({ended})")
    w.close()
    other.close()
    restart_when_finished(app)


KEEP = []     # the Processes made here, alive until the end


def restart_when_finished(app):
    """As Quickshell (asked on Omarchy, 2026-11-24): when the output's
    `streamFinished` is heard, `running` already reads false, and setting it
    true there starts the process again. The page asks for its next check
    that way (`checkDone`); the host once dropped it, and the page waited
    eight seconds for a check that never ran (tests/page/run.py, section 5)."""
    import qs_io
    p = qs_io.Process()
    out = qs_io.StdioCollector()
    p._set_stdout(out)
    seen = []

    def finished():
        seen.append((out.property("text").strip(), p._get_running()))
        if len(seen) < 3:
            p._set_running(True)
    out.streamFinished.connect(lambda: finished())
    p._set_command([sys.executable, "-c", "print('hi')"])
    p._set_running(True)
    loop_until(app, lambda: len(seen) >= 3 and not p._get_running(), 20.0)
    check(seen == [("hi", False)] * 3,
          f"a Process started again from its own streamFinished runs again, not running when it is heard ({seen})")

    KEEP.append((p, out))
    restart_while_ending(app)


def restart_while_ending(app):
    """`running = false`, a new command, `running = true` while the old
    process is still ending: the new one runs once it has ended (as
    Quickshell, asked on Omarchy; the page leaves Hyprland's submap so,
    `hyprListen`, and the host once dropped it)."""
    import qs_io
    p = qs_io.Process()
    out = qs_io.StdioCollector()
    p._set_stdout(out)
    said = []
    out.streamFinished.connect(lambda: said.append(out.property("text").strip()))
    p._set_command([sys.executable, "-c", "import time; time.sleep(30); print('first')"])
    p._set_running(True)
    loop_until(app, lambda: p._proc is not None and int(p._proc.processId()) > 0, 10.0)
    p._set_running(False)
    p._set_command([sys.executable, "-c", "print('second')"])
    p._set_running(True)
    loop_until(app, lambda: "second" in said and not p._get_running(), 20.0)
    check(said[-1:] == ["second"] and "first" not in said,
          f"stopped and started again before it ended: the new command runs once the old one has ({said})")
    KEEP.append((p, out))


def QGuiApplication_focus():
    from PySide6.QtGui import QGuiApplication
    return QGuiApplication.focusWindow()


def QGuiApplication_platform():
    from PySide6.QtGui import QGuiApplication
    return QGuiApplication.platformName()


def loop_until(app, cond, seconds):
    end = time.monotonic() + seconds
    while time.monotonic() < end and not cond():
        app.processEvents()
        time.sleep(0.01)


# ------------------------------------------------------------ palette

def palette_file(tmp):
    import palette
    import qs_io
    f = qs_io.FileView()
    f._set_path((tmp / "home" / ".local" / "state" / "omarchy" / "current" / "theme" / "colors.toml").as_posix())
    text, _err = f._read()
    keys = dict(re.findall(r'^(\w+) = "(#[0-9a-f]{6})"$', text or "", re.M))
    check(set(keys) >= {"red", "yellow", "orange", "green", "cyan", "blue", "magenta"} and len(set(keys.values())) == len(keys),
          f"where no theme is, its colors.toml is Windows' palette, a colour for each role ({sorted(keys)})")
    check("accent" not in keys and "background" not in keys, "…the accent and the ground left to the shell's palette, which follows Windows live")
    check('green = "#0f7b0f"' in palette.colors_toml(False) and 'green = "#6ccb5f"' in palette.colors_toml(True),
          "light and dark have each their own")
    real = tmp / "theme" / ".local" / "state" / "omarchy" / "current" / "theme" / "colors.toml"
    real.parent.mkdir(parents=True)
    real.write_bytes(b'accent = "#123456"\n')
    f._set_path(real.as_posix())
    check(f._read()[0] == 'accent = "#123456"\n', "a theme's own colors.toml, where there is one, is read as it is")


# ------------------------------------------------------------ sound, notifications

def sounds(tmp):
    import notify
    import play_sound
    loud = tmp / "loud.wav"
    with wave.open(str(loud), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(8000)
        w.writeframes(array("h", [10000, -20000, 30000, 0]).tobytes())
    import io
    data = play_sound.quieter(str(loud), 0.6, lead=0)
    with wave.open(io.BytesIO(data), "rb") as w:
        got = list(array("h", w.readframes(w.getnframes())))
    check(got == [6000, -12000, 18000, 0], f"the bell is played at six tenths, as pw-play --volume=0.6 ({got})")
    # A sleeping sound chip loses what plays while it wakes: the whole tick,
    # until it was given silence to wake in.
    with wave.open(io.BytesIO(play_sound.quieter(str(loud), 0.6)), "rb") as w:
        got = list(array("h", w.readframes(w.getnframes())))
    lead = int(8000 * play_sound.LEAD)
    check(play_sound.LEAD >= 0.25 and got[:lead] == [0] * lead and got[lead:] == [6000, -12000, 18000, 0],
          f"the sound comes after {play_sound.LEAD}s of silence, for the sound chip to wake")
    check(isinstance(play_sound.silenced(), bool), "Windows is asked whether notifications are silenced")
    check(play_sound.main([str(tmp / "none.wav")]) in (0, 1) and play_sound.main([]) == 2, "a missing file is not a fault")

    s = notify.script("Pomodoro", "Focus done'; Remove-Item C:\\ -Recurse #", notify.POWERSHELL_ID)
    check("Remove-Item" not in s and "Focus done" not in s, "a toast's words reach PowerShell as base64, never as code")


def notify_through_longhand(app):
    import notify
    from PySide6.QtNetwork import QLocalServer
    check(notify.to_longhand("Pomodoro", "x") is False, "with no Longhand running, pomo's notification is not sent to one")
    server = QLocalServer()
    QLocalServer.removeServer(notify.instance_name())
    check(server.listen(notify.instance_name()), "(a Longhand stands in, listening under its name)")
    heard = []

    def on_new():
        sock = server.nextPendingConnection()
        sock.readyRead.connect(lambda: heard.append(bytes(sock.readAll()).decode("utf-8")))
        heard.append(bytes(sock.readAll()).decode("utf-8"))
    server.newConnection.connect(on_new)
    # From a thread, as pomo is another process: a pipe's write waits for
    # its reader, which is this loop.
    import threading
    result = []
    t = threading.Thread(target=lambda: result.append(notify.to_longhand("Pomodoro", "Focus done — break time")), daemon=True)
    t.start()
    loop_until(app, lambda: "".join(heard).endswith("\n") and result, 5.0)
    sent = bool(result and result[0])
    said = json.loads("".join(heard) or "{}")
    check(sent and said == {"do": "notify", "title": "Pomodoro", "body": "Focus done — break time"},
          f"with Longhand running, pomo's notification is handed to it, for the tray to say ({said})")
    server.close()


# ------------------------------------------------------------ windows, icon

def places_and_icon(tmp):
    import host_api
    host = host_api.Host()
    host.keepPlace("Page — today's note", {"x": 10, "y": 20, "width": 700, "height": 800})
    kept = host.savedPlace("Page — today's note") or {}
    check({k: kept.get(k) for k in ("x", "y", "width", "height")} == {"x": 10, "y": 20, "width": 700, "height": 800},
          "where the page's window was left is kept in the state folder, and given back")
    from PySide6.QtGui import QGuiApplication
    check(kept.get("screen") in [s.name() for s in QGuiApplication.screens()],
          f"…with the screen it is on, for the window to be put there first ({kept.get('screen')!r})")
    check(host.workArea().get("screen") == host.screenHere(), "the room by the clock names its screen")
    host.keepPlace("gone", {"x": 90000, "y": 90000, "width": 700, "height": 800})
    check(host.savedPlace("gone") is None, "a place no screen has any more is not given back")
    check(host.savedPlace("never") is None, "a window never placed has no place")
    check((tmp / "state" / "longhand" / "windows.json").is_file(), "…kept beside Longhand's other state, not in the vault")
    check(isinstance(host.screenHere(), str) and host.workArea()["width"] >= 0, "the screen the pointer is on is named")

    a = host.themedIcon("#ff202020", "#f3f3f3", "#4cc2ff")
    b = host.themedIcon("#f9f9f9", "#1b1b1b", "#005fb8")
    from PySide6.QtCore import QUrl
    pa, pb = pathlib.Path(QUrl(a).toLocalFile()), pathlib.Path(QUrl(b).toLocalFile())
    svg = pb.read_text(encoding="utf-8") if pb.is_file() else ""
    check(a != b and pb.is_file() and not pa.exists(), "the tray's seal is drawn anew for new colours, the old one let go")
    check('fill="#f9f9f9"' in svg and 'data-longhand-status="theme-derived"' in svg and 'data-longhand-logo="a2-open-cuts"' in svg,
          "…the tile in the mode's ground, the canonical seal's shape kept")
    check(host.themedIcon("#f9f9f9", "#1b1b1b", "#005fb8") == b, "the same colours, the same picture")

    # The timer's and the deadlines' own tray icons: a word on the tile.
    colours = ("#ff202020", "#f3f3f3", "#3a0a08", "#9a9a9a", "#ff99a4")   # an accent too dark to read there
    t = host.trayGlyph("timer", "25", "accent", *colours)
    late = host.trayGlyph("deadlines", "!", "urgent", *colours)
    odd = host.trayGlyph("deadlines", "<&>", "text", *colours)
    files = [pathlib.Path(QUrl(u).toLocalFile()) for u in (t, late, odd)]
    texts = [f.read_text(encoding="utf-8") if f.is_file() else "" for f in files]
    check(all(f.is_file() and f.name.startswith("glyph-") for f in files) and pb.is_file(),
          "the timer's and the deadlines' icons are drawn beside the seal's, which stays")
    check(">25</text>" in texts[0] and 'fill="#202020"' in texts[0] and 'fill="#3a0a08"' not in texts[0],
          "…the minutes on the mode's ground, the accent moved to read on it, as the seal's")
    check('fill="#ff99a4"' in texts[1] and "&lt;&amp;&gt;" in texts[2], "…late in the urgent colour; the word escaped")
    check(host.trayGlyph("timer", "25", "accent", *colours) == t, "the same word and colours, the same picture")

    # A new picture Windows will not let be put in place (its temporary file
    # held past the host's brief tries): each icon keeps the picture it has,
    # no exception reaches the window's thread, nothing is left behind.
    def refused(src, dst, waits=None):
        raise PermissionError(5, "Access is denied", str(dst))
    kept = host_api.replace
    host_api.replace = refused
    try:
        timer_now = host.trayGlyph("timer", "24", "accent", *colours)
        seal_now = host.themedIcon("#ff000000", "#ffffff", "#ff0000")
    finally:
        host_api.replace = kept
    tray_dir = pb.parent
    check(timer_now == t and seal_now == b and pb.is_file(),
          "a tray picture that cannot be put in place: the timer and the seal keep the ones they show")
    check(not list(tray_dir.glob("*.tmp")), "…and no temporary file is left in the tray's folder")
    check(host.trayGlyph("timer", "24", "accent", *colours) not in ("", t), "…and the next minute draws again")


def placed_again(app):
    """The page's window and a popup by the clock, put on their screen and
    placed again a moment after they are shown: moved onto a screen scaled
    otherwise, Windows shifts a window as the scale changes under it
    (2026-11-24, the overlay 282 px off on a monitor at 150% beside a
    laptop at 125%). Here the shift is made by hand, just after showing."""
    import host_api
    from PySide6.QtCore import QUrl
    from PySide6.QtQml import QQmlComponent, QQmlEngine

    host = host_api.Host()
    host.keepPlace("placed again", {"x": 30, "y": 40, "width": 420, "height": 320})
    engine = QQmlEngine()
    engine.addImportPath(str(ROOT / "windows" / "shim"))
    component = QQmlComponent(engine)
    component.setData(b"""
import QtQuick
import Quickshell
import qs.Ui
Item {
  property var page: FloatingWindow { title: "placed again"; implicitWidth: 420; implicitHeight: 320 }
  property var popup: KeyboardPanel { contentWidth: 220; contentHeight: 160 }
}
""", QUrl.fromLocalFile(str(ROOT / "tests" / "placed_again.qml")))
    holder = component.create()
    check(holder is not None, f"the page's window and a popup load ({[e.toString() for e in component.errors()][:2]})")
    if holder is None:
        return
    win, popup = holder.property("page"), holder.property("popup")

    win.setVisible(True)
    kept = host.savedPlace("placed again")
    check(win.screen().name() == kept["screen"], f"the page's window is put on the screen it was left on ({win.screen().name()!r})")
    win.setX(win.x() + 282)                        # as Windows shifts it
    loop_until(app, lambda: win.x() == 30, 1.0)
    got = [win.x(), win.y(), win.width(), win.height()]
    check(got == [30, 40, 420, 320], f"…and placed again where it was left, after the shift ({got})")

    popup.setProperty("open", True)
    area = host.workArea()
    check(popup.screen().name() == area["screen"], f"the popup is put on the pointer's screen ({popup.screen().name()!r})")
    popup.setX(popup.x() - 282)
    margin = popup.property("margin")
    corner = lambda: [popup.x() + popup.width(), popup.y() + popup.height()]  # noqa: E731
    want = [area["x"] + area["width"] - margin, area["y"] + area["height"] - margin]
    loop_until(app, lambda: corner() == want, 1.0)
    check(corner() == want, f"…and placed again in the corner by the clock, after the shift ({corner()} for {want})")
    popup.setProperty("open", False)
    win.setVisible(False)
    del holder, win, popup
    engine.deleteLater()


# ------------------------------------------------------------ the tray

def tray(app, tmp):
    """Main.qml, loaded as the host loads it: the tray's line for the agent."""
    import longhand_host
    import host_api  # noqa: F401
    import qs_io  # noqa: F401
    import qs_wayland  # noqa: F401
    from PySide6.QtCore import QUrl
    from PySide6.QtQml import QQmlAbstractUrlInterceptor, QQmlApplicationEngine

    box = longhand_host.sandbox(tmp / "box")
    state = pathlib.Path(os.environ["XDG_STATE_HOME"]) / "longhand"
    state.mkdir(parents=True, exist_ok=True)
    (state / "proposals.json").write_text(json.dumps({"items": [{"status": "open"}, {"status": "open"}, {"status": "done"}]}),
                                          encoding="utf-8")
    day = box["vault"] / "agents" / "longhand" / "daily"
    day.mkdir(parents=True, exist_ok=True)
    (day / f"{time.strftime('%Y-%m-%d')}.json").write_text(json.dumps({"blocks": {
        "a": {"state": "reply", "read": False}, "b": {"state": "reply", "read": True}}}), encoding="utf-8")

    class Shared(QQmlAbstractUrlInterceptor):
        def intercept(self, url, kind):
            if url.isLocalFile() and url.fileName() == "Store.js" and "/plugin-deadline/" in url.path():
                return QUrl.fromLocalFile(str(ROOT / "plugin-page" / "Store.js"))
            return url

    warnings = []
    engine = QQmlApplicationEngine()
    shared = Shared()
    engine.addUrlInterceptor(shared)
    engine.warnings.connect(lambda ws: warnings.extend(w.toString() for w in ws))
    engine.addImportPath(str(ROOT / "windows" / "shim"))
    ctx = engine.rootContext()
    ctx.setContextProperty("hostBridge", host_api.BRIDGE)
    ctx.setContextProperty("hostResident", False)
    ctx.setContextProperty("hostKeepAlive", True)
    engine.load(QUrl.fromLocalFile(str(ROOT / "windows" / "Main.qml")))
    roots = engine.rootObjects()
    check(bool(roots), f"Main.qml loads ({warnings[:3]})")
    if not roots:
        return
    host = roots[0]
    loop_until(app, lambda: host.property("agentLine") == "1 reply waiting · 2 from the agent, in the dashboard", 8.0)
    check(host.property("agentLine") == "1 reply waiting · 2 from the agent, in the dashboard",
          f"the tray says a reply is waiting and what the agent proposes, as the bar's glyph does ({host.property('agentLine')!r})")
    (state / "proposals.json").write_text(json.dumps({"items": []}), encoding="utf-8")
    loop_until(app, lambda: host.property("agentLine") == "1 reply waiting", 5.0)
    check(host.property("agentLine") == "1 reply waiting", "…and follows the file as it changes")
    check(not [w for w in warnings if "Main.qml" in w], f"no warning from Main.qml ({[w for w in warnings if 'Main.qml' in w][:2]})")
    del roots
    engine.deleteLater()


if __name__ == "__main__":
    sys.exit(main())
