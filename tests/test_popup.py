"""The deadline popup (plugin-deadline): it loads under the installed shell,
and its tick is the page's — a deadline marked done asks for the sound
(never on reopening, never when Settings turned it off) and is done in the
store. It runs `longhand-check` when it opens and after each change, and
never in the background (docs/tasks.md, rules 1 and 6). Runs quickshell
against a throwaway state folder, on the popup as `tools/install-plugins`
installs it: with the page's Store.js beside it, which the repo's folder
does not hold.

And the bar pass (2026-11-28), over both popups as installed: a ticked
row stays where it was, the keys' cursor with it; a cancel comes back with
Ctrl+Z; the timer's typed length is minutes, and with nothing typed Enter
starts the usual length; a session that ran out while the shell was not
running is ended (and logged) when it starts.

Run: python3 tests/test_popup.py
"""
import json
import os
import re
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tests"))
import desktop  # noqa: E402
SHELL = "/usr/share/omarchy/shell"
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


# Open the popup, mark the first deadline done, then reopen it, then (sound
# off) done again; say what the popup counted, and when it opened and
# changed something (the check stub logs when it ran). Each step waits a
# few beats for the store to say so, as a busy machine is slower.
QML = """import QtQuick
import Quickshell
import "deadline"
ShellRoot {
  Panel { id: p }
  property int step: 0
  property int waited: 0
  function at() { return (Date.now() / 1000).toFixed(3) }
  Timer {
    interval: 900; repeat: true; running: true
    onTriggered: {
      var it = p.listed[0]
      var want = step === 2 ? "done" : step === 3 ? "open" : ""
      if (want && it && it.status !== want && waited < 8) { waited++; return }
      waited = 0
      if (step === 0) { console.log("LOADED items=" + p.listed.length + " at=" + at()); p.open(); console.log("OPENED at=" + at()) }
      else if (step === 1) { console.log("TICK at=" + at()); if (it) p.tickItem(it) }
      else if (step === 2) { console.log("AFTER_DONE status=" + (it ? it.status : "") + " heard=" + p.ticksHeard); if (it) p.tickItem(it) }
      else if (step === 3) { console.log("AFTER_REOPEN status=" + (it ? it.status : "") + " heard=" + p.ticksHeard) }
      else Qt.quit()
      step++
    }
  }
}
"""


# Both popups, as the bar pass left them. Each step a few beats apart, as
# the store answers.
PASS_QML = """import QtQuick
import Quickshell
import "deadline" as D
import "pomo" as P
ShellRoot {
  D.Panel { id: d }
  P.Panel { id: t }
  property int step: 0
  function rows() { return d.shown.map(function (i) { return i.title + ":" + i.status }).join(",") }
  Timer {
    interval: 800; repeat: true; running: true
    onTriggered: {
      if (step === 0) { d.open(); d.toggleSelected(); console.log("FIRST_KEY active=" + d.cursorActive + " rows=" + rows()) }
      else if (step === 1) { d.toggleSelected(); console.log("TICKED rows=" + rows() + " row=" + d.cursorRow + " on=" + (d.cursorId === d.shown[0].id)) }
      else if (step === 3) { console.log("SETTLED rows=" + rows() + " row=" + d.cursorRow + " on=" + (d.cursorId === d.shown[0].id)) }
      else if (step === 4) { d.cancelItem(d.shown[d.cursorRow]) }
      else if (step === 6) { console.log("CANCELLED rows=" + rows() + " said=" + d.said); d.undo() }
      else if (step === 8) { console.log("UNDONE rows=" + rows()); d.close() }
      else if (step === 9) {
        t.open()
        t.entryDigits = "25"; console.log("TYPED entry=" + t.entryText())
        t.entryDigits = "5"; console.log("TYPED5 entry=" + t.entryText())
        t.entryDigits = ""; console.log("EMPTY entry=" + t.entryText() + " tip=" + t.playTip)
        t.startFromEntry()
      }
      else if (step === 11) { console.log("STARTED tip=" + t.playTip + " skip=" + t.skipTip + " reset=" + t.resetTip) }
      else if (step > 11) Qt.quit()
      step++
    }
  }
}
"""

LOAD_QML = """import QtQuick
import Quickshell
import "pomo" as P
ShellRoot {
  P.Panel { }
  Timer { interval: 2500; running: true; onTriggered: Qt.quit() }
}
"""


def bar_pass(tmp: pathlib.Path, env: dict) -> None:
    shell = tmp / "shell"
    (shell / "pomo").symlink_to(tmp / "plugins" / "longhand.pomo")
    state = pathlib.Path(env["XDG_STATE_HOME"]) / "longhand"
    for f in ("deadlines.tsv", "state.json", "pomo.log"):
        (state / f).unlink(missing_ok=True)
    for title, when in (("Essay draft", "in 3 days"), ("Lab report", "in 5 days")):
        subprocess.run(["pomo", "deadline", "add", title, *when.split()], env=env, check=True, capture_output=True)
    (shell / "shell.qml").write_text(PASS_QML)
    out = run(tmp, env)
    if os.environ.get("POPUP_DEBUG"):
        print(out)
    check("FIRST_KEY active=true rows=Essay draft:open,Lab report:open" in out,
          "the first key on a row, before the keys have a place, shows where they are and ticks nothing")
    check("TICKED rows=Essay draft:done,Lab report:open row=0 on=true" in out, "a tick is seen at once, on the row it was on")
    check("SETTLED rows=Essay draft:done,Lab report:open row=0 on=true" in out,
          "…and once the store says it, the row stays put, the keys' cursor still on it (not sorted under the next)")
    check("CANCELLED rows=Lab report:open said=cancelled “Essay draft” · Ctrl+Z brings it back" in out,
          "a cancel takes the row off the list and says how to bring it back")
    check("UNDONE rows=Essay draft:done,Lab report:open" in out, "Ctrl+Z brings it back as it was, done")
    check("TYPED entry=25:00" in out and "TYPED5 entry=5:00" in out, "the timer's typed length is minutes: 25 is 25:00, 5 is 5:00")
    check("EMPTY entry=25:00 tip=Start focus · 25:00" in out, "with nothing typed it shows the usual length, and says play starts it")
    check("STARTED tip=Pause skip=Skip to the break · not counted reset=Reset to idle" in out,
          "Enter with nothing typed starts it; skip says a skipped focus is not counted")
    check(not any(w in out for w in ("ReferenceError", "TypeError", "Unable to assign", "is not a type", "unavailable")),
          "…with no QML errors in either popup")

    # A focus that ran out an hour ago, while nothing was running.
    import time
    ended = int(time.time()) - 3600
    (state / "state.json").write_text(
        '{"phase":"focus","status":"running","ends_at":%d,"remaining":1500,"auto":false,"countup":false,'
        '"focus_len":1500,"break_len":300,"total":1500,"for":0}\n' % ended)
    (state / "pomo.log").unlink(missing_ok=True)
    (shell / "shell.qml").write_text(LOAD_QML)
    run(tmp, env)
    log = (state / "pomo.log").read_text() if (state / "pomo.log").exists() else ""
    check("focus completed · 25:00" in log, f"a session that ran out while the shell was down is ended and counted when it starts ({log.strip()!r})")


def stamp(out: str, name: str) -> float:
    m = re.search(name + r"\S* at=([\d.]+)", out)
    return float(m.group(1)) if m else -1.0


def run(tmp: pathlib.Path, env: dict) -> str:
    r = subprocess.run(["timeout", "30", "quickshell", "-p", str(tmp / "shell")], env=env,
                       capture_output=True, text=True)
    return r.stdout + r.stderr


def main() -> int:
    desktop.reach("the popup")
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="popup-test-"))
    shell = tmp / "shell"
    shell.mkdir()
    for name in ("Commons", "Ui"):
        (shell / name).symlink_to(f"{SHELL}/{name}")
    subprocess.run([str(ROOT / "tools" / "install-plugins"), "--to", str(tmp / "plugins")], check=True, capture_output=True)
    (shell / "deadline").symlink_to(tmp / "plugins" / "longhand.deadline")
    (shell / "shell.qml").write_text(QML)
    bindir = tmp / "bin"
    bindir.mkdir()
    (bindir / "pomo").symlink_to(ROOT / "cli" / "pomo")
    # The check, as a stub that says when it ran: whether it runs is the
    # popup's to get right, what it does is tests/test_check.py's.
    checks = tmp / "checks.log"
    (bindir / "longhand-check").write_text(f'#!/bin/sh\necho "$(date +%s.%N) $*" >> "{checks}"\n')
    (bindir / "longhand-check").chmod(0o755)
    state, cfg = tmp / "state", tmp / "config"
    (cfg / "longhand").mkdir(parents=True)
    env = dict(os.environ, XDG_STATE_HOME=str(state), XDG_CONFIG_HOME=str(cfg), LONGHAND_SILENT="1",
               PATH=f"{bindir}{os.pathsep}{os.environ['PATH']}")
    subprocess.run(["pomo", "deadline", "add", "Essay draft", "in", "3", "days"], env=env, check=True, capture_output=True)

    out = run(tmp, env)
    check("LOADED items=1" in out, "the popup loads under the installed shell, with the deadline listed")
    check("AFTER_DONE status=done heard=1" in out, "marking it done asks for the tick, and it is done in the store")
    check("AFTER_REOPEN status=open heard=1" in out, "reopening it is silent")
    check(not any(w in out for w in ("ReferenceError", "TypeError", "Unable to assign", "is not a type")),
          "…with no QML errors")
    ran = [float(l.split()[0]) for l in checks.read_text().splitlines()] if checks.exists() else []
    opened, ticked = stamp(out, "OPENED"), stamp(out, "TICK")
    check(opened > 0 and not [t for t in ran if t < opened - 0.05],
          f"nothing runs the check before the popup opens: no watcher (at {opened}: {ran})")
    check(any(opened - 0.05 <= t < ticked for t in ran), f"opening the popup runs the check, catching edits made elsewhere ({ran})")
    check(sum(t >= ticked for t in ran) >= 2, f"…and each change it makes runs it after (done, then reopened: {ran})")
    check(checks.exists() and all(l.endswith(" --quiet") for l in checks.read_text().splitlines()), "…quietly")

    (cfg / "longhand" / "settings.json").write_text(json.dumps({"tickSound": False}))
    out = run(tmp, env)
    check("AFTER_DONE status=done heard=0" in out, "with the sound turned off in the page's Settings, the popup is silent too")

    same = (ROOT / "plugin-deadline" / "tick.wav").read_bytes() == (ROOT / "plugin-page" / "tick.wav").read_bytes()
    check(same, "the popup's tick is the page's sound (tools/make_tick.py writes both)")
    store = (tmp / "plugins" / "longhand.deadline" / "Store.js").read_bytes() == (ROOT / "plugin-page" / "Store.js").read_bytes()
    check(store, "the popup reads the store as the page does: the page's Store.js, installed beside it")
    bar_pass(tmp, env)
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
