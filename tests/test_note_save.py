"""Today's note always reaches the disk (plugin-page/Service.qml).

On 2026-11-17 the page seeded today's note from the template with a
`setText` inside FileView's `loadFailed`. Quickshell writes that, but drops
its `saved` ("got operation finished from dropped operation"), so the
service's `saving` never went false and every later save waited behind it,
in memory only, for 71 minutes, until an update restarted the shell and the
text was gone. Checked here, on the service alone under quickshell,
offscreen:

- a new day's note is seeded and the write says it landed, with no stall;
- the first words after it reach the disk;
- a write whose `saved` never comes (played by holding `saving`) is let go
  after `landWait`, and what was typed meanwhile is written, not lost.

Run: python3 tests/test_note_save.py
"""
import datetime
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


# Each step waits on a condition, polled every 100 ms, and gives up after
# 4 s (a slow machine), saying what it saw.
QML = """import QtQuick
import Quickshell
import Quickshell.Io
import "page"
ShellRoot {
  Service { id: svc; landWait: 800 }
  // What the disk holds now: a synchronous read, not a FileView (whose
  // reload lands later and would show a write too early).
  function onDisk() {
    var x = new XMLHttpRequest()
    x.open("GET", "file://" + svc.notePath, false)
    x.send()
    return x.responseText
  }
  property int step: 0
  property int ticks: 0
  function next() { step++; ticks = 0 }
  function say(what) {
    console.log(what + " saving=" + svc.saving + " stalls=" + svc.stalls + " stalled=" + svc.stalled
                + " disk=" + JSON.stringify(onDisk()))
  }
  Timer {
    interval: 100; repeat: true; running: true
    onTriggered: {
      ticks++
      var late = ticks > 40
      if (step === 0) { if (svc.configured) { svc.openToday(); next() } else if (late) { console.log("NOCONFIG " + svc.configError); Qt.quit() } }
      else if (step === 1) { if ((svc.ready && !svc.saving) || late) { say("SEEDED"); svc.save("first words\\n"); next() } }
      else if (step === 2) { if (!svc.saving || late) { say("FIRST"); svc.saving = true; svc.save("first words\\nmore words\\n"); next() } }
      else if (step === 3) { if (ticks === 2) say("HELD") }
      if (step === 3 && ticks > 2 && (!svc.saving || late)) { say("UNSTUCK"); Qt.quit() }
    }
  }
}
"""


def line(out: str, tag: str) -> str:
    return next((l for l in out.splitlines() if f" {tag} " in l or l.endswith(f" {tag}")), "")


def main() -> int:
    if not shutil.which("quickshell"):
        print("skip: no quickshell")
        return 0
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="note-save-test-"))
    vault, cfg, state = tmp / "vault", tmp / "config", tmp / "state"
    (vault / "Daily").mkdir(parents=True)
    (vault / "tpl").mkdir()
    (vault / "tpl" / "daily.md").write_text("[[agent/{{date}}|agent]]\n")
    (cfg / "longhand").mkdir(parents=True)
    (cfg / "longhand" / "config.json").write_text(json.dumps(
        {"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD", "template": "tpl/daily"}}))
    shell = tmp / "shell"
    shell.mkdir()
    # The page's folder whole, as tests/page/run.py links it: Service.qml
    # imports Links.js beside it (since 2026-11-24), and linked alone it
    # failed to load, every check here reading nothing.
    (shell / "page").symlink_to(ROOT / "plugin-page")
    (shell / "shell.qml").write_text(QML)
    env = dict(os.environ, XDG_CONFIG_HOME=str(cfg), XDG_STATE_HOME=str(state), QT_QPA_PLATFORM="offscreen",
               QML_XHR_ALLOW_FILE_READ="1")
    r = subprocess.run(["timeout", "40", "quickshell", "-p", str(shell / "shell.qml")], env=env,
                       stdin=subprocess.DEVNULL, capture_output=True, text=True)
    out = r.stdout + r.stderr
    today = datetime.date.today().isoformat()
    seed = f"[[agent/{today}|agent]]\n"

    seeded = line(out, "SEEDED")
    check("saving=false stalls=0" in seeded and json.dumps(seed) in seeded,
          f"a new day's note is seeded from the template, and that write says it landed ({seeded!r})")
    check("dropped operation" not in out, "…with no write dropped by Quickshell")
    first = line(out, "FIRST")
    check("saving=false" in first and "first words" in first, f"the first words reach the disk ({first!r})")
    held = line(out, "HELD")
    check("saving=true" in held and "more words" not in held, f"while a write is held, the newer text waits ({held!r})")
    unstuck = line(out, "UNSTUCK")
    check("saving=false stalls=1 stalled=false" in unstuck and "more words" in unstuck,
          f"a write that never says it landed is let go, and the text that waited is written ({unstuck!r})")
    check("never said it landed" in out, "…and the shell's log says so")
    check(not any(w in out for w in ("ReferenceError", "TypeError", "Unable to assign", "is not a type", "non-existent property")),
          "…with no QML errors")
    if failures:
        print(out[-3000:])
    shutil.rmtree(tmp, ignore_errors=True)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
