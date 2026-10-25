"""The deadline popup (plugin-deadline): it loads under the installed shell,
and its tick is the page's — a deadline marked done asks for the sound
(never on reopening, never when Settings turned it off) and is done in the
store. It runs `longhand-check` when it opens and after each change, and
never in the background (docs/tasks.md, rules 1 and 6). Runs quickshell
against a throwaway state folder.

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


def stamp(out: str, name: str) -> float:
    m = re.search(name + r"\S* at=([\d.]+)", out)
    return float(m.group(1)) if m else -1.0


def run(tmp: pathlib.Path, env: dict) -> str:
    r = subprocess.run(["timeout", "30", "quickshell", "-p", str(tmp / "shell")], env=env,
                       capture_output=True, text=True)
    return r.stdout + r.stderr


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="popup-test-"))
    shell = tmp / "shell"
    shell.mkdir()
    for name in ("Commons", "Ui"):
        (shell / name).symlink_to(f"{SHELL}/{name}")
    (shell / "deadline").symlink_to(ROOT / "plugin-deadline")
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
               PATH=f"{bindir}:{os.environ['PATH']}")
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
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
