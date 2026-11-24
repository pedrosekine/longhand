"""The bar's two popups on Windows: plugin/Panel.qml and
plugin-deadline/Panel.qml, loaded as they are over stand-ins for the shell's
panel pieces (windows/shim/qs/Ui/), opened by the clock. The host is started
on a throwaway vault and drives them itself (windows/popup_check.py); this
reads what it says. And the tick a ticked box plays, which the popup and the
page ask a shell line for. Elsewhere the shell's own pieces are used, and
there is nothing here to test.

Run: python tests\\run_all.py tray_popups
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOST = ROOT / "windows" / "longhand_host.py"
failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def main() -> int:
    if os.name != "nt":
        print("skip: the popups by the clock are Windows' (on Omarchy the shell's bar opens them)")
        return 0
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="tray-popups-test-"))
    out = tmp / "popups.json"
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_CONFIG_HOME=str(tmp / "config"), XDG_STATE_HOME=str(tmp / "state"))
    r = subprocess.run([sys.executable, str(HOST), "--sandbox", str(tmp / "box"), "--check", str(out), "--popups"],
                       capture_output=True, text=True, env=env, timeout=150)
    said = json.loads(out.read_text(encoding="utf-8")) if out.exists() else {"steps": [], "ok": False, "warnings": ["no report"]}
    steps = {s["step"]: s for s in said["steps"]}
    gave_up = [s for s in steps if s.startswith("gave up")]
    check(said.get("ok") is True and not gave_up, f"the host drove both popups to the end ({gave_up or r.stderr.strip()[-300:]})")
    check(not said.get("warnings"), f"the widgets load over the stand-ins with no QML warning ({said.get('warnings')})")

    opened = steps.get("timer popup open", {})
    check(opened.get("inTheCorner") is True, f"the timer's popup opens in the corner by the clock ({opened.get('at')} in {opened.get('workArea')})")
    check((opened.get("size") or [0, 0])[1] > 120, f"…at the height of what is in it ({opened.get('size')})")
    check(steps.get("length typed", {}).get("entry") == "25:00", "2500 typed into it is 25:00, as on the bar")
    started = steps.get("focus started", {})
    check(started.get("remaining") == 1500 and started.get("popupStillOpen") is True,
          f"Enter starts that focus session, the popup staying ({started})")

    listed = steps.get("deadlines popup open", {})
    check(listed.get("rows") == 2 and "Essay draft" in str(listed.get("titles")),
          f"Tab goes over to the deadlines' popup, which lists the store's two ({listed})")
    ticked = steps.get("deadline ticked", {})
    check(ticked.get("doneInStore") == 1 and ticked.get("title") == "Essay draft",
          f"d ticks the one under the cursor, in the store ({ticked})")
    check(steps.get("put away", {}).get("popups") == [], "Esc puts the popup away")
    check("timer reset" in steps, "the timer is back to idle")

    # The tick: the shell line the page and the popup ask for is played by
    # Windows itself, the file named as the page names it.
    sys.path.insert(0, str(ROOT / "windows"))
    import play_sound
    import qs_io
    wav = "/C:/Users/someone/longhand/plugin-deadline/tick.wav"
    line = ('[ "$(omarchy-shell notifications isDnd 2>/dev/null)" = on ] && exit 0; '
            'if command -v pw-play >/dev/null; then exec pw-play --volume=0.6 "$0"; else exec paplay "$0"; fi')
    program, args = qs_io.resolve(["sh", "-c", line, wav])
    check(pathlib.Path(program).name.lower().startswith("python") and pathlib.Path(args[0]).name == "play_sound.py" and args[1] == wav,
          f"the tick's shell line is sent to Windows' own player ({pathlib.Path(program).name}, {args})")
    check(play_sound.path_of(wav) == "C:/Users/someone/longhand/plugin-deadline/tick.wav",
          "a path cut from a file:// URL loses the slash before its drive")
    check(play_sound.path_of("file:///C:/Users/some%20one/tick.wav") == "C:/Users/some one/tick.wav", "…and a URL is read as the file it names")
    check(play_sound.path_of("/home/someone/tick.wav") == "/home/someone/tick.wav", "a path from / is left as it is")
    program, args = qs_io.resolve(["sh", "-c", "echo hello"])
    check(pathlib.Path(program).name.lower() in ("sh.exe", "sh") and args == ["-c", "echo hello"], "any other shell line still goes to the shell")

    print(f"\n{failures} failure(s)")
    return failures


if __name__ == "__main__":
    sys.exit(main())
