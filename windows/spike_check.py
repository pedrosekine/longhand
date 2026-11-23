"""The spike's question, asked of the running page: does it take keys, save
what was typed, and notice a change made behind its back?

Keys go in as key events to the page's window, the way a keyboard's do, so
the editor's own typing path runs (not `insert`). The page is read through
QML expressions, in its own scope.
"""
from __future__ import annotations

import json
import time

from PySide6.QtCore import QCoreApplication, QEvent, QObject, QPoint, Qt, QTimer
from PySide6.QtTest import QTest
from PySide6.QtGui import QKeyEvent
from PySide6.QtQml import QQmlExpression, qmlContext

import qs_io


def run(app, engine, box, args, warnings):
    root = engine.rootObjects()[0]
    page = root.findChild(QObject, "longhandPage")
    ctx = qmlContext(page)
    out = {"loaded": True, "steps": [], "ok": False}
    # Held on purpose: let go of, PySide deletes the root item and the page with it.
    state = {"t0": time.monotonic(), "last": "", "root": root}

    def ev(expr):
        e = QQmlExpression(ctx, page, expr)
        got = e.evaluate()
        if isinstance(got, tuple):
            got = got[0]
        if e.hasError():
            state["last"] = e.error().toString()
            return None
        return got

    def window():
        for w in app.allWindows():
            if w.isVisible():
                return w
        return None

    def text():
        return ev("editorItem.text")

    def key(w, k, ch="", mods=Qt.KeyboardModifier.NoModifier):
        for kind in (QEvent.Type.KeyPress, QEvent.Type.KeyRelease):
            QCoreApplication.sendEvent(w, QKeyEvent(kind, k, mods, ch))

    def type_text(w, s):
        for ch in s:
            if ch == "\n":
                key(w, Qt.Key.Key_Return, "\r")
            elif ch == " ":
                key(w, Qt.Key.Key_Space, " ")
            else:
                k = Qt.Key(ord(ch.upper())) if ch.isalnum() and ord(ch) < 128 else Qt.Key.Key_unknown
                key(w, k, ch)
            app.processEvents()

    def step(name, **facts):
        out["steps"].append({"step": name, "at": round(time.monotonic() - state["t0"], 2), **facts})

    def finish(ok):
        out["ok"] = ok
        out["warnings"] = warnings
        out["couldNotStart"] = sorted(set(qs_io.LOG))
        args.check.write_text(json.dumps(out, indent=2, ensure_ascii=False), encoding="utf-8")
        app.quit()

    def wait(cond, then, what, limit=15.0):
        t0 = time.monotonic()

        def poll():
            try:
                good = cond()
            except Exception as e:
                good = False
                state["last"] = repr(e)
            if good:
                then()
            elif time.monotonic() - t0 > limit:
                try:
                    step("gave up: " + what, last=state["last"], problem=ev("problem"),
                         configured=ev("noteService.configured"), ready=ev("noteService.ready"),
                         notePath=ev("noteService.notePath"), windowOpen=ev("windowOpen"),
                         windows=[[w.title(), w.isVisible()] for w in app.allWindows()])
                except Exception as e:
                    step("gave up: " + what, last=state["last"], error=repr(e))
                finish(False)
            else:
                QTimer.singleShot(100, poll)
        poll()

    typed = "hello from windows\n# A heading\n- [ ] a box to tick"

    def ready():
        return window() is not None and ev("noteService.ready") is True and ev("editorItem.enabled") is True

    def after_ready():
        w = window()
        w.requestActivate()
        step("ready", title=w.title(), size=[w.width(), w.height()],
             font=ev("fontFamily"), codeFont=ev("codeFamily"),
             background=ev("String(background)"), foreground=ev("String(foreground)"), accent=ev("String(accent)"),
             textBefore=text(), problem=ev("problem"), toolWarning=ev("noteService.toolWarning"))
        QTimer.singleShot(800, do_type)

    def in_note():
        return ev("editorItem.hasFocus") is True

    def do_type():
        w = window()
        step("focus", active=w.isActive(), keysInNote=in_note())
        if not in_note():
            # What a person does when the keys are not in the note: click it.
            QTest.mouseClick(w, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier,
                             QPoint(w.width() // 2, w.height() // 2))
            app.processEvents()
            step("clicked the sheet", keysInNote=in_note())
        if not in_note():
            # The page's own way back to the note (what its Window.onActiveChanged calls).
            ev("focusCenter()")
            app.processEvents()
            step("asked the page for focusCenter()", keysInNote=in_note())
        type_text(w, typed)
        step("typed", editorText=text())
        ev("flush()")
        wait(lambda: box["note"].exists() and "a box to tick" in box["note"].read_text(encoding="utf-8"),
             after_saved, "the note on disk holding what was typed", 8.0)

    def after_saved():
        raw = box["note"].read_bytes()
        step("saved", file=str(box["note"]), bytes=len(raw), crlf=b"\r\n" in raw,
             onDisk=raw.decode("utf-8"), sameAsEditor=raw.decode("utf-8").endswith(text() or "\0"))
        # Something else writes the note (Obsidian, a sync): the page must take it up.
        wait(lambda: ev("noteSaving") is not True, write_behind, "the save to land", 5.0)

    def write_behind():
        with open(box["note"], "ab") as f:
            f.write(b"\nwritten behind the page's back\n")
        wait(lambda: "behind the page's back" in (text() or ""), after_external,
             "the page showing a line written into the file by another program", 8.0)

    def after_external():
        step("external change seen", editorText=text())
        QTimer.singleShot(400, shot)

    def shot():
        w = window()
        if args.shot:
            img = w.grabWindow()
            step("shot", saved=img.save(str(args.shot)), size=[img.width(), img.height()])
        finish(True)

    wait(ready, after_ready, "the page's window and editor")
