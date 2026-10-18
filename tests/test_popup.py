"""The deadline popup (plugin-deadline): it loads under the installed shell,
and its tick is the page's — a deadline marked done asks for the sound
(never on reopening, never when Settings turned it off) and is done in the
store. Runs quickshell against a throwaway state folder.

Run: python3 tests/test_popup.py
"""
import json
import os
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


# Mark the first deadline done, then reopen it, then (sound off) done again;
# say what the popup counted.
QML = """import QtQuick
import Quickshell
import "deadline"
ShellRoot {
  Panel { id: p }
  property int step: 0
  Timer {
    interval: 900; repeat: true; running: true
    onTriggered: {
      var it = p.listed[0]
      if (step === 0) { console.log("LOADED items=" + p.listed.length); if (it) p.tickItem(it) }
      else if (step === 1) { console.log("AFTER_DONE status=" + (it ? it.status : "") + " heard=" + p.ticksHeard); if (it) p.tickItem(it) }
      else if (step === 2) { console.log("AFTER_REOPEN status=" + (it ? it.status : "") + " heard=" + p.ticksHeard) }
      else Qt.quit()
      step++
    }
  }
}
"""


def run(tmp: pathlib.Path, env: dict) -> str:
    r = subprocess.run(["timeout", "15", "quickshell", "-p", str(tmp / "shell")], env=env,
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

    (cfg / "longhand" / "settings.json").write_text(json.dumps({"tickSound": False}))
    out = run(tmp, env)
    check("AFTER_DONE status=done heard=0" in out, "with the sound turned off in the page's Settings, the popup is silent too")

    same = (ROOT / "plugin-deadline" / "tick.wav").read_bytes() == (ROOT / "plugin-page" / "tick.wav").read_bytes()
    check(same, "the popup's tick is the page's sound (tools/make_tick.py writes both)")
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
