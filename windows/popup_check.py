"""The bar's two popups, asked of the running host: do they open by the
clock, take keys, and do what they do on Omarchy?

    python windows/longhand_host.py --sandbox DIR --check OUT.json --popups [--shot OUT.png]

The timer's is opened, a length typed into it as on a microwave (2500 is
25:00) and started; Tab goes over to the deadlines', where one of two
deadlines put into the sandbox's store is ticked with `d`; Esc puts it
away. Keys go in as key events to the popup's own window. With --shot,
three pictures are kept beside the name given: -timer, -running, -deadlines.
"""
from __future__ import annotations

import json
import subprocess
import time
from pathlib import Path

from PySide6.QtCore import QCoreApplication, QEvent, QObject, Qt, QTimer
from PySide6.QtGui import QKeyEvent
from PySide6.QtQml import QQmlExpression, qmlContext

import qs_io

HERE = Path(__file__).resolve().parent
REPO = HERE.parent


def run(app, engine, box, args, warnings):
    root = engine.rootObjects()[0]
    ctx = qmlContext(root)
    out = {"loaded": True, "steps": [], "ok": False}
    # Held on purpose: let go of, PySide deletes the root item and all in it.
    state = {"t0": time.monotonic(), "last": "", "root": root}

    def ev(expr):
        e = QQmlExpression(ctx, root, expr)
        got = e.evaluate()
        if isinstance(got, tuple):
            got = got[0]
        if e.hasError():
            state["last"] = e.error().toString()
            return None
        return got

    def popup(name):
        """The popup's window, when it is on screen."""
        return next((w for w in app.allWindows() if w.isVisible() and w.title() == name), None)

    def give_keyboard(w):
        """The popup made the window Windows sends keys to. Opened from the
        tray's menu or a global key, Longhand is the program in front and
        Windows lets it; this check is started in the background, where it
        does not, so it asks as the program in front would."""
        if app.platformName() != "windows" or w.isActive():
            return w.isActive()
        import ctypes
        u32, k32 = ctypes.windll.user32, ctypes.windll.kernel32
        front = u32.GetWindowThreadProcessId(u32.GetForegroundWindow(), None)
        mine = k32.GetCurrentThreadId()
        u32.AttachThreadInput(mine, front, True)
        u32.SetForegroundWindow(ctypes.c_void_p(int(w.winId())))
        u32.AttachThreadInput(mine, front, False)
        w.requestActivate()
        for _ in range(20):
            app.processEvents()
            if w.isActive():
                break
            time.sleep(0.05)
        return w.isActive()

    def key(w, k, ch="", mods=Qt.KeyboardModifier.NoModifier):
        for kind in (QEvent.Type.KeyPress, QEvent.Type.KeyRelease):
            QCoreApplication.sendEvent(w, QKeyEvent(kind, k, mods, ch))
        app.processEvents()

    def step(name, **facts):
        out["steps"].append({"step": name, "at": round(time.monotonic() - state["t0"], 2), **facts})

    def picture(w, name):
        if not args.shot or w is None:
            return
        target = args.shot.with_name(f"{args.shot.stem}-{name}{args.shot.suffix or '.png'}")
        img = w.grabWindow()
        step("shot " + name, saved=img.save(str(target)), size=[img.width(), img.height()])

    def finish(ok):
        out["ok"] = ok
        out["warnings"] = warnings
        out["couldNotStart"] = sorted(set(qs_io.LOG))
        args.check.write_text(json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8")
        app.quit()

    def wait(cond, then, what, limit=12.0):
        t0 = time.monotonic()

        def poll():
            try:
                good = cond()
            except Exception as e:      # noqa: BLE001 — said in the step, the check goes on to its end
                good = False
                state["last"] = repr(e)
            if good:
                then()
            elif time.monotonic() - t0 > limit:
                step("gave up: " + what, last=state["last"],
                     windows=[[w.title(), w.isVisible()] for w in app.allWindows()])
                finish(False)
            else:
                QTimer.singleShot(100, poll)
        poll()

    def pomo_cli(*words):
        return subprocess.run([qs_io.python(), str(REPO / "cli" / "pomo.py"), *words], capture_output=True, text=True,
                              encoding="utf-8", errors="replace", timeout=30,
                              creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))

    # --- the two widgets, loaded as they are
    def loaded():
        return ev("pomo !== null && deadlines !== null") is True and ev("pomo.phase") == "idle"

    def seed():
        step("widgets loaded", timerLabel=ev("pomo.labelText"), deadlineLabel=ev("deadlines.labelText"))
        added = [pomo_cli("deadline", "add", "Essay draft", "--project", "stats", "tomorrow", "17:00"),
                 pomo_cli("deadline", "add", "Lab report", "next", "friday", "09:00")]
        step("two deadlines added", exits=[r.returncode for r in added], said=[(r.stdout + r.stderr).strip()[-120:] for r in added])
        wait(lambda: ev("deadlines.items.length") == 2, open_timer, "the store's two deadlines in the service")

    # --- the timer's popup
    def open_timer():
        step("deadlines read", label=ev("deadlines.labelText"), tip=ev("deadlines.tooltipText"))
        ev('popup("timer")')
        wait(lambda: popup("longhand.pomo") is not None and ev("pomoPanel.opened") is True
             and popup("longhand.pomo").height() > 120, timer_open, "the timer's popup on screen, at its size")

    def timer_open():
        w = popup("longhand.pomo")
        area = app.primaryScreen().availableGeometry()
        auto_row = w.findChild(QObject, "pomoAutoRow") if w is not None else None
        step("timer popup open", size=[w.width(), w.height()], at=[w.x(), w.y()],
             workArea=[area.x(), area.y(), area.width(), area.height()],
             inTheCorner=abs((w.x() + w.width()) - (area.x() + area.width())) <= 40
             and abs((w.y() + w.height()) - (area.y() + area.height())) <= 40,
             autoRowWidth=round(auto_row.property("width"), 1) if auto_row is not None else 0,
             flags=int(w.flags()), entry=ev("pomoPanel.entryText()"), hasKeyboard=give_keyboard(w))
        for ch in "2500":
            key(w, Qt.Key(ord(ch)), ch)
        wait(lambda: ev("pomoPanel.entryDigits") == "2500", typed, "the length typed into the timer")

    def typed():
        w = popup("longhand.pomo")
        step("length typed", entry=ev("pomoPanel.entryText()"))
        picture(w, "timer")
        key(w, Qt.Key.Key_Return, "\r")
        wait(lambda: ev("pomo.phase") == "focus" and ev("pomo.runStatus") == "running", running, "a focus session running", 15.0)

    def running():
        w = popup("longhand.pomo")
        step("focus started", remaining=ev("pomo.remaining"), label=ev("pomo.labelText"), popupStillOpen=w is not None)
        QTimer.singleShot(500, lambda: (picture(popup("longhand.pomo"), "running"), to_deadlines()))

    # --- Tab: the widget beside it
    def to_deadlines():
        key(popup("longhand.pomo"), Qt.Key.Key_Tab, "\t")
        wait(lambda: popup("longhand.deadline") is not None and popup("longhand.pomo") is None, deadlines_open,
             "Tab going over to the deadlines' popup")

    def deadlines_open():
        w = popup("longhand.deadline")
        give_keyboard(w)
        step("deadlines popup open", size=[w.width(), w.height()], rows=ev("deadlinePanel.shown.length"),
             titles=ev('deadlinePanel.shown.map(function (i) { return i.title }).join(" | ")'))
        key(w, Qt.Key.Key_Down)
        wait(lambda: ev("deadlinePanel.cursorActive") is True, tick, "the cursor on the first deadline")

    def tick():
        w = popup("longhand.deadline")
        first = ev("deadlinePanel.shown[0].title")
        key(w, Qt.Key.Key_D, "d")
        # The store's file, not the popup's list: the list shows a tick at
        # once, before it is written (2026-11-26, plugin-deadline/Service.qml).
        wait(lambda: store_done() == 1, lambda: ticked(first), "the deadline under the cursor ticked, in the store", 15.0)

    def store_lines():
        store = box["state"] / "longhand" / "deadlines.tsv"
        return store.read_text(encoding="utf-8").splitlines() if store.exists() else []

    def store_done():
        return sum("\tdone\t" in l or l.rstrip().endswith("\tdone") for l in store_lines())

    def ticked(first):
        lines = store_lines()
        step("deadline ticked", title=first, doneInStore=store_done(),
             storeLines=len(lines), label=ev("deadlines.labelText"))
        QTimer.singleShot(900, lambda: (picture(popup("longhand.deadline"), "deadlines"), put_away()))

    def put_away():
        key(popup("longhand.deadline"), Qt.Key.Key_Escape)
        wait(lambda: popup("longhand.deadline") is None and ev("deadlinePanel.opened") is False, away, "Esc putting the popup away")

    def away():
        step("put away", popups=[w.title() for w in app.allWindows() if w.isVisible()])
        ev("pomo.reset()")
        wait(lambda: ev("pomo.phase") == "idle", lambda: (step("timer reset"), click_away()), "the timer back to idle")

    # --- another window clicked: a popup that had the keys goes. (One that
    # Windows never gave them to stays until it is put away: a refused
    # activation is no click elsewhere. Tried on the real screen, 2026-11-24.)
    def click_away():
        ev('popup("deadlines")')
        wait(lambda: popup("longhand.deadline") is not None and give_keyboard(popup("longhand.deadline")),
             clicked_elsewhere, "the deadlines' popup open again, with the keys")

    def clicked_elsewhere():
        from PySide6.QtGui import QWindow
        other = QWindow()
        state["other"] = other
        other.setTitle("somewhere else")
        other.setGeometry(40, 40, 200, 120)
        other.show()
        other.requestActivate()
        wait(lambda: popup("longhand.deadline") is None and ev("deadlinePanel.opened") is False,
             lambda: (step("another window clicked", popups=[w.title() for w in app.allWindows() if w.isVisible()]),
                      other.close(), finish(True)),
             "the popup going when another window takes the keys", 5.0)

    wait(loaded, seed, "the two widgets and their services", 20.0)
