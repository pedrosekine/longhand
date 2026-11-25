#!/usr/bin/env python3
"""The page's own logic, driven live: bound lines, cancelling, catching up with
the deadline store, outside edits, going to a line, agent accepts.

Needs a Hyprland session with quickshell and the omarchy shell modules. It
builds a throwaway config, vault and deadline store under /tmp, starts a
Hyprland of its own nested in yours, drawing on a headless output
(tests/desktop.py → Private), opens the page there as a window titled "Page
scratch", and talks to it over IPC — no key is ever pressed. Nothing shows
on your screen; your notes, store, running shell and Hyprland rules are not
touched; and it runs with the lid shut, the screen off or the session locked.

Run: python3 tests/page/run.py              # the window shape, as used most
     python3 tests/page/run.py --overlay    # also the overlay

On Windows (or with no quickshell) it runs over the Windows host instead
(`--host qt`: tests/page/qt_host.py, PySide6, offscreen; windows/README.md).
PAGE_LOG=file keeps what the page says; PAGE_KEEP=1 keeps the throwaway
vault, state and logs to read after a failure.
"""
import argparse
import datetime as dt
import json
import os
import pathlib
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
if os.name == "nt":
    # Shebang execution, LF line endings, and Windows process helpers even when
    # tests/page/run.py is invoked directly outside tests/run_all.py.
    sys.path.insert(0, str(ROOT / "tests" / "windows"))
    import sitecustomize as _win_sc  # noqa: E402, F401
    sys.path.pop(0)

    # The page writes a note by renaming a new copy over it. Linux lets a
    # reader in at any moment; Windows refuses one (PermissionError) for the
    # instant the old file is being replaced. What this reads is tried again.
    def _patient(read):
        def again(self, *args, **kwargs):
            for wait in (0.01, 0.02, 0.05, 0.1, 0.2, 0.4, None):
                try:
                    return read(self, *args, **kwargs)
                except PermissionError:
                    if wait is None:
                        raise
                    time.sleep(wait)
        return again
    pathlib.Path.read_text = _patient(pathlib.Path.read_text)
    pathlib.Path.read_bytes = _patient(pathlib.Path.read_bytes)
sys.path.insert(0, str(ROOT / "agent"))
import blocks  # noqa: E402
import lifespan  # noqa: E402
sys.path.insert(0, str(ROOT / "tests"))
import desktop  # noqa: E402

# A question to the page answers in well under a second; one that takes
# this long means the page has frozen, and every check after it would wait.
CALL_TIMEOUT = 30


class PageFrozen(Exception):
    pass


# What the runner writes when the student talks to a block: both turns, the
# way `longhand-agent chat` records them. Enough for the page to settle the
# message it was holding and draw the answer.
CHAT_STUB = """import datetime, json, os, pathlib, sys, time

at = datetime.datetime.now().isoformat(timespec="seconds")   # as the runner does: the one conversation orders by it
daily, args = pathlib.Path(sys.argv[1]), sys.argv[2:]
h = args[args.index("--hash") + 1]
msg = args[args.index("--message") + 1]
stem = args[args.index("--date") + 1]
path = daily / (stem + ".json")
state = json.loads(path.read_text()) if path.exists() else {"date": stem, "blocks": {}}
rec = state["blocks"].setdefault(h, {"state": "seen"})
rec.setdefault("chat", []).append({"role": "student", "text": msg, "at": at})
if "--refs" in args:                    # kept as sent; the runner names them (tests/test_convo.py)
    rec["chat"][-1]["refs"] = json.loads(args[args.index("--refs") + 1])
rec["chat"].append({"role": "agent", "text": "stub answer to: " + msg, "at": at})
rec["state"] = "reply"
rec["read"] = False
rec.setdefault("reply", "")
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(state))
# With `linger` in the stub's folder, the run goes on a moment after its
# answer is written, as a run's process closing does (longer on Windows).
if os.path.exists(os.path.join(os.environ.get("STUB_DIR", ""), "linger")):
    time.sleep(2.5)
"""

# The planner's model, for the page's own tests: it answers only once a
# test has turned it on (plan-on in its folder), so the dashboard's other
# tests see no proposals. It proposes the first box it is offered for
# tomorrow (or its due day, if sooner), and asks one question.
PLAN_STUB = """#!/usr/bin/env python3
import json, os, re, sys
d = os.environ["STUB_DIR"]
payload = sys.stdin.read()
reply = {"proposals": [], "questions": [], "knowledge": []}
if os.path.exists(os.path.join(d, "plan-on")) and payload.startswith("# Plan") \\
        and json.loads(re.search(r"```json\\n(.*?)\\n```", payload, re.S).group(1))["candidates"]:
    data = json.loads(re.search(r"```json\\n(.*?)\\n```", payload, re.S).group(1))
    c = data["candidates"][0]
    day = data["fortnight"][1]["date"]
    # Asked for another day (the box's tomorrow was declined, and the
    # planner never offers a declined day again).
    if os.path.exists(os.path.join(d, "plan-later")):
        day = data["fortnight"][2]["date"]
    if c["due"] and c["due"][:10] < day:
        day = c["due"][:10]
    reply["proposals"].append({"kind": "do-date", "key": c["key"], "date": day, "why": "Tomorrow is free."})
    reply["questions"].append({"key": "", "question": "Do you work on weekends?", "recommended": "No"})
# A scripted reply (slice 5): its "key_of" names a box by its words.
if os.path.exists(os.path.join(d, "plan-reply.json")) and payload.startswith("# Plan"):
    data = json.loads(re.search(r"```json\\n(.*?)\\n```", payload, re.S).group(1))
    reply = json.load(open(os.path.join(d, "plan-reply.json")))
    open(os.path.join(d, "plan-data.json"), "w").write(json.dumps(data))
    for p in reply["proposals"]:
        if "key_of" in p:
            want = p.pop("key_of")
            p["key"] = next((b["key"] for b in data["open_boxes"] if b["title"] == want), "")
# Talking about a proposal (2026-10-20): the reply is talk-reply.json's;
# "revise": "another day" moves a do-date to another day it may have.
if "talk with you about one of your proposals" in sys.argv[-1]:
    path = os.path.join(d, "talk-reply.json")
    reply = json.load(open(path)) if os.path.exists(path) else {"reply": "stub talk"}
    if reply.get("revise") == "another day":
        prop = json.loads(re.search(r"# The proposal the student wants to talk about\\n\\n```json\\n(.*?)\\n```", payload, re.S).group(1))
        data = json.loads(re.search(r"```json\\n(.*?)\\n```", payload, re.S).group(1))
        c = next(x for x in data["candidates"] if x["key"] == prop["key"])
        day = next(f["date"] for f in data["fortnight"] if f["date"] != prop["date"] and (not c["due"] or f["date"] <= c["due"][:10]))
        reply["revise"] = {"kind": "do-date", "key": prop["key"], "date": day, "why": "the day you asked for"}
# The day conversation (2026-10-21): the day agent says back what it was told.
args = sys.argv[1:]
if "--agent" in args and args[args.index("--agent") + 1] == "longhand-day" \
        and "talk with you about one of your proposals" not in args[-1]:   # a talk is the one agent's too (slice 3)
    said = re.findall(r"# The student says\\n\\n(.*?)(?:\\n\\nAnswer|\\n*$)", payload if payload.strip() else args[-1], re.S)
    reply = {"reply": "day: " + (said[-1].strip() if said else ""), "knowledge": [], "read": []}
    # What it may propose about, as last given (slice 3); a scripted
    # day-reply.json proposes, its "key_of" naming a box by its words.
    seen = re.search(r"# What you may propose[^\\n]*\\n\\n[^\\n]*\\n\\n```json\\n(.*?)\\n```", payload + args[-1], re.S)
    if seen:
        open(os.path.join(d, "day-data.json"), "w").write(seen.group(1))
    if os.path.exists(os.path.join(d, "day-reply.json")):
        data = json.load(open(os.path.join(d, "day-data.json")))
        reply["proposals"] = json.load(open(os.path.join(d, "day-reply.json")))
        for p in reply["proposals"]:
            if "key_of" in p:
                want = p.pop("key_of")
                p["key"] = next((b["key"] for b in data["open_boxes"] if b["title"] == want), "")
    # …and what it opens (slice 4 of "One conversation"): day-open.json.
    if os.path.exists(os.path.join(d, "day-open.json")):
        reply["open"] = json.load(open(os.path.join(d, "day-open.json")))
ev = lambda t, part: print(json.dumps({"type": t, "sessionID": "ses_page", "part": part}))
ev("text", {"type": "text", "text": "```json\\n" + json.dumps(reply) + "\\n```"})
ev("step_finish", {"type": "step-finish", "cost": 0.0001, "tokens": {"input": 1, "output": 1, "reasoning": 0, "total": 2}})
"""

# The student's Hyprland bindings, as the throwaway config has them: the six
# keys for the page, the timer and the deadlines, hand-written.
BINDINGS = """o.bind("SUPER + SHIFT + T", "Todoist", { webapp = "https://app.todoist.com/app/today", focus = true })
o.bind("SUPER + ALT + P", "Pomo toggle", "pomo toggle")
o.bind("SUPER + ALT + N", "Pomo skip", "pomo skip")
o.bind("SUPER + ALT + O", "Pomo popup", "omarchy-shell longhand.pomo toggle")
o.bind("SUPER + ALT + D", "Deadlines popup", "omarchy-shell longhand.deadline toggle")
o.bind("SUPER + ALT + equal", "Page (today's note)", "omarchy-shell shell toggle longhand.page '{}'")
o.bind("SUPER + ALT + backslash", "Page alongside", "omarchy-shell shell summon longhand.page '{\\"shape\\":\\"alongside\\"}'")
"""

TODAY = dt.date.today().strftime("%Y.%m.%d")
YDAY = (dt.date.today() - dt.timedelta(days=1)).strftime("%Y.%m.%d")
TODAY_ISO = dt.date.today().isoformat()
failures = 0
HOST = "quickshell"          # set in main(): "quickshell" on Omarchy, "qt" on Windows / headless PySide6

SYNTH_THEME_A = (
    'background = "#1a1b26"\nforeground = "#c0caf5"\naccent = "#7aa2f7"\n'
    'red = "#f7768e"\nyellow = "#e0af68"\norange = "#ff9e64"\ngreen = "#9ece6a"\n'
    'blue = "#7aa2f7"\nmagenta = "#bb9af7"\ncyan = "#7dcfff"\n'
    'muted = "#565f89"\nlight_foreground = "#a9b1d6"\ndark_foreground = "#565f89"\ndark_background = "#16161e"\n'
)
SYNTH_THEME_B = (
    'background = "#282828"\nforeground = "#ebdbb2"\naccent = "#fabd2f"\n'
    'red = "#fb4934"\nyellow = "#fabd2f"\norange = "#fe8019"\ngreen = "#b8bb26"\n'
    'blue = "#83a598"\nmagenta = "#d3869b"\ncyan = "#8ec07c"\n'
    'muted = "#928374"\nlight_foreground = "#d5c4a1"\ndark_foreground = "#a89984"\ndark_background = "#1d2021"\n'
)

# The bash runner (Page), in Python, for the Qt host: no bash on Windows.
# Page puts the paths it needs first in its arguments.
PY_RUNNER = """
import os, subprocess, sys, time
calls, stub, agent, chatstub, daily = sys.argv[1:6]
argv = sys.argv[6:]
cmd = argv[0] if argv else ""
arg3 = argv[2] if len(argv) > 2 else ""
# Stopped as the page stops a run. On Linux the page's SIGTERM ends the bash
# runner in its sleep, before the stub answers. Windows has no such signal:
# the host sets a named event, and ends outright only what has not said it
# listens, after three seconds (windows/qs_io.py, `signal`) -- longer than
# the stub's two. So this listens, as the real runner does
# (agent/winproc.py), and ends what it started.
child = []
if os.name == "nt":
    sys.path.insert(0, os.path.dirname(agent))
    import winproc
    def stopped():
        for c in child:
            c.kill()
        os._exit(143)
    winproc.listen_for_stop(stopped)
def run(cmdline):
    c = subprocess.Popen(cmdline)
    child.append(c)
    return c.wait()
# One line of the log, whole. Runners start side by side and append at
# once; a file opened for appending is a seek and a write on Windows, and
# one runner's line overwrote another's ("start plan" lost, 2026-11-25).
# Opened for appending only (FILE_APPEND_DATA), Windows appends a write
# whole, as O_APPEND does on Linux.
def log(line):
    data = line.encode("utf-8")
    if os.name != "nt":
        with open(calls, "ab") as f:
            f.write(data)
        return
    import ctypes
    from ctypes import wintypes
    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.CreateFileW.restype = wintypes.HANDLE
    k32.CreateFileW.argtypes = (wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p,
                                wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE)
    h = k32.CreateFileW(calls, 0x0004, 0x7, None, 4, 0x80, None)   # append only, shared, open always
    try:
        done = wintypes.DWORD()
        k32.WriteFile(wintypes.HANDLE(h), data, len(data), ctypes.byref(done), None)
    finally:
        k32.CloseHandle(wintypes.HANDLE(h))
log(f"{time.time():.6f} start {cmd} {arg3}\\n")
if cmd == "projects":
    if os.path.exists(os.path.join(stub, "slow-fetch")):
        time.sleep(2)
    rc = run([sys.executable, agent, *argv])
    log(f"{time.time():.6f} end {cmd}\\n")
    sys.exit(rc)
LOCAL = {"accept", "projects", "project", "project-page", "sections", "next", "dated", "tasks", "box", "timetable",
         "plan", "proposals", "proposal", "talk", "thread", "rate", "notebook", "autonomy", "day", "search", "horizon",
         "note", "export", "checkin", "conversation"}
if cmd in LOCAL:
    sys.exit(run([sys.executable, agent, *argv]))
if cmd == "run":
    time.sleep(2)
    sys.exit(0)
if cmd == "chat":
    time.sleep(2)
    sys.exit(run([sys.executable, chatstub, daily, *argv]))
sys.exit(0)
"""


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


class Page:
    def __init__(self, fake_home=False, host=None):
        self.host = host or HOST
        self.qt = self.host == "qt"
        self._sock = None
        self._sock_f = None
        self._after_call_stat = None
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="page-test-"))
        self.shell = self.tmp / "shell"
        self.shell.mkdir()
        if not self.qt:
            for mod in ("Commons", "Ui"):
                (self.shell / mod).symlink_to(f"/usr/share/omarchy/shell/{mod}")
            (self.shell / "page").symlink_to(ROOT / "plugin-page")
            shutil.copy(ROOT / "tests" / "page" / "harness.qml", self.shell / "shell.qml")
        else:
            page_url = (ROOT / "plugin-page").as_uri().rstrip("/")
            qml = (ROOT / "tests" / "page" / "harness.qml").read_text(encoding="utf-8")
            qml = qml.replace('import "page"', f'import "{page_url}"')
            qml = qml.replace('import "page/', f'import "{page_url}/')
            qml = qml.replace('Qt.resolvedUrl("page/', f'Qt.resolvedUrl("{page_url}/')
            (self.shell / "shell.qml").write_text(qml, encoding="utf-8")
        self.vault = self.tmp / "vault"
        self.daily = self.vault / "Daily"
        self.daily.mkdir(parents=True)
        self.state = self.tmp / "state"
        (self.state / "longhand").mkdir(parents=True)
        # The page opens by date (2026-11-03); the checks below were written
        # for the order by what each row asks, and 12f walks to the others.
        (self.state / "longhand" / "page.json").write_text('{"dashOrder": "ask"}\n')
        self.store = self.state / "longhand" / "deadlines.tsv"
        cfg = self.tmp / "config"
        (cfg / "longhand").mkdir(parents=True)
        if not self.qt:
            (cfg / "omarchy").symlink_to(pathlib.Path.home() / ".config" / "omarchy")   # the theme
        self.runner = self.tmp / ("runner.py" if self.qt else "runner")
        self.played = self.tmp / "played.log"
        self.calls = self.tmp / "calls.log"
        self.stub = self.tmp / "stub"
        self.stub.mkdir()
        bindir = self.tmp / "bin"
        bindir.mkdir()
        chatstub = self.tmp / "chatstub.py"
        chatstub.write_text(CHAT_STUB)

        if self.qt:
            # Cross-platform stubs: no symlinks, no bash required. On Windows
            # tests/windows/sitecustomize.py starts extensionless #! scripts
            # directly via python.exe without cmd.exe (preserving newlines in args).
            (bindir / "opencode").write_text(PLAN_STUB)
            (bindir / "hyprctl").write_text(
                f'#!/usr/bin/env python3\nimport subprocess, sys\n'
                f'sys.exit(subprocess.run([sys.executable, {str(ROOT / "tests" / "fake_hyprctl.py")!r}, *sys.argv[1:]]).returncode)\n'
            )
            if os.name != "nt":
                (bindir / "opencode").chmod(0o755)
                (bindir / "hyprctl").chmod(0o755)
                (bindir / "pomo").symlink_to(ROOT / "cli" / "pomo")
            # One Python, not a wrapper starting another: on Windows each
            # start costs a few hundred milliseconds, and the page starts the
            # runner for nearly everything it asks.
            baked = [str(self.calls), str(self.stub), str(ROOT / "agent" / "longhand-agent"), str(chatstub),
                     str(self.vault / "agents" / "longhand" / "daily")]
            self.runner.write_text(f"#!/usr/bin/env python3\nimport sys\nsys.argv[1:1] = {baked!r}\n" + PY_RUNNER)
            if os.name != "nt":
                self.runner.chmod(0o755)
        else:
            (bindir / "pomo").symlink_to(ROOT / "cli" / "pomo")
            (bindir / "pw-play").write_text(f'#!/bin/sh\necho "$@" >> "{self.played}"\n')
            (bindir / "pw-play").chmod(0o755)
            real_shell = shutil.which("omarchy-shell") or "false"
            (bindir / "omarchy-shell").write_text('#!/bin/sh\n[ "$1 $2" = "notifications isDnd" ] && { echo off; exit 0; }\n'
                                                  f'exec "{real_shell}" "$@"\n')
            (bindir / "omarchy-shell").chmod(0o755)
            (bindir / "opencode").write_text(PLAN_STUB)
            (bindir / "opencode").chmod(0o755)
            (bindir / "hyprctl").write_text(f'#!/bin/sh\nexec python3 "{ROOT}/tests/fake_hyprctl.py" "$@"\n')
            (bindir / "hyprctl").chmod(0o755)
            self.runner.write_text(f"""#!/bin/bash
echo "$(date +%s.%N) start $1 $3" >> "{self.calls}"
if [ "$1" = projects ]; then
  [ -e "{self.stub}/slow-fetch" ] && sleep 2
  "{ROOT}/agent/longhand-agent" "$@"; rc=$?
  echo "$(date +%s.%N) end $1" >> "{self.calls}"
  exit $rc
fi
case "$1" in
  accept|projects|project|project-page|sections|next|dated|tasks|box|timetable|plan|proposals|proposal|talk|thread|rate|notebook|autonomy|day|search|horizon|note|export|checkin|conversation) exec "{ROOT}/agent/longhand-agent" "$@" ;;
  run) sleep 2; exit 0 ;;
  chat) sleep 2; exec python3 "{chatstub}" "{self.vault}/agents/longhand/daily" "$@" ;;
esac
""")
            self.runner.chmod(0o755)

        (cfg / "longhand" / "config.json").write_text(json.dumps({
            "vault": self.vault.as_posix(), "daily": {"dir": "Daily", "format": "YYYY.MM.DD"}, "horizon": "2000-01-01",
            # The stub by its path, not its name: on Windows a name is looked
            # up with PATHEXT (the agent's `_win_cmd`), which passes over the
            # stub (no extension) for an opencode installed on the machine.
            "opencode": (bindir / "opencode").as_posix(),
            "runner": self.runner.as_posix(), "check": (ROOT / "cli" / "longhand-check").as_posix(),
            "read": (ROOT / "cli" / "longhand-read").as_posix(), "weekStart": "monday",
            "inbox": (self.tmp / "Downloads").as_posix(),
            "export": {"author": "A. Student", "dir": (self.tmp / "Downloads").as_posix()}}))
        (self.tmp / "Downloads").mkdir()
        # Hyprland, played over a throwaway hypr folder: the keys sheet's
        # writes, reloads and submap never reach the real one.
        self.hypr = cfg / "hypr"
        self.hypr.mkdir()
        (self.hypr / "bindings.lua").write_text(BINDINGS)
        extra_path = [str(bindir)]
        if os.name == "nt":
            extra_path.append(str(pathlib.Path(sys.executable).parent))
        self.env = dict(os.environ, XDG_CONFIG_HOME=cfg.as_posix(), XDG_STATE_HOME=self.state.as_posix(),
                        STUB_DIR=str(self.stub),
                        PATH=os.pathsep.join(extra_path + [os.environ["PATH"]]), FAKE_HYPR_DIR=str(self.hypr),
                        FAKE_HYPR_REAL=shutil.which("hyprctl") or "")
        self.env.pop("LONGHAND_SILENT", None)
        # Every deadline the check cancels, and why (cli/longhand-check,
        # `trace`): said in the failures that come from a line lost.
        self.cancels = self.tmp / "cancels.log"
        self.env["LONGHAND_CHECK_LOG"] = str(self.cancels)
        if fake_home or self.qt:
            # A home of its own, holding a theme palette, so a theme switch can
            # be replayed without touching the real one (and on Qt host without
            # an Omarchy install, a synthetic palette provides every role).
            self.home = self.tmp / "home"
            self.theme = self.home / ".local" / "state" / "omarchy" / "current" / "theme"
            self.theme.mkdir(parents=True)
            real = pathlib.Path.home() / ".local" / "state" / "omarchy" / "current" / "theme"
            copied = False
            for name in ("colors.toml", "shell.toml"):
                if (real / name).exists():
                    shutil.copy(real / name, self.theme / name)
                    copied = True
            if not copied:
                (self.theme / "colors.toml").write_text(SYNTH_THEME_A)
            self.env["HOME"] = self.home.as_posix()
            if os.name == "nt":
                self.env["USERPROFILE"] = str(self.home)     # what Path.home() and Qt read there
        self._log = open(os.environ["PAGE_LOG"], "w") if os.environ.get("PAGE_LOG") else None
        log = self._log if self._log is not None else subprocess.DEVNULL
        if self.qt:
            self.env["LONGHAND_PLAY_LOG"] = str(self.played)
            if not os.environ.get("PAGE_SHOW"):
                self.env["QT_QPA_PLATFORM"] = "offscreen"
                # Offscreen Qt on Windows finds no fonts and draws every glyph
                # as a box of one width, so the measure (72 characters) is
                # off; given Windows' own folder it lays text out as on screen.
                if os.name == "nt" and not self.env.get("QT_QPA_FONTDIR"):
                    self.env["QT_QPA_FONTDIR"] = str(pathlib.Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts")
            # Qt's warnings on stderr, for PAGE_LOG: on Windows it sends them
            # to the debugger instead when no console is attached.
            self.env["QT_FORCE_STDERR_LOGGING"] = "1"
            if os.name == "nt":
                py_path = [str(ROOT / "tests" / "windows"), str(ROOT / "windows" / "pyshim")]
                old_pp = self.env.get("PYTHONPATH", "")
                self.env["PYTHONPATH"] = os.pathsep.join(py_path + ([old_pp] if old_pp else []))
                self.env["PYTHONUTF8"] = "1"
                self.env["PYTHONIOENCODING"] = "utf-8"
            self.proc = subprocess.Popen(
                [sys.executable, str(ROOT / "tests" / "page" / "qt_host.py"), str(self.shell), "701", "850"],
                env=self.env, stdout=log, stderr=log)
            port_file = self.shell / ".qt-ipc-port"
            end = time.time() + 15
            while time.time() < end and not port_file.is_file():
                if self.proc.poll() is not None:
                    raise PageFrozen(f"qt_host exited early ({self.proc.returncode})")
                time.sleep(0.05)
            if not port_file.is_file():
                raise PageFrozen("qt_host never wrote its IPC port")
            port = int(port_file.read_text().strip())
            self._sock = socket.create_connection(("127.0.0.1", port), timeout=CALL_TIMEOUT)
            self._sock.settimeout(CALL_TIMEOUT)
            self._sock_f = self._sock.makefile("r", encoding="utf-8")
            self.wait(lambda: self.call("state").startswith("{"), 10)
            # Push the synthetic/copied colors.toml into Commons.Color so
            # ThemeColors and the shell palette agree from the start.
            if (self.theme / "colors.toml").is_file():
                import base64
                c64 = base64.b64encode((self.theme / "colors.toml").read_bytes()).decode()
                s64 = base64.b64encode((self.theme / "shell.toml").read_bytes()).decode() if (self.theme / "shell.toml").is_file() else ""
                self.call("applyTheme", c64, s64)
        else:
            subprocess.run(["hyprctl", "eval", 'hl.window_rule({ match = { title = "^Page scratch$" }, no_initial_focus = true })'],
                           capture_output=True)
            # A known size, whatever else is open on the workspace (tiled into a
            # full one, the window can be a few pixels wide).
            subprocess.run(["hyprctl", "eval", 'hl.window_rule({ match = { title = "^Page scratch$" }, float = true, size = { 701, 850 } })'],
                           capture_output=True)
            # PAGE_LOG=file keeps what the page says (its QML warnings), to read
            # when a run goes wrong.
            self.proc = subprocess.Popen(["quickshell", "-p", str(self.shell)], env=self.env, stdout=log, stderr=log)
            self.wait(lambda: self.call("state").startswith("{"), 10)

    def call(self, fn, *args):
        if self.qt:
            try:
                req = json.dumps({"fn": fn, "args": [str(a) for a in args]}) + "\n"
                self._sock.sendall(req.encode("utf-8"))
                line = self._sock_f.readline()
                if not line:
                    raise PageFrozen(f"qt_host closed IPC during {fn}")
                resp = json.loads(line)
                if not resp.get("ok"):
                    return ""
                today_file = self.daily / f"{TODAY}.md"
                try:
                    st = today_file.stat()
                    self._after_call_stat = (st.st_mtime_ns, st.st_size)
                except OSError:
                    self._after_call_stat = None
                return str(resp.get("out", ""))
            except (socket.timeout, TimeoutError):
                raise PageFrozen(f"the page stopped answering ({fn} {' '.join(map(str, args))}, {CALL_TIMEOUT}s)") from None
        try:
            r = subprocess.run(["quickshell", "ipc", "-p", str(self.shell), "call", "page", fn, *map(str, args)],
                               capture_output=True, text=True, env=self.env, timeout=CALL_TIMEOUT)
        except subprocess.TimeoutExpired:
            # Not asked again: a frozen page may still act on it once it
            # wakes, and a key would then be pressed twice.
            off = desktop.screens_off()
            raise PageFrozen(f"the page stopped answering ({fn} {' '.join(map(str, args))}, {CALL_TIMEOUT}s)"
                             + (f": the screen is off ({', '.join(off)}), so it gets no frames" if off else "")) from None
        out = r.stdout
        return out[:-1] if out.endswith("\n") else out   # only IPC's own newline: a note may start with one

    def wait(self, cond, timeout=6.0):
        # Process creation on Windows is slower than Linux fork(), so give
        # conditions a little more headroom without changing Linux timeouts.
        end = time.time() + (timeout * 2.0 if os.name == "nt" else timeout)
        while time.time() < end:
            try:
                if cond():
                    return True
            except (ValueError, KeyError, IndexError, TypeError, json.JSONDecodeError):   # TypeError: not asked yet (null)
                pass
            time.sleep(0.15)
        return False

    def pomo(self, *args):
        cmd = [sys.executable, str(ROOT / "cli" / "pomo.py"), "deadline", *args] if os.name == "nt" else ["pomo", "deadline", *args]
        return subprocess.run(cmd, capture_output=True, text=True, env=self.env).stdout

    def check(self):
        """The check, as the popup runs it after a change."""
        cmd = [sys.executable, str(ROOT / "cli" / "longhand-check"), "--quiet"]
        return subprocess.run(cmd, capture_output=True, text=True, env=self.env)

    def deadline(self, i):
        for line in (self.store.read_text().splitlines() if self.store.exists() else []):
            f = line.split("\t")
            if int(f[0]) == i:
                return {"title": f[2], "status": f[3], "grade": f[5] if len(f) > 5 else "",
                        "project": f[6] if len(f) > 6 else "", "link": f[7] if len(f) > 7 else ""}
        return None

    def note(self, stem=TODAY):
        p = self.daily / f"{stem}.md"
        return p.read_text() if p.exists() else ""

    def lines(self):
        return self.call("text").split("\n")

    def line_of(self, needle):
        return next(i for i, l in enumerate(self.lines()) if needle in l)

    def offset_of_line(self, i):
        return sum(len(l) + 1 for l in self.lines()[:i])

    def open_fresh(self, payload='{"shape":"alongside"}'):
        if self.qt:
            # Fast TCP IPC can reach write_text() + open_fresh() before a 300ms
            # saveTimer from the previous test fires; if the test just wrote a
            # fresh fixture to TODAY.md after the last IPC call, keep it from
            # being overwritten by closeAll() -> flush().
            today_file = self.daily / f"{TODAY}.md"
            try:
                st = today_file.stat()
                cur_stat = (st.st_mtime_ns, st.st_size)
            except OSError:
                cur_stat = None
            fixture = today_file.read_bytes() if (cur_stat is not None and cur_stat != self._after_call_stat) else None
            self.call("closeAll")
            if fixture is not None:
                # Put back once the page's last save has landed: on GitHub's
                # Windows machine a save from the edits before landed after
                # a fixed 50 ms, over the note put back (2026-11-25).
                self.wait(lambda: self.call("noteSaving") == "false", 5)
                today_file.write_bytes(fixture)
        else:
            self.call("closeAll")
        self.call("summon", payload)
        self.wait(lambda: json.loads(self.call("state"))["ready"])
        time.sleep(0.5)

    def resize(self, w, h):
        if self.qt:
            self.call("__resize", w, h)
        else:
            subprocess.run(["hyprctl", "eval",
                            f'hl.window_rule({{ match = {{ title = "^Page scratch$" }}, float = true, size = {{ {w}, {h} }} }})'],
                           capture_output=True)
        self.open_fresh()
        self.wait(lambda: abs(json.loads(self.call("sides"))["width"] - w) < 20, 4)

    def close(self):
        if self.qt and self._sock is not None:
            try:
                self.call("__quit")
            except Exception:  # noqa: BLE001
                pass
            try:
                self._sock_f.close()
                self._sock.close()
            except OSError:
                pass
        self.proc.terminate()
        try:
            self.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()
        if getattr(self, "_log", None) is not None:
            self._log.close()
        if os.environ.get("PAGE_KEEP"):            # the vault, state and logs, to read after a failure
            print(f"     (kept {self.tmp})")
        else:
            shutil.rmtree(self.tmp, ignore_errors=True)


def header(stem):
    return f"[[agents/longhand/daily/{stem}|agent]]\n\n"


def contrast(a: str, b: str) -> float:
    """WCAG contrast between two "#rrggbb" colours, as ThemeColors.qml
    measures it."""
    def lum(c):
        def ch(x):
            x /= 255.0
            return x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4
        h = c.lstrip("#")[-6:]
        r, g, bl = (int(h[i:i + 2], 16) for i in (0, 2, 4))
        return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(bl)
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def delta_e(a: str, b: str) -> float:
    """How far apart two colours look (CIE76), the way ThemeColors.qml
    measures it — contrast says nothing about this."""
    def lab(c):
        def lin(x):
            x /= 255.0
            return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4
        def f(t):
            return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
        h = c.lstrip("#")[-6:]
        r, g, bl = (lin(int(h[i:i + 2], 16)) for i in (0, 2, 4))
        x = f((0.4124 * r + 0.3576 * g + 0.1805 * bl) / 0.95047)
        y = f(0.2126 * r + 0.7152 * g + 0.0722 * bl)
        z = f((0.0193 * r + 0.1192 * g + 0.9505 * bl) / 1.08883)
        return (116 * y - 16, 500 * (x - y), 200 * (y - z))
    p, q = lab(a), lab(b)
    return sum((p[i] - q[i]) ** 2 for i in range(3)) ** 0.5


def theme_switch() -> None:
    """Replay `omarchy theme set` the way it runs: the new theme is staged,
    the old folder removed, the new one moved in, then the colours pushed
    to the shell over IPC. The page must repaint at once."""
    import base64
    themes = pathlib.Path("/usr/share/omarchy/themes")
    target = next((t for t in ("tokyo-night", "gruvbox", "nord") if (themes / t / "colors.toml").exists()), None)
    next_colors = (themes / target / "colors.toml").read_text() if target else SYNTH_THEME_B
    next_shell = (themes / target / "shell.toml").read_text() if (target and (themes / target / "shell.toml").exists()) else ""
    label = target or "synthetic-gruvbox"
    want = re.search(r'^accent\s*=\s*"(#[0-9A-Fa-f]{6})"', next_colors, re.M).group(1).lower()
    p = Page(fake_home=True)
    try:
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "# heading\n")
        p.open_fresh()
        before = p.call("palette")
        nxt = p.theme.parent / "next-theme"
        nxt.mkdir()
        (nxt / "colors.toml").write_text(next_colors)
        if next_shell:
            (nxt / "shell.toml").write_text(next_shell)
        shutil.rmtree(p.theme)
        nxt.rename(p.theme)
        moved = time.time()
        file_only = p.wait(lambda: f"accent={want}" in p.call("palette"), 1.5)
        b64 = lambda n: base64.b64encode((p.theme / n).read_bytes()).decode() if (p.theme / n).exists() else ""
        sent = time.time()
        p.call("applyTheme", b64("colors.toml"), b64("shell.toml"))
        repainted = p.wait(lambda: f"accent={want}" in p.call("palette"), 3)
        took = time.time() - sent
        print(f"     (file watch alone caught it: {file_only}; after the shell's push: {took:.2f}s)")
        check(f"accent={want}" not in before and repainted and took < 1.0, f"a theme switch repaints the page at once ({label})")
        heads = p.call("palette").split(" h=")[1].split(" ")[0].split(",")
        # H1 is the new accent, deepened if that accent sat too near the text:
        # the same colour, never another one.
        check(len(set(heads)) == 4 and delta_e(heads[0], want) < 25,
              f"…and the new theme's accent leads the heading ramp ({','.join(heads)}, {delta_e(heads[0], want):.0f} ΔE off {want})")

        # How Longhand feels, once a week (2026-11-18): the dashboard says it
        # is due, F opens it, the keys answer it, Enter keeps it, and the
        # keys are back on the list; the week is answered in the vault.
        ci = lambda: json.loads(p.call("checkin"))  # noqa: E731
        p.call("closePanes")
        if json.loads(p.call("panes"))["center"] != "dash":
            p.call("dash")
        check(p.wait(lambda: ci()["due"], 6), "the week's check-in is due, said on the dashboard")
        p.call("dashKey", 0x46, 0)                      # F
        check(p.wait(lambda: ci()["view"] == "checkin", 2), f"F opens it ({ci()})")
        p.call("checkinKey", 0x01000004)                # Enter, nothing answered
        check(ci()["view"] == "checkin" and "8 lines to go" in p.call("hint"), f"…Enter with lines left says so ({p.call('hint')!r})")
        for k in "66564565":
            p.call("checkinKey", ord(k))
        check(ci()["answers"] == [6, 6, 5, 6, 4, 5, 6, 5], f"…a digit answers a line and moves on ({ci()['answers']})")
        p.call("checkinKey", 0x01000004)                # Enter
        # Enter keeps the week through `longhand-agent checkin`, a Python
        # started cold: on a busy Windows runner that alone has taken more
        # than the 4 s this waited (2026-11-24, three times: twice here
        # beside other runs, once in CI). Waited for longer; still a check.
        check(p.wait(lambda: not ci()["due"] and ci()["view"] == "", 15) and ci()["center"] == "dash",
              f"…Enter keeps the week, and the keys are back on the dashboard ({ci()})")
        logs = list((p.vault / "agents" / "longhand" / "checkins").glob("*.jsonl"))
        check(len(logs) == 1 and '"answers": [6, 6, 5, 6, 4, 5, 6, 5]' in logs[0].read_text(),
              "…kept in this machine's log in the vault")
    finally:
        p.close()


def main() -> int:
    global HOST
    ap = argparse.ArgumentParser(description="Drive Longhand's live page over IPC.")
    ap.add_argument("--overlay", action="store_true", help="also test the overlay shape")
    ap.add_argument("--host", choices=("auto", "quickshell", "qt"), default="auto",
                    help="host backend: quickshell (Omarchy/Hyprland) or qt (PySide6 offscreen, default on Windows)")
    ap.add_argument("--smoke", action="store_true", help="run only the theme-switch & weekly check-in smoke pass")
    args = ap.parse_args()
    HOST = ("qt" if (os.name == "nt" or not shutil.which("quickshell")) else "quickshell") if args.host == "auto" else args.host
    if HOST == "qt":
        if args.smoke:
            theme_switch()
            print("PASS" if failures == 0 else f"{failures} FAILED")
            return 1 if failures else 0
        return checks()
    # The page draws in a Hyprland of its own, on a headless output: never on
    # your screen, and drawn whatever the session is doing (lid shut, screen
    # off, locked: then a window on it gets no frames and the page freezes).
    desktop.reach("the page", wake_screen=False)
    with desktop.Private():
        if args.smoke:
            theme_switch()
            print("PASS" if failures == 0 else f"{failures} FAILED")
            return 1 if failures else 0
        return checks()


def checks() -> int:
    theme_switch()
    p = Page()
    try:
        # 0. The first open after the shell starts asks the note for the keys
        # before it has been read: they are in the note once it is. Until
        # 2026-11-24 the overlay left them in the closed settings sheet's
        # key catcher, and what was typed went to hidden settings.
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "Plan for the week.\n")
        p.call("summon", "{}")
        p.wait(lambda: json.loads(p.call("state"))["ready"])
        check(p.wait(lambda: p.call("noteHasKeys") == "true", 3), "the first open: the keys are in the note once it is read")

        # 1. a checkbox written with a date at its end lights up, and binds
        # when it is left — no question asked
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "Plan for the week.\n")
        p.open_fresh()
        p.call("cursorEnd")
        p.call("type", "- [ ] chapter 2 draft #thesis due fri 17:00")
        check(p.call("pending", p.line_of("chapter 2")) == "true", "the date lights up as it is typed")
        check(p.call("ask") == "null", "nothing is asked")
        p.call("cursor", 1)
        check(p.wait(lambda: "#thesis 📅 " in p.note() and p.note().rstrip().endswith("17:00 ^d1")), "left, the line is bound: 📅 date ^d1")
        # The store is written a moment after the note: waited for.
        p.wait(lambda: (p.deadline(1) or {}).get("link") == f"[[{TODAY}#^d1]]", 5)
        d = p.deadline(1)
        check(d and d["project"] == "thesis" and d["link"] == f"[[{TODAY}#^d1]]", f"store has it, with project and link ({d})")

        # 2. ticking the line marks it done; 3. its words rename it
        p.call("tick", p.line_of("chapter 2 draft"))
        check(p.wait(lambda: p.deadline(1)["status"] == "done"), "ticking the line marks the deadline done")
        # Staging went on 2026-10-15: a tick leaves no mark saying the block
        # "could be sent", and the tick is still a sign Ctrl+Enter can send.
        check(json.loads(p.call("marks")) == [], f"a tick marks nothing in the gutter ({p.call('marks')})")
        p.call("cursor", p.offset_of_line(p.line_of("chapter 2 draft")) + 8)
        check(p.wait(lambda: p.call("trigger") == "tick"), f"a ticked box is still a sign for Ctrl+Enter ({p.call('trigger')})")
        check(p.call("ask") == "null", "…and nothing was asked on the way")
        i = p.line_of("chapter 2 draft")
        p.call("cursor", p.offset_of_line(i) + len("- [x] chapter 2 draft #thesis"))
        p.call("insert", " v2")
        p.call("cursor", 1)
        check(p.wait(lambda: p.deadline(1)["title"] == "chapter 2 draft v2"), "editing the words renames it")
        i = p.line_of("chapter 2 draft")
        p.call("cursor", p.offset_of_line(i) + len("- [x] chapter 2 draft #thesis v2"))
        p.call("type", "   ")
        p.call("cursor", 1)
        check(p.wait(lambda: "#thesis v2 📅 " in p.note()), "spaces left at the end of a bound line's words go when it is left")

        # 4. Ctrl+D binds a plain line — as an undo step of its own. The
        # student goes on writing while its date is read and its deadline
        # added; the binding lands inside that run of typing, and the
        # Backspace after it, undone, brings back what it deleted and only
        # that (until 2026-10-17 it took the binding back too, and with it
        # the deadline: docs/tasks.md).
        p.call("cursor", p.offset_of_line(p.line_of("Plan for the week")))
        p.call("insert", "then\n")                 # above it: no 📅 before it to count
        p.call("ctrlD")
        time.sleep(0.3)
        p.call("cursor", p.offset_of_line(p.line_of("then")) + len("then"))
        p.call("type", ".")                         # the run starts before the date is given
        p.call("when", "tomorrow")
        for _ in range(40):
            if p.call("typeUnless", ".", "^d2") != "true":
                break
            time.sleep(0.1)
        check("Plan for the week. 📅 " in p.call("text") and "^d2" in p.call("text"), "Ctrl+D + when binds a plain line")
        typed = p.lines()[p.line_of("then")]
        p.call("backspace", 1)
        p.call("undo")
        check(p.lines()[p.line_of("then")] == typed and "Plan for the week. 📅 " in p.lines()[p.line_of("Plan for the week")],
              f"Ctrl+Z after a Backspace brings back only what it deleted ({p.lines()[p.line_of('Plan for the week')]!r})")
        time.sleep(0.5)
        check(p.deadline(2)["status"] == "open", f"…and the binding's deadline stays ({p.deadline(2)})")

        # 5. deleting a bound line cancels its deadline and says so; nothing
        # is asked, and the line coming back brings it back (docs/tasks.md)
        p.call("removeLine", p.line_of("^d1"))
        check(p.wait(lambda: p.deadline(1)["status"] == "cancelled"), "deleting a bound line cancels its deadline")
        # The check writes the store before it exits and says what it did:
        # the hint comes a moment after the store (longer on Windows, where
        # a Python takes longer to end).
        check(p.wait(lambda: "cancelled" in p.call("hint"), 3) and p.call("ask") == "null",
              f"…said under the cursor, nothing asked ({p.call('hint')!r})")
        bound = p.lines()[p.line_of("^d2")]
        p.call("undo")
        check(p.wait(lambda: p.deadline(1)["status"] == "done"), "Ctrl+Z brings the line back, and its deadline as it was")
        # …and only that: the Ctrl+D binding before the deletion is a step
        # of its own, so the line keeps it and its deadline stays open.
        check(p.lines()[p.line_of("Plan for the week.")] == bound and p.note().count("^d2") == 1,
              f"Ctrl+Z after a deletion takes back only the deletion ({p.lines()[p.line_of('Plan for the week.')]!r})")
        time.sleep(0.5)
        check(p.deadline(2)["status"] == "open", f"…and the binding's deadline is untouched ({p.deadline(2)})")
        # A line pasted back, tag and all, brings its deadline back.
        # (The Ctrl+D line, deleted for it.)
        p.call("removeLine", p.line_of("^d2"))
        check(p.wait(lambda: p.deadline(2)["status"] == "cancelled"), "deleting the Ctrl+D line cancels its deadline")
        p.call("cursor", p.offset_of_line(p.line_of("then")) + len(p.lines()[p.line_of("then")]))
        p.call("insert", "\n- [ ] Plan for the week. 📅 2030-01-01 ^d2")
        p.call("cursor", 1)
        check(p.wait(lambda: p.deadline(2)["status"] == "open" and "^d2" in p.note()),
              f"a bound line pasted in brings its deadline back ({p.deadline(2)}, {p.call('checkState')})")
        # A block with two of them: both, not the last one only.
        lo, hi = sorted((p.line_of("^d1"), p.line_of("^d2")))
        p.call("removeLines", lo, hi)
        check(p.wait(lambda: p.deadline(1)["status"] == "cancelled" and p.deadline(2)["status"] == "cancelled"),
              "deleting several bound lines cancels every one of their deadlines")
        check(p.wait(lambda: "2 deadlines" in p.call("hint")), f"…and says how many ({p.call('hint')!r})")

        # 6. changes made outside reach the lines when their note opens
        p.pomo("add", "from cli", "friday")
        p.pomo("add", "goes away", "friday")
        (p.daily / f"{YDAY}.md").write_text(header(YDAY) + "- [ ] from cli 📅 2030-01-01 ^d3\n- [ ] goes away 📅 2030-01-01 ^d4\n")
        p.check()   # the line is the task: the store takes its date
        p.pomo("done", "3")
        p.pomo("set", "3", "friday")
        p.pomo("rm", "4")
        p.call("openDay", YDAY)
        check(p.wait(lambda: "- [x] from cli 📅 2030-01-01" not in p.note(YDAY) and "- [x] from cli 📅 " in p.note(YDAY)),
              "a deadline done and moved elsewhere is ticked and redated on open")
        check(p.wait(lambda: "- [ ] goes away 📅 2030-01-01\n" in p.note(YDAY)), "one removed elsewhere keeps its date, loses its anchor")

        # 7. a store that cannot be read is unknown, not empty
        p.call("openDay", TODAY)
        p.wait(lambda: p.call("header").startswith(dt.date.today().strftime("%A")))
        p.store.replace(p.store.with_suffix(".away"))
        time.sleep(0.6)
        p.call("openDay", YDAY)
        time.sleep(1.5)
        check("^d3" in p.note(YDAY), f"with the store unreadable, opening a note keeps its anchors ({p.note(YDAY)!r})")
        p.store.with_suffix(".away").replace(p.store)

        # 8. an edit made outside the page while it is open is kept
        p.call("openDay", TODAY)
        p.wait(lambda: p.call("header").startswith(dt.date.today().strftime("%A")))
        f = p.daily / f"{TODAY}.md"
        f.write_text(f.read_text() + "written in obsidian\n")
        check(p.wait(lambda: "written in obsidian" in p.call("text")), "the page re-reads a note changed outside")
        p.call("cursorEnd")
        p.call("insert", "and then here")
        check(p.wait(lambda: "written in obsidian" in p.note() and "and then here" in p.note()), "…and its next save keeps both")
        tmpf = f.with_suffix(".tmp")
        tmpf.write_text(f.read_text() + "written by rename\n")
        tmpf.replace(f)
        check(p.wait(lambda: "written by rename" in p.call("text")), "…also when written by rename (atomic save)")
        # The line the keys are in, taken away outside (2026-11-17): its
        # field is rebuilt, and the keys went with it — every shortcut deaf
        # until a click. A line must still hold them.
        p.call("cursor", p.offset_of_line(p.line_of("written by rename")))
        check(json.loads(p.call("noteFocus"))["active"], "the keys are in the line about to go")
        f.write_text(f.read_text().replace("written by rename\n", ""))
        check(p.wait(lambda: "written by rename" not in p.call("text")), "the page re-reads a line taken away outside")
        kept = json.loads(p.call("noteFocus"))
        check(kept["active"], f"…and a line of the note still has the keys ({kept})")
        # Saves that overlap (2026-11-15): a save begun over one still on its
        # way was taken as landed when the older did, and the check read
        # the note a write too early (a line Ctrl+Z had just brought back
        # read cancelled, and its deadline was cancelled again).
        p.call("cursorEnd")
        p.call("insert", "\n")
        knew = p.call("saveBurst", "overlapping saves")
        check(knew == "true", f"a save that overtakes one still on its way is known to be on its way ({knew}): "
              "the check must not read the note before it lands")
        check(p.wait(lambda: p.note().rstrip().endswith("overlapping saves") and p.call("text").rstrip().endswith("overlapping saves")),
              f"saves that overlap: the last is what the file holds ({p.note()[-30:]!r} / {p.call('text')[-30:]!r})")
        time.sleep(1.0)
        check(p.note().rstrip().endswith("overlapping saves") and p.call("text").rstrip().endswith("overlapping saves"),
              f"…and the page stays on it, not on one of its own earlier saves ({p.note()[-30:]!r} / {p.call('text')[-30:]!r})")

        # 9. the popup's `o`: opening on a deadline's line
        p.open_fresh(json.dumps({"shape": "alongside", "goto": f"[[{YDAY}#^d3]]"}))
        check(p.wait(lambda: "from cli" in p.lines()[int(p.call("cursorLine"))]),
              f"goto opens the note on the deadline's line ({p.call('cursorLine')}, {p.lines()[:8]})")

        # 10. accepting an agent proposal binds the block's checkbox
        line = "- [ ] one-pager by friday"
        h = blocks.split(line)[0]["hash"]
        (p.vault / "agents" / "longhand" / "daily").mkdir(parents=True, exist_ok=True)
        (p.vault / "agents" / "longhand" / "daily" / f"{TODAY}.json").write_text(json.dumps({"blocks": {h: {
            "state": "reply", "reply": "Friday?", "read": True,
            "proposals": [{"kind": "deadline", "title": "one-pager", "when": "friday", "project": "DORO"}]}}}))
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + line + "\n")
        p.open_fresh()
        p.call("cursor", 3)
        time.sleep(0.4)
        p.call("acceptAt", 0)
        check(p.wait(lambda: "- [ ] one-pager 📅 " in p.note() and "^d" in p.note(), 8), "an accepted proposal binds its line, cue replaced")

        # 10b. a list is one submission: a proposal binds the line it is about,
        # wherever the cursor is, and is accepted once for the whole list
        lst = ["- [ ] Roles Planned by 30 oct", "- [ ] Initial paper by 30 nov", "- [ ] A0 poster"]
        hs = [blocks.split(l)[0]["hash"] for l in lst]
        props = [{"kind": "deadline", "title": "Roles planned", "when": "30 Oct", "project": "intsem"},
                 {"kind": "deadline", "title": "Initial paper", "when": "30 Nov", "project": "intsem"},
                 {"kind": "deadline", "title": "Conference", "when": "03 Feb", "project": "intsem"}]
        (p.vault / "agents" / "longhand" / "daily" / f"{TODAY}.json").write_text(json.dumps({"blocks": {
            h: {"state": "reply", "reply": "Dates.", "read": True, "group": hs, "proposals": props} for h in hs}}))
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "\n".join(lst) + "\n")
        p.open_fresh()
        before = len(p.store.read_text().splitlines())
        p.call("cursor", p.offset_of_line(p.line_of("Roles Planned")) + 8)
        time.sleep(0.4)
        p.call("acceptAt", 1)
        check(p.wait(lambda: "- [ ] Initial paper 📅 " in p.note() and "^d" in p.note(), 8),
              "accepted from the first item, a proposal binds the item it names")
        check("- [ ] Roles Planned by 30 oct\n" in p.note() and "- [ ] A0 poster\n" in p.note(), "…and leaves the others as written")
        p.call("cursor", p.offset_of_line(p.line_of("A0 poster")) + 8)
        time.sleep(0.4)
        p.call("acceptAt", 1)
        p.call("acceptAt", 2)
        # Both written before anything below touches the store (each is a
        # `pomo` of its own, later on Windows: one landing after the store
        # is written by hand below would write it back without that line);
        # then a moment more for a third that must not come.
        p.wait(lambda: len(p.store.read_text().splitlines()) >= before + 2, 8)
        time.sleep(1.5)
        check(len(p.store.read_text().splitlines()) == before + 2, "another item offers it no more; a proposal naming no line adds once")
        check("- [ ] A0 poster\n" in p.note() and "Conference" not in p.note(), "…and that one takes no line")

        # 10b'. a block's chat drops what is already there (2026-11-15): its
        # cards from the one list sit in the margin; Enter on "drop it" for a
        # deadline with no line cancels it in the store, as Del on its row
        # does; Del on a card declines it, in the one list.
        line = "- [ ] AI Literacy course"
        h = blocks.split(line)[0]["hash"]
        due = int(time.mktime((dt.date.today() + dt.timedelta(days=3)).timetuple())) + 86340
        p.store.write_text(p.store.read_text() + f"77\t{due}\tAI Literacy course\topen\t0\t\t\t\n")
        ledger_path = p.state / "longhand" / "proposals.json"
        led = json.loads(ledger_path.read_text()) if ledger_path.exists() else {"next": 1, "items": []}
        nid = led["next"]
        now_at = dt.datetime.now().isoformat(timespec="seconds")
        led["items"] += [{"kind": "drop", "key": "", "deadline": 77, "title": "AI Literacy course", "project": "",
                          "why": "a copy", "from": "margin", "id": nid, "status": "open", "at": now_at},
                         {"kind": "drop", "key": "", "deadline": 77, "title": "AI Literacy course (again)", "project": "",
                          "why": "asked twice", "from": "margin", "id": nid + 1, "status": "open", "at": now_at}]
        led["next"] = nid + 2
        ledger_path.write_text(json.dumps(led))
        cards = [{"kind": "drop", "key": "", "deadline": 77, "title": "AI Literacy course", "why": "a copy", "ledger": nid, "at": now_at},
                 {"kind": "drop", "key": "", "deadline": 77, "title": "AI Literacy course (again)", "why": "asked twice",
                  "ledger": nid + 1, "at": now_at}]
        (p.vault / "agents" / "longhand" / "daily" / f"{TODAY}.json").write_text(json.dumps({"blocks": {h: {
            "state": "reply", "reply": "Dropping the copy.", "read": True, "proposals": cards,
            "chat": [{"role": "student", "text": "remove the one from the 18th", "at": now_at},
                     {"role": "agent", "text": "Dropping the copy with no line.", "at": now_at, "proposals": [0, 1]}]}}}))
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + line + "\n")
        p.open_fresh()
        p.call("cursor", 3)
        p.call("refreshProposals")
        check(p.wait(lambda: [c["live"] for c in json.loads(p.call("marginListed"))] == [True, True], 8),
              f"a block's day and drop cards are open while the one list has them ({p.call('marginListed')})")
        p.call("declineAt", 1)
        check(p.wait(lambda: any(x["id"] == nid + 1 and x["status"] == "declined" for x in json.loads(ledger_path.read_text())["items"])),
              "Del on one declines it, in the one list")
        p.call("acceptAt", 0)
        check(p.wait(lambda: p.deadline(77)["status"] == "cancelled", 8),
              f"Enter on a drop of a deadline with no line cancels it in the store ({p.deadline(77)})")
        # The cards hear of it when the one list is read again, after the
        # ledger: both waited for.
        check(p.wait(lambda: any(x["id"] == nid and x["status"] == "accepted" for x in json.loads(ledger_path.read_text())["items"])
                     and json.loads(p.call("marginListed")) == [{"kind": "drop", "live": False, "state": "accepted"},
                                                                 {"kind": "drop", "live": False, "state": "declined"}]),
              f"…accepted in the one list, and both cards say how they were settled ({p.call('marginListed')})")
        check(line + "\n" in p.note(), "…and no note was written: it had no line")

        # 10c. ways to keep a date as words, and old lines left alone
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "- [ ] essay\n- [ ] old line by friday\nnext item\n")
        p.open_fresh()
        count = len(p.store.read_text().splitlines())
        p.call("cursor", p.offset_of_line(p.line_of("old line")) + 8)
        p.call("cursor", p.offset_of_line(p.line_of("next item")) + 2)
        time.sleep(1)
        check("old line by friday\n" in p.note() and len(p.store.read_text().splitlines()) == count,
              "moving through an old dated line does not bind it")
        p.call("cursor", p.offset_of_line(p.line_of("essay")) + len("- [ ] essay"))
        p.call("type", " by the 19th of Feb")
        p.call("ctrlD")
        check(p.call("pending", p.line_of("essay")) == "false", "Ctrl+D on a lit-up date keeps it as words")
        p.call("cursor", p.offset_of_line(p.line_of("next item")) + 2)
        # The words on disk first (a save can take longer than a second on
        # GitHub's Windows machine), then a moment for a binding that must
        # not come.
        p.wait(lambda: "essay by the 19th of Feb\n" in p.note(), 5)
        time.sleep(1)
        check("essay by the 19th of Feb\n" in p.note() and len(p.store.read_text().splitlines()) == count,
              f"…and leaving does not bind it ({[l for l in p.note().splitlines() if 'essay' in l]}, "
              f"store {len(p.store.read_text().splitlines())} lines for {count})")
        p.call("cursor", p.offset_of_line(p.line_of("essay")) + 8)
        p.call("ctrlD")
        check(p.wait(lambda: "- [ ] essay 📅 " in p.note() and "^d" in p.note()), "Ctrl+D again makes it the deadline")
        # Ctrl+Z right after a binding: the words come back, the deadline goes
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "- [ ] read ch.7\nnext item\n")
        p.open_fresh()
        count = len(p.store.read_text().splitlines())
        p.call("cursor", p.offset_of_line(p.line_of("read ch.7")) + len("- [ ] read ch.7"))
        p.call("type", " by tomorrow")
        p.call("cursor", p.offset_of_line(p.line_of("next item")) + 2)
        check(p.wait(lambda: "read ch.7 📅 " in p.note() and len(p.store.read_text().splitlines()) == count + 1), "bound as it was left")
        p.call("undo")
        check(p.wait(lambda: "- [ ] read ch.7 by tomorrow\n" in p.note() and len(p.store.read_text().splitlines()) == count),
              f"Ctrl+Z: the words are back and the deadline it made is gone ({p.note()[-60:]!r}; "
              f"store {len(p.store.read_text().splitlines())} lines for {count}: {p.store.read_text().splitlines()[-2:]}; "
              f"{p.call('checkState')})")
        p.call("cursor", p.offset_of_line(p.line_of("read ch.7")) + 8)
        p.call("cursor", p.offset_of_line(p.line_of("next item")) + 2)
        time.sleep(1)
        check("read ch.7 by tomorrow\n" in p.note(), "…and it is not bound again")

        # 10c, Tab: it takes a lit date there and then, and the line goes on
        # being written: typing right after it, before the store has
        # answered with the number, lands in the words and the number at
        # the end; Enter right after it steps over the date.
        TAB = 0x01000001
        # Offsets as the page counts them: 📅 is two UTF-16 units there.
        at = lambda i: sum(len(l.encode("utf-16-le")) // 2 + 1 for l in p.lines()[:i])
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "- [ ] call mum\nnext item\n")
        p.open_fresh()
        count = len(p.store.read_text().splitlines())
        p.call("cursor", p.offset_of_line(p.line_of("call mum")) + len("- [ ] call mum"))
        p.call("type", " by fri 17:00")
        check(p.call("pageKey", TAB, 0) == "true", "Tab on a lit date is taken")
        p.call("type", "about the trip")
        line = lambda: p.lines()[p.line_of("call mum")]
        check(p.wait(lambda: re.search(r"^- \[ \] call mum about the trip +📅 \d{4}-\d\d-\d\d 17:00 \^d\d+$", line())),
              f"…the date is the deadline, the words typed after Tab are the line's ({line()!r})")
        check(len(p.store.read_text().splitlines()) == count + 1, "…one deadline added")
        n = int(re.search(r"\^d(\d+)", line()).group(1))
        p.call("cursor", at(p.line_of("next item")) + 2)
        check(p.wait(lambda: p.deadline(n)["title"] == "call mum about the trip" and "call mum about the trip 📅 " in p.note()),
              f"left, its words are the deadline's title ({p.deadline(n)})")
        check(p.call("pageKey", TAB, 0) == "false", "Tab on a line with nothing lit is the line's own (nesting)")
        p.call("cursor", at(p.line_of("next item")) + len("next item"))
        p.call("enter")
        p.call("type", "- [ ] essay due mon")
        p.call("pageKey", TAB, 0)
        p.call("enter")
        p.call("type", "outline")
        check(p.wait(lambda: re.search(r"^- \[ \] essay 📅 \S+ \^d\d+$", p.lines()[p.line_of("essay")]) is not None),
              f"Enter right after Tab: the box keeps its date and number ({p.lines()[p.line_of('essay')]!r})")
        check(p.lines()[p.line_of("essay") + 1] == "- [ ] outline", f"…and the new line is the next box ({p.lines()[p.line_of('essay') + 1]!r})")
        # Ctrl+Z after Tab: the words come back, the deadline goes.
        p.call("cursor", at(p.line_of("outline")) + len("- [ ] outline"))
        p.call("type", " by tomorrow")
        count = len(p.store.read_text().splitlines())
        p.call("pageKey", TAB, 0)
        check(p.wait(lambda: re.search(r"outline +📅 \S+ \^d\d+", p.call("text")) is not None and len(p.store.read_text().splitlines()) == count + 1),
              "Tab binds it")
        p.call("undo")
        check(p.wait(lambda: "- [ ] outline by tomorrow\n" in p.note() and len(p.store.read_text().splitlines()) == count),
              "Ctrl+Z after Tab: the words are back and the deadline it made is gone")
        # Enter at the end of a bound line's words: the new line, and the
        # cursor in it (until 2026-10-27 the cursor stayed behind).
        p.call("cursor", at(p.line_of("essay")) + len("- [ ] essay"))
        p.call("enter")
        p.call("type", "bound too")
        check(p.lines()[p.line_of("essay") + 1] == "- [ ] bound too", f"Enter after a bound line's words: typing goes on in the new line ({p.lines()[p.line_of('essay') + 1]!r})")

        # 10e. a list written with dates: every item is bound as it is left,
        # and the list goes to the agent only after that
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "Dates\n")
        p.open_fresh()
        p.call("cursorEnd")
        p.call("enter")
        for item in ("Roles planned by 30 oct", "Initial paper by 30 nov", "final paper by 15 jan"):
            p.call("type", ("- [ ] " if item.startswith("Roles") else "") + item)
            p.call("enter")
        p.call("enter")   # the empty item: leaving the list
        # The send prompt went on 2026-10-15: leaving a list interrupts
        # nothing, and the dates bind all the same.
        check(p.call("ask") == "null", "leaving the list asks nothing")
        check(p.wait(lambda: p.call("text").count(" ^d") == 3), "…and every dated item is bound")
        text = p.call("text")
        check("by 30 oct" not in text and "by 15 jan" not in text,
              f"…with its cue words gone ({text.count(' ^d')} of 3)")
        # The header's "chat" is the visible way in, on the same path as
        # Ctrl+Enter: it reads the sign on the block under the cursor.
        p.call("cursor", p.offset_of_line(p.line_of("Initial paper")) + 10)
        check(p.wait(lambda: p.call("sign") == "checkbox"), f"a box is a sign the header can see ({p.call('sign')})")
        p.call("cursor", 1)
        check(p.wait(lambda: p.call("sign") == ""), "a line with no sign offers nothing")
        p.call("askNow")
        check(p.wait(lambda: json.loads(p.call("panes"))["right"] == "margin") and p.call("ask") == "null",
              f"…and chatting anyway opens its chat, the box ready, nothing sent ({p.call('panes')})")
        p.call("closePanes")

        # 10d. one line, one deadline: the page's own binding and the agent's
        # proposal for the same line do not make two, in either order
        p.pomo("add", "Canvas course and thesis suggestions", "today")   # accepted, not yet bound
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "- [ ] Take a look into the Canvas course and thesis suggestions\nnext\n")
        p.open_fresh()
        count = len(p.store.read_text().splitlines())
        p.call("cursor", p.offset_of_line(p.line_of("Canvas")) + len("- [ ] Take a look into the Canvas course and thesis suggestions"))
        p.call("type", " by today")
        p.call("cursor", p.offset_of_line(p.line_of("next")) + 2)
        check(p.wait(lambda: "suggestions 📅 " in p.note() and "^d" in p.note()) and len(p.store.read_text().splitlines()) == count,
              "written and left, it binds the deadline already there, adds none")
        line = next(l for l in p.lines() if "Canvas" in l)
        h = blocks.split(line)[0]["hash"]
        (p.vault / "agents" / "longhand" / "daily" / f"{TODAY}.json").write_text(json.dumps({"blocks": {h: {
            "state": "reply", "reply": "Today?", "read": True,
            "proposals": [{"kind": "deadline", "title": "Take a look into the Canvas course and thesis suggestions",
                           "when": f"today ({dt.date.today():%Y-%m-%d})", "project": "respro"}]}}}))
        p.call("cursor", p.offset_of_line(p.line_of("Canvas")) + 8)
        time.sleep(0.4)
        p.call("acceptAt", 0)
        time.sleep(1.5)
        check(len(p.store.read_text().splitlines()) == count, "accepting the agent's proposal for it afterwards adds none either")

        # 11. projects in the sidebar: the tags that exist, a class started
        pd = p.vault / "agents" / "longhand" / "knowledge" / "projects"
        pd.mkdir(parents=True, exist_ok=True)
        soon = dt.date.today() + dt.timedelta(days=1)
        (pd / "intsem.md").write_text(f"# Interdisciplinary Seminar\n\n- Tag: `#intsem`\n  - {soon:%a %d %b}: 10:45–12:15 (Gold)\n")
        (pd / "dtm.md").write_text("# Design Theory & Methods\n\n- Tag: `#dtm`\n")
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "Morning notes.\n")
        p.open_fresh()
        p.call("openDay", YDAY)
        p.wait(lambda: p.call("header") != "" and not p.call("header").startswith(dt.date.today().strftime("%A")))
        p.call("sidebar")
        check(p.wait(lambda: json.loads(p.call("projects")) == ["intsem|tomorrow 10:45 · Gold", "dtm|"]),
              f"the sidebar lists the projects, soonest first ({p.call('projects')})")
        p.call("startClass", 0)
        check(p.wait(lambda: p.note().endswith("Morning notes.\n\n# Interdisciplinary Seminar #intsem\n")),
              "starting a class from another day writes its heading at the end of today's note")
        check(p.call("header").startswith(dt.date.today().strftime("%A")) and int(p.call("cursorLine")) == len(p.lines()) - 1,
              "…opens today with the cursor under it")
        p.call("insert", "first point")
        check(p.call("projectKey", 1, 0x01000004, 0x04000000) == "true", "Ctrl+Enter on a project in the sidebar is taken")
        check(p.wait(lambda: "first point #dtm " in p.call("text")), "…and puts just its tag at the cursor")

        # 11b. a project's notes: every section of its tag, newest first,
        # opened in place. The claiming rule is the runner's; what matters
        # here is that the list is right and Enter lands on the heading.
        p.call("closeAll")
        (p.daily / f"{YDAY}.md").write_text(
            header(YDAY)
            + "# Interdisciplinary Seminar #intsem\nGabriel on sovereignty\n"
            + "## Learning goals\n- [ ] send the email\n"
            + "# Design Theory & Methods #dtm\n## Methods\nnot intsem's\n")
        (p.daily / f"{TODAY}.md").write_text(
            header(TODAY) + "Morning notes.\n\n# Interdisciplinary Seminar #intsem\n## Today's seminar\nthe second week\n")
        p.open_fresh()
        p.call("sidebar")
        p.wait(lambda: len(json.loads(p.call("projects"))) == 2)
        # Enter on a project opens its notes; writing into the note is the
        # shifted pair (inverted 2026-10-15).
        p.call("projectEnter", 0, "false", "false")
        check(p.wait(lambda: len(json.loads(p.call("sections"))) == 2),
              f"the project's sections, both days ({p.call('sections')})")
        se = json.loads(p.call("sections"))
        check(se[0].startswith(TODAY) and se[1].startswith(YDAY), f"newest first ({se})")
        check(se[0].split("|")[1] == "Interdisciplinary Seminar", f"the heading without its tag ({se[0]})")
        check(se[0].split("|")[2] == "Today's seminar" and "Learning goals" in se[1],
              f"what is under it, as its index ({se})")
        check("Methods" not in p.call("sections"), "another H1's section is not in the list")
        check(json.loads(p.call("panel"))["project"] is True and json.loads(p.call("panel"))["margin"] is False,
              "the project is in the sidebar, and the agent's margin stays shut")
        p.call("openSection", 1)
        check(p.wait(lambda: p.call("header") != "" and not p.call("header").startswith(dt.date.today().strftime("%A"))),
              "Enter on an older section opens its day")
        check(p.wait(lambda: p.lines()[int(p.call("cursorLine"))] == "# Interdisciplinary Seminar #intsem"),
              f"…with the cursor on that section's heading ({p.lines()[int(p.call('cursorLine'))]!r})")
        check(json.loads(p.call("panel"))["project"] is True,
              "…and the list stays, as the calendar does after opening a day")
        # Only the project's part of that day is drawn (Focus.js, 2026-11-11).
        check(p.wait(lambda: p.call("focusTag") == "intsem"), f"…and only #intsem's part of it is drawn ({p.call('focusTag')!r})")
        shown = json.loads(p.call("shownLines"))
        check("# Interdisciplinary Seminar #intsem" in shown and "- [ ] send the email" in shown
              and "## Methods" not in shown and "not intsem's" not in shown,
              f"…its section, not the other course's ({shown})")
        p.call("unfocus")
        check(p.call("focusTag") == "" and "## Methods" in json.loads(p.call("shownLines")), "…and the whole day comes back")
        p.call("toggleFocus")
        check(p.call("focusTag") == "intsem", "the key focuses on the section the cursor is in")
        # The list follows the note (2026-11-11): what is written in the
        # section shows in its row once saved, the highlight still on it.
        t = p.call("text")
        p.call("cursor", t.index("- [ ] send the email") + len("- [ ] send the email"))
        p.call("insert", "\n- [ ] read the paper")
        check(p.wait(lambda: json.loads(p.call("sectionCounts"))[1:] == ["2 open"]),
              f"a box written in the section is counted in the project's list ({p.call('sectionCounts')})")
        check(p.call("sectionFocus") == "1", f"…the highlight still on that day's section ({p.call('sectionFocus')})")
        p.call("unfocus")
        p.call("leaveProject")
        check(p.wait(lambda: json.loads(p.call("sections")) == []), "← goes back to the projects")
        before = p.note()
        check(p.call("projectKey", 0, 0x53, 0) == "false" and p.note() == before,
              "s on a project writes nothing now (letters find a project)")
        check(p.call("projectKey", 0, 0x01000004, 0x02000000) == "true", "Shift+Enter on a project is taken")
        check(p.wait(lambda: p.note().rstrip().endswith("# Interdisciplinary Seminar #intsem")),
              "…and starts a new section for it")
        check(json.loads(p.call("panel"))["project"] is False, "…and does not open the project")
        p.call("openProject", 1)
        check(p.wait(lambda: json.loads(p.call("sections")) == [f"{YDAY}|Design Theory & Methods|Methods"]),
              f"the other project has its own one ({p.call('sections')})")
        p.open_fresh()
        check(json.loads(p.call("panel"))["margin"] is False,
              "a page opened from nothing shows the note alone, not the last panel")

        # 11c. private: the note the agent may not see. The mark is one line
        # of frontmatter, because that is what the runner reads; the page
        # never offers the agent while it is there.
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "Dear diary.\n")
        p.open_fresh()
        check(p.call("isPrivate") == "false" and p.call("agentOn") == "true", "a note starts open to the agent")
        p.call("togglePrivate")
        check(p.wait(lambda: p.call("isPrivate") == "true"), "the header's word marks the note private")
        check(p.wait(lambda: p.note().startswith("---\nagent: false\n---\n")),
              f"…by writing the line the runner reads ({p.note()[:40]!r})")
        check("Dear diary." in p.note() and "|agent]]" in p.note(), "…leaving the note and its link line alone")
        check(p.call("agentOn") == "false", "…and the page stops offering the agent at all")
        # The plan and the briefs are passes of their own, started when the
        # page opened; one may still be writing its payload a second later
        # (on Windows, where the agent is slower to start, it was): not an
        # ask, so not counted.
        def asked():
            pl = p.state / "longhand" / "payloads"
            return {x.name for x in pl.glob("*") if not re.search(r"-(plan|brief-[\d-]+)\.md$", x.name)} if pl.is_dir() else set()
        before = asked()
        p.call("cursorEnd")
        p.call("type", " Is this ok?")
        p.call("askNow")
        time.sleep(1)
        after = asked()
        check(after == before, f"asking on a private note runs nothing ({len(before)} → {len(after)}: {sorted(after - before)})")
        p.call("togglePrivate")
        check(p.wait(lambda: p.call("isPrivate") == "false"), "turning it off puts the day back")
        check(p.wait(lambda: not p.note().startswith("---")), f"…with no frontmatter left behind ({p.note()[:20]!r})")

        # 11d. `@` calls a project, the same vocabulary as the sidebar's list
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "Notes.\n")
        p.open_fresh()
        p.wait(lambda: len(json.loads(p.call("projects"))) == 2)
        p.call("cursorEnd")
        p.call("type", "today in @")
        check(p.wait(lambda: json.loads(p.call("mention")) == ["intsem", "dtm"]),
              f"@ offers the projects ({p.call('mention')})")
        check(p.wait(lambda: json.loads(p.call("room"))["row"] == p.line_of("today in @")),
              f"…in room the line opens under it, nothing drawn over ({p.call('room')})")
        p.call("type", "dt")
        check(p.wait(lambda: json.loads(p.call("mention")) == ["dtm"]), f"…narrowing as you type ({p.call('mention')})")
        p.call("mentionPick", 0, "false")
        check(p.wait(lambda: "today in #dtm " in p.call("text")), f"Enter writes its tag where the @ was ({p.call('text')[-30:]!r})")
        check(p.call("mention") == "null", "…and the list is done")
        check(p.wait(lambda: json.loads(p.call("room"))["row"] == -1), "…and the room it opened closes")
        p.call("enter")
        p.call("type", "@ints")
        check(p.wait(lambda: json.loads(p.call("mention")) == ["intsem"]), "@ at a line's start offers the same")
        p.call("mentionPick", 0, "true")
        check(p.wait(lambda: "# Interdisciplinary Seminar #intsem" in p.call("text")),
              f"Shift+Enter starts the class there ({p.call('text')[-40:]!r})")
        p.call("enter")
        p.call("type", "mail me at pedro@it")
        check(p.call("mention") == "null", "an address is not a call")

        # `#` offers the tags that exist (2026-10-18): the projects', then the
        # ones written in the notes; not for a heading, not for a tag done.
        p.call("enter")
        p.call("type", "#")
        time.sleep(0.3)
        check(p.call("mention") == "null", "a lone # (a heading on its way) offers nothing")
        p.call("type", "d")
        check(p.wait(lambda: (json.loads(p.call("mention")) or [""])[0] == "dtm"),
              f"#d offers the tags that exist, the one starting so first ({p.call('mention')})")
        p.call("mentionPick", 0, "true")
        check(p.wait(lambda: p.call("text").endswith("#dtm ")), f"…Enter (even shifted) writes it ({p.call('text')[-20:]!r})")
        p.call("type", "and #intsem")
        time.sleep(0.3)
        check(p.call("mention") == "null", "…and a tag written in full is left as it is: Enter stays a new line")

        # 11d'. making a project (2026-10-22): when nothing matches, a tag
        # nothing goes by yet. Under `@` Enter makes it; under `#` the row
        # waits for ↓, so Enter stays a new line. The runner writes its file.
        pd = p.vault / "agents" / "longhand" / "knowledge" / "projects"
        KEY_DOWN, KEY_ENTER = 0x01000015, 0x01000004
        p.call("enter")
        p.call("type", "for the @thes")
        check(p.wait(lambda: json.loads(p.call("mention")) == ["+thes"]) and int(p.call("mentionFocus")) == 0,
              f"@ with nothing matching offers to make it, ready for Enter ({p.call('mention')})")
        p.call("type", "is")
        check(p.wait(lambda: json.loads(p.call("mention")) == ["+thesis"]), "…as you type on")
        p.call("mentionPick", 0, "false")
        check(p.wait(lambda: (json.loads(p.call("askingName")) or {}).get("tag") == "thesis"), "Enter asks its name")
        check(p.wait(lambda: json.loads(p.call("room"))["row"] == p.line_of("for the @thesis")),
              f"…under the line, in the room it opens ({p.call('room')})")
        p.call("projectName", "Master Thesis")
        check(p.wait(lambda: "for the #thesis " in p.call("text")), f"the tag is written where the @ was ({p.call('text')[-30:]!r})")
        check(p.wait(lambda: (pd / "thesis.md").exists()) and (pd / "thesis.md").read_text() == "# Master Thesis\n\n- Tag: `#thesis`\n",
              "…and the project made, its name as given")
        check(p.wait(lambda: any(x.startswith("thesis|") for x in json.loads(p.call("projects")))), "…in the projects the sidebar lists")
        check(p.wait(lambda: p.call("hint") == "#thesis is a project now"), f"…and says so ({p.call('hint')!r})")
        p.call("enter")
        p.call("type", "an idea #bikes")
        check(p.wait(lambda: json.loads(p.call("mention")) == ["+bikes"]) and int(p.call("mentionFocus")) == -1,
              f"a new # offers it too, waiting ({p.call('mention')}, {p.call('mentionFocus')})")
        check(p.call("keyPage", KEY_ENTER, 0) == "false", "…Enter is still the note's")
        check(p.call("keyPage", KEY_DOWN, 0) == "true" and int(p.call("mentionFocus")) == 0, "↓ chooses it")
        p.call("keyPage", KEY_ENTER, 0)
        check(p.wait(lambda: (json.loads(p.call("askingName")) or {}).get("tag") == "bikes"), "…then Enter asks its name")
        p.call("closeProjectName")
        time.sleep(0.4)
        check(p.call("askingName") == "null" and "an idea #bikes" in p.call("text") and not (pd / "bikes.md").exists(),
              "Esc leaves the tag as written, and makes nothing")
        p.call("type", " #12")
        time.sleep(0.3)
        check(p.call("mention") == "null", "a tag that is a number is never offered as a project")
        p.call("sidebarProject", "Bikeability in Linz #bikes")
        check(p.wait(lambda: (pd / "bikes.md").exists()) and (pd / "bikes.md").read_text() == "# Bikeability in Linz\n\n- Tag: `#bikes`\n"
              and p.call("addingProject") == "false", "the sidebar's field makes one: its name, and its #tag")
        # Made and read back before the next: its file is written before the
        # runner ends, and one asked meanwhile is "still making the last one"
        # (a slower end on Windows; 2026-11-25 on GitHub's machine).
        p.wait(lambda: any(t.startswith("bikes|") for t in json.loads(p.call("projects"))), 10)
        p.call("sidebarProject", "#DTM")
        check(p.wait(lambda: p.call("hint") == "#DTM is a project already"), f"…never one that exists ({p.call('hint')!r})")
        for f in ("thesis.md", "bikes.md"):
            (pd / f).unlink()

        # 11e. emphasis: Ctrl+B writes the markers the file keeps, and the
        # sidebar moved to the shifted pair to make room for it.
        CTRL, SHIFT, KEY_B = 0x04000000, 0x02000000, 0x42
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "read chapter seven\n")
        p.open_fresh()
        p.call("cursor", p.offset_of_line(p.line_of("read chapter")) + 9)
        check(p.call("keyPage", KEY_B, CTRL) == "true", "Ctrl+B is taken by the note")
        check(p.wait(lambda: "read **chapter** seven" in p.call("text")),
              f"…and bolds the word under the cursor ({p.call('text')!r})")
        check(json.loads(p.call("panel"))["project"] is False and p.call("keyPage", 0x5c, CTRL) == "true",
              "Ctrl+\\ is taken too")
        check(p.wait(lambda: "**chapter**" in p.note()), "…and does not touch the words")
        # Words selected inside one line are the field's own selection, not
        # the editor's: they are what is wrapped, never the word after them
        # (2026-11-04), and a space at the edge stays outside the markers.
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "Many biases are available\n")
        p.open_fresh()
        at = p.offset_of_line(p.line_of("Many biases"))
        p.call("selectInLine", at + 5, at + 16)
        p.call("keyPage", KEY_B, CTRL)
        check(p.wait(lambda: "Many **biases are** available" in p.call("text")),
              f"Ctrl+B bolds the words selected in a line, its space left out ({p.call('text')!r})")
        p.call("selectInLine", at, at + 5)
        p.call("keyPage", 0x49, CTRL)
        check(p.wait(lambda: "*Many* **biases are** available" in p.call("text")),
              f"…and Ctrl+I makes them italic the same way ({p.call('text')!r})")

        # 11e'. Ctrl+K makes a link (2026-10-28): words selected become its
        # text and the cursor waits between the parentheses for the address;
        # with none, `[]()` and the cursor between the brackets.
        KEY_K = 0x4b
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "see the reading list\n")
        p.open_fresh()
        at = p.offset_of_line(p.line_of("see the reading"))
        p.call("selectSpan", at + 8, at + 20)
        check(p.call("keyPage", KEY_K, CTRL) == "true", "Ctrl+K is taken by the note")
        check(p.wait(lambda: "see the [reading list]()" in p.call("text")), f"…and makes the words selected a link ({p.call('text')!r})")
        check(int(p.call("cursorAt")) == at + 23, f"…the cursor between its parentheses ({p.call('cursorAt')} vs {at + 23})")
        p.call("cursorEnd")
        end = int(p.call("cursorAt"))
        p.call("keyPage", KEY_K, CTRL)
        check(p.wait(lambda: p.call("text")[end:end + 4] == "[]()") and int(p.call("cursorAt")) == end + 1,
              f"…with nothing selected, an empty one and the cursor between the brackets ({p.call('text')[-12:]!r}, {p.call('cursorAt')})")
        p.call("closeAll")                 # closing saves the link just made: write after it
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "see the reading list\n")
        p.open_fresh()
        p.call("selectInLine", at + 8, at + 20)
        p.call("keyPage", KEY_K, CTRL)
        check(p.wait(lambda: "see the [reading list]()" in p.call("text")) and int(p.call("cursorAt")) == at + 23,
              f"…and words selected inside one line are its text too ({p.call('text')!r}, {p.call('cursorAt')})")

        # 11f. emphasis, drawn: the markers go to nothing and the words
        # carry the weight, while the field underneath still holds the line
        # character for character — every offset in the editor counts on it.
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "read **chapter** seven\nplain 2 * 3 line\n")
        p.open_fresh()
        rich = json.loads(p.call("drawn", p.line_of("read **chapter**")))
        check(rich["rich"] is True, "a line with emphasis is drawn, not shown")
        check(rich["plain"] == "read **chapter** seven" and rich["len"] == 22,
              f"…over the line as it is on disk ({rich!r})")
        flat = json.loads(p.call("drawn", p.line_of("plain 2 *")))
        check(flat["rich"] is False, "arithmetic is not emphasis")
        # Break the pair and the markers come back: that is how you edit them.
        # A marker is one thing to the cursor: it never stands inside one.
        at = p.offset_of_line(p.line_of("read **chapter**"))
        for asked, rests, why in ((at + 6, at + 7, "between the opening stars"),
                                  (at + 5, at + 7, "before them"),
                                  (at + 15, at + 14, "between the closing stars"),
                                  (at + 16, at + 14, "after them")):
            p.call("cursor", asked)
            got = int(p.call("cursorAt"))
            check(got == rests, f"a cursor put {why} rests against the words ({got} vs {rests})")

        star = p.offset_of_line(p.line_of("read **chapter**")) + 15
        p.call("erase", star, star + 1)           # one star of the closing pair
        check(p.wait(lambda: "read **chapter* seven" in p.call("text")),
              f"a marker can be deleted ({p.call('text')!r})")
        check(p.wait(lambda: json.loads(p.call("drawn", p.line_of("read **chapter*")))["rich"] is False),
              "…and a broken pair shows itself again")

        # 11f'. arrows, drawn: `->`, `<-` and `<->` show as one arrow each,
        # the file keeps what was typed, and the cursor takes each arrow as
        # the one character it looks like.
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "home -> work <- bed <-> sofa `a->b`\n")
        p.open_fresh()
        line = p.line_of("home ->")
        arrows = json.loads(p.call("drawn", line))
        check(arrows["rich"] is True and arrows["plain"] == "home -> work <- bed <-> sofa `a->b`" and arrows["len"] == 35,
              f"a line with arrows is drawn over the line as it is on disk ({arrows!r})")
        check("\u2192" in p.call("shown", line) and "\u2190" in p.call("shown", line) and "\u2194" in p.call("shown", line)
              and "a-&gt;b" in p.call("shown", line), f"…as →, ← and ↔, never in code ({p.call('shown', line)!r})")
        at = p.offset_of_line(line)
        for asked, rests, why in ((at + 6, at + 7, "inside ->"), (at + 21, at + 23, "inside <->")):
            p.call("cursor", asked)
            got = int(p.call("cursorAt"))
            check(got == rests, f"a cursor put {why} rests after it ({got} vs {rests})")
        p.call("cursor", at + 7)
        check(p.call("lineKey", 0x01000003, 0) == "true"
              and p.wait(lambda: "home  work <- bed" in p.call("text")), f"Backspace takes the arrow whole ({p.call('text')!r})")
        p.call("cursor", p.offset_of_line(line) + 18)
        check(p.call("lineKey", 0x01000007, 0) == "true"
              and p.wait(lambda: "bed  sofa" in p.call("text")), f"…and so does Delete ({p.call('text')!r})")
        p.call("cursor", p.offset_of_line(line) + 4)
        p.call("typeField", "!")
        check(p.wait(lambda: "home!  work <- bed" in p.call("text")), f"typing beside an arrow keeps it as typed ({p.call('text')!r})")

        # 11g. the agent, away: asking marks the block from the moment of the
        # ask and the mark goes when the answer is back. The page used to
        # look identical whether a pass was in flight or had died.
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "@ what did I say about reviews?\n")
        p.open_fresh()
        p.call("cursor", p.offset_of_line(p.line_of("@ what")) + 2)
        check(p.wait(lambda: p.call("sign") != ""),
              f"the block carries a sign for the agent ({p.call('sign')!r})")
        p.call("askNow")
        check(p.wait(lambda: "sending" in p.call("marks"), 4), f"asking marks the block ({p.call('marks')})")
        check(p.wait(lambda: "sending" not in p.call("marks"), 8), "…and the mark goes when it is back")

        # 11h. the conversation. A block the agent has answered is not asked
        # again: Ctrl+Enter opens the chat on it, cursor in the box. The
        # hash is of the block's text, so an unchanged block would send the
        # identical question and — a run overwrites the record — throw the
        # first answer away (2026-10-15).
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "@ what should I read first?\n")
        p.open_fresh()
        p.call("cursor", p.offset_of_line(p.line_of("@ what")) + 2)
        p.wait(lambda: p.call("sign") != "")
        p.call("sendChat", "is there a shorter way?")
        check(json.loads(p.call("chat")) == ["student: is there a shorter way?"],
              f"the message is in the chat at once ({p.call('chat')})")
        check(p.call("answering") == "true", "…with the agent thinking under it")
        check(p.wait(lambda: "agent: stub answer to: is there a shorter way?" in p.call("chat"), 8),
              f"…and the answer lands there ({p.call('chat')})")
        check(json.loads(p.call("chat")).count("student: is there a shorter way?") == 1
              and p.call("heldTurn") == "null",
              f"…the held turn let go of, never drawn twice ({p.call('chat')})")
        check(p.wait(lambda: p.call("answering") == "false"), "…and the thinking stops")
        # Stopped mid-answer (2026-11-18, plan item 22's "stop"): "thinking"
        # says how to stop it; Esc in the box ends the run, what was sent is
        # back in the box, nothing is written, and Esc again backs out.
        p.call("sendChat", "and the long version?")
        stop = json.loads(p.call("stopShown"))
        check(p.call("answering") == "true" and p.call("thinkingSays").startswith("thinking")
              and stop["square"] and stop["placeholder"] == "Esc stops",
              f"thinking, a stop square in the box, and the empty box says Esc stops ({stop})")
        p.call("chatBoxKey", 0x01000000)          # Esc in the box while it thinks
        check(p.wait(lambda: p.call("answering") == "false", 2), "Esc in the box while it thinks stops it at once")
        check(p.call("chatBoxText") == "and the long version?" and "back in the box" in p.call("hint"),
              f"…what was sent is back in the box, and the page says so ({p.call('chatBoxText')!r}, {p.call('hint')!r})")
        time.sleep(2.5)
        check("and the long version?" not in p.call("chat"), f"…and nothing was written ({p.call('chat')})")
        p.call("chatBoxClear")
        # …and with the mouse: the pill beside "thinking" does the same.
        p.call("sendChat", "or the short one?")
        check(p.call("answering") == "true", "another message: thinking")
        p.call("clickStop")
        check(p.wait(lambda: p.call("answering") == "false", 2) and p.call("chatBoxText") == "or the short one?"
              and not json.loads(p.call("stopShown"))["square"],
              f"a click on the square stops it too, the words back in the box, the square gone ({p.call('chatBoxText')!r})")
        p.call("chatBoxClear")
        # Answered while its run is still ending (its process closing, most
        # of a second on Windows; here the stub lingers): the thinking stops
        # with the answer, and Esc in the box stops nothing (2026-11-25: it
        # stopped the finished run and put the message back in the box).
        (p.stub / "linger").write_text("")
        p.call("sendChat", "and once more?")
        check(p.wait(lambda: "agent: stub answer to: and once more?" in p.call("chat"), 10)
              and p.call("answering") == "false" and not json.loads(p.call("stopShown"))["square"],
              f"answered while its run still ends: no more thinking, no stop square ({p.call('answering')}, {p.call('stopShown')})")
        hint, ending = p.call("hint"), p.call("runnerRunning")
        p.call("chatBoxKey", 0x01000000)
        check(ending == "true" and p.call("hint") == hint and p.call("chatBoxText") == ""
              and "agent: stub answer to: and once more?" in p.call("chat"),
              f"…and Esc there, the run still ending ({ending}), stops nothing: the answer stays, the box empty "
              f"({p.call('hint')!r}, {p.call('chatBoxText')!r})")
        (p.stub / "linger").unlink()
        p.wait(lambda: p.call("runnerRunning") == "false", 6)    # the lingering run ends

        before = len(list((p.state / "longhand" / "payloads").glob("*"))) \
            if (p.state / "longhand" / "payloads").is_dir() else 0
        p.call("askNow")
        time.sleep(1)
        after = len(list((p.state / "longhand" / "payloads").glob("*"))) \
            if (p.state / "longhand" / "payloads").is_dir() else 0
        check(after == before, f"asking an answered block runs nothing again ({before} → {after})")
        check(json.loads(p.call("panel"))["margin"] is True, "…it opens the conversation instead")
        check(p.call("chatFocused") == "true", "…with the cursor in the box")
        # Alt+→ in the note with nothing to its right: the block's own
        # conversation, as before the panes (brought back 2026-10-25), and
        # nothing sent.
        p.call("marginOpen", "false")
        p.call("cursor", p.call("cursorAt"))
        check(p.wait(lambda: json.loads(p.call("panel"))["margin"] is False), "the margin closed")
        check(p.call("keyPage", 0x01000014, 0x08000000) == "true" and json.loads(p.call("panel"))["margin"] is True,
              "Alt+→ in the note, nothing to its right: the block's conversation opens")
        after2 = len(list((p.state / "longhand" / "payloads").glob("*")))
        check(after2 == after, f"…without asking anything ({after} → {after2})")

        # 11i. a box answered, then ticked, is the same block to its
        # conversation: found by its words, whatever its box and facts
        # (2026-10-17). It used to vanish with the tick.
        q = "- [ ] should I buy a scooter?"
        qh = blocks.split(q)[0]["hash"]
        (p.vault / "agents" / "longhand" / "daily" / f"{TODAY}.json").write_text(json.dumps({"blocks": {qh: {
            "state": "reply", "reply": "What would you use it for?", "read": True, "head": q,
            "chat": [{"role": "student", "text": "commuting"}, {"role": "agent", "text": "a bike will do"}]}}}))
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + q + "\n")
        p.open_fresh()
        p.call("cursor", p.offset_of_line(p.line_of("scooter")) + 8)
        check(p.wait(lambda: p.call("reply") == "What would you use it for?"), "an answered box shows its reply")
        # The student's word on it (the improvement loop): from the margin,
        # kept on the block; the same word again takes it back.
        day_state = p.vault / "agents" / "longhand" / "daily" / f"{TODAY}.json"
        rating = lambda: (json.loads(day_state.read_text())["blocks"][qh].get("rating") or {}).get("value")
        p.call("rate", "down")
        check(p.wait(lambda: rating() == "down"), "a reply rated not helpful from the margin is kept on its block")
        p.call("rate", "down")
        check(p.wait((lambda: rating() is None)), "…and the same word again takes it back")
        p.call("tick", p.line_of("scooter"))
        check(p.wait(lambda: "- [x] should I buy a scooter?" in p.call("text")), "…ticked")
        check(p.wait(lambda: p.call("reply") == "What would you use it for?") and p.call("askWord") == "reply",
              f"…and the ticked box still has its conversation ({p.call('reply')!r}, {p.call('askWord')})")
        check("reply" in p.call("marks"), f"…still marked as answered ({p.call('marks')})")
        p.call("sendChat", "and in winter?")
        check(p.wait(lambda: "agent: stub answer to: and in winter?" in p.call("chat"), 8)
              and "agent: a bike will do" in p.call("chat"),
              f"…and talking to it carries on the same conversation ({p.call('chat')})")
        p.call("cursor", p.offset_of_line(p.line_of("scooter")) + len(p.lines()[p.line_of("scooter")]))
        p.call("insert", " ⏫")
        p.call("cursor", p.offset_of_line(p.line_of("scooter")) + 8)
        check(p.wait(lambda: "scooter? ⏫" in p.call("text")) and p.wait(lambda: "agent: a bike will do" in p.call("chat")),
              f"…a priority set on it leaves it too ({p.lines()[p.line_of('scooter')]!r})")
        p.call("cursor", p.offset_of_line(p.line_of("scooter")) + len("- [x] should I buy a scooter?"))
        p.call("insert", " now")
        p.call("cursor", p.offset_of_line(p.line_of("scooter")) + 8)
        # Its words changed (2026-10-18): still the block its conversation is
        # about, carried on its line in the layer (threads.json).
        check(p.wait(lambda: "scooter? now ⏫" in p.call("text")) and p.wait(lambda: p.call("askWord") == "reply")
              and "agent: a bike will do" in p.call("chat"),
              f"…and so do other words: the conversation stays ({p.lines()[p.line_of('scooter')]!r}, {p.call('askWord')})")
        threads = p.state / "longhand" / "threads.json"
        check(p.wait(lambda: threads.exists() and qh in threads.read_text() and "should I buy a scooter? now" in threads.read_text()),
              "…kept in the layer by the line's new words, never in the note")
        p.call("closeAll")
        p.open_fresh()
        p.call("cursor", p.offset_of_line(p.line_of("scooter")) + 8)
        check(p.wait(lambda: p.call("askWord") == "reply") and p.wait(lambda: "agent: a bike will do" in p.call("chat")),
              "…and found again when the note is opened again")

        # 11j. what the page shows under a line opens room there: Ctrl+D's
        # "when?" pushes the next line down rather than covering it, and a
        # passing word goes to the header's status line (2026-10-17).
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "- [ ] first\n- [ ] second\n")
        p.open_fresh()
        a, b = p.line_of("first"), p.line_of("second")
        p.call("cursor", p.offset_of_line(a) + 6)
        time.sleep(0.3)
        before = float(p.call("rowY", b))
        p.call("ctrlD")
        check(p.wait(lambda: json.loads(p.call("room"))["row"] == a), f"Ctrl+D opens room under its line ({p.call('room')})")
        def below():
            rm = json.loads(p.call("room"))
            after = float(p.call("rowY", b))
            return after >= before + rm["height"] - 1 and after >= rm["top"] + rm["height"] - 1
        check(p.wait(below, 3), f"…and the next line moves below the question ({before} → {p.call('rowY', b)}, {p.call('room')})")
        p.call("closeWhen")
        check(p.wait(lambda: abs(float(p.call("rowY", b)) - before) < 1), "…and back when it is answered or left")
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "> [!private]\n> just words\n")
        p.open_fresh()
        p.call("cursor", p.call("text").index("just words") + 3)
        p.call("askNow")
        check(p.wait(lambda: p.call("status").startswith("private: the agent sees nothing")), f"a passing word is in the status line ({p.call('status')!r})")

        # A run of list items is one submission, but the mark is on the line
        # the student asked from — the whole list lighting up read as the
        # page leaving rather than the line (2026-10-15).
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) +
            "- [ ] drill the verbs\n- [ ] read chapter 7\n- [ ] hand in the sheet\n")
        p.open_fresh()
        p.call("cursor", p.offset_of_line(p.line_of("read chapter 7")) + 8)
        p.wait(lambda: p.call("sign") != "")
        p.call("askNow")
        check(p.wait(lambda: "sending" in p.call("marks"), 4), "a checkbox in a list marks too")
        check(json.loads(p.call("marks")).count("sending") == 1,
              f"…only the line it was asked from ({p.call('marks')})")

        # 12. the theme: roles come from the Omarchy palette, and the four
        # heading levels are four kinds of thing (2026-10-16) — the theme's
        # chroma, that colour halfway home, the prose, the quiet grey. Each
        # rung has to be plainly not the one under it, which is a perceptual
        # distance and not a contrast ratio: the first ramp was legible at
        # every step and still read as one colour.
        pal = p.call("palette")
        heads = pal.split(" h=")[1].split(" ")[0].split(",")
        fg = pal.split(" fg=")[1].split(" ")[0]
        bg = pal.split(" bg=")[1].split(" ")[0]
        dim = pal.split(" dim=")[1].split(" ")[0]
        check("keys=0" not in pal and len(set(heads)) == 4, f"the page draws in the theme's palette ({pal[:60]}…)")
        check(pal.split(" eh=")[1].split(" ")[0] == ",".join(heads), "…and the editor draws headings with them")
        check(heads[2] == fg and heads[3] == dim,
              f"the deep levels are the prose and the grey below it ({heads[2]}, {heads[3]})")
        rgb = [int(heads[0].lstrip("#")[-6:][i:i + 2], 16) for i in (0, 2, 4)]
        check(max(rgb) - min(rgb) >= 38, f"H1 carries the theme's colour, not a grey ({heads[0]})")
        check(contrast(heads[0], bg) >= 4.4, f"…and reads at 4.5:1 ({contrast(heads[0], bg):.1f}:1)")
        gaps = [delta_e(heads[i], heads[i + 1]) for i in range(3)]
        check(min(gaps) >= 15, f"no level is mistakable for the next ({[round(g) for g in gaps]} ΔE)")

        # 12b. the measure: 72 characters at any zoom, centred; a window too
        # narrow for them wraps instead (the window is 701 wide)
        p.open_fresh()
        for z in (0.75, 1):
            p.call("zoom", z)
            time.sleep(0.4)
            lay = json.loads(p.call("layout"))
            check(71.5 <= lay["chars"] <= 72.5 and lay["x"] > 0, f"at zoom {z} a line holds 72 characters, centred ({lay})")
        # (1.5: at 1.25 the measure counted on real prose, 2026-11-19, still
        # fits the 701 px window)
        p.call("zoom", 1.5)
        time.sleep(0.4)
        lay = json.loads(p.call("layout"))
        check(40 < lay["chars"] < 72 and lay["x"] == 0, f"zoomed past the window, the column fills it and wraps ({lay})")
        p.call("zoom", 1)

        # 12. the dashboard (2026-10-15): every open box in one place, each
        # row saying where it came from, and the three verbs an old box never
        # had. Ticking here ticks the line in the day it was written.
        KEY_RETURN, KEY_DELETE, KEY_Z, KEY_ESC = 0x01000004, 0x01000007, 0x5a, 0x01000000
        (p.daily / f"{YDAY}.md").write_text(header(YDAY)
            + "# Design Theory #dtm\n\n## Essay 2\n\n- [ ] draft the intro\n- [ ] ask about the rubric\n")
        (p.daily / f"{TODAY}.md").write_text(header(TODAY)
            + "# Interdisciplinary Seminar #intsem\n\n- [ ] slides ⏳ 2030-01-02\n"
              "- [ ] read the paper ⏫\n- [ ] loose thought\n")
        p.open_fresh()
        # A line written and the dashboard opened at once: the list waits
        # for the note to be saved (it was read before, and the line was
        # missing until something else asked again, 2026-10-25).
        p.call("cursorEnd")
        p.call("insert", "\n- [ ] just written ⏫")
        p.call("dash")
        check(p.call("dashOpen") == "true", "Ctrl+T opens the dashboard")
        check(p.wait(lambda: any(r.get("text") == "just written" for r in json.loads(p.call("dashRows")))),
              f"a line written a moment before is on it (on disk: {'just written' in p.note()}; "
              f"the list's reads: {p.call('tasksTrace')})")
        p.call("dash")
        p.call("removeLine", p.line_of("just written"))
        p.wait(lambda: "just written" not in p.note())
        p.call("dash")

        def heads():
            return [r["text"] for r in json.loads(p.call("dashRows")) if r["kind"] == "head"]

        def row(title, until=None):
            # The list is rebuilt whenever a line changes, so a row's index
            # is only good once it has stopped moving — and, after an edit,
            # once the row says what the edit made (`until`): the list is
            # read again by `longhand-agent tasks`, which on Windows takes
            # most of a second to start, and a key pressed on the row as it
            # was undoes what the last one did.
            def at():
                rows = json.loads(p.call("dashRows"))
                return next((n for n, r in enumerate(rows) if r.get("text") == title), -1), rows
            i, rows = at()
            for _ in range(20):
                time.sleep(0.3)
                j, rows = at()
                if i == j and j >= 0 and (until is None or until(rows[j])):
                    break
                i = j
            p.call("dashFocus", i)
            return rows[i] if i >= 0 else {}

        check(p.wait(lambda: heads()[-4:] == ["DOING", "TO SCHEDULE",
                                              "Interdisciplinary Seminar", "Design Theory & Methods"]),
              f"grouped by what it asks of you, then by project ({heads()})")
        rows = json.loads(p.call("dashRows"))
        band = next(r for r in rows if r["kind"] == "head" and r["text"] == "Interdisciplinary Seminar")
        check(band["tag"] == "#intsem", f"a band carries the course's own name, its tag beside it ({band})")
        check(any(r["kind"] == "month" for r in rows),
              f"the dated rows are banded by month ({[r['text'] for r in rows if r['kind'] == 'month']})")
        intro = row("draft the intro")
        check("Design Theory & Methods › Essay 2" in intro["where"],
              f"a row says where it came from, the course in full ({intro['where']!r})")
        check("written yesterday" in intro["where"], "…and when it was written")
        check("16 Oct" not in intro["where"] and "do " not in intro["where"],
              "…but not its dates, which are pills as they are in the note")
        check(row("slides")["when"] == "2030-01-02" and row("read the paper")["prio"] == 2,
              "a do-date and a priority are read off the line")

        heard = int(p.call("ticksHeard"))
        row("draft the intro")
        check(p.call("dashKey", 0x20, 0) == "true", "Space is the act that settles a row")
        check(int(p.call("ticksHeard")) == heard + 1, "…and the tick asks for its sound")
        check(p.wait(lambda: p.played.exists() and "tick.wav" in p.played.read_text()),
              "…and the sound is really played (pw-play, given tick.wav)")
        check(p.wait(lambda: "- [x] draft the intro" in (p.daily / f"{YDAY}.md").read_text()),
              "…and it ticks the line in the day it was written")
        done_on = dt.date.today().isoformat()
        check(p.wait(lambda: f"- [x] draft the intro ✅ {done_on}" in (p.daily / f"{YDAY}.md").read_text()),
              "…with the day it was done, as Obsidian Tasks writes it")
        check(p.wait(lambda: any(r.get("text") == "draft the intro" and r.get("done") for r in json.loads(p.call("dashRows")))),
              "…and it stays in the dashboard, done, rather than vanishing")
        row("draft the intro")
        p.call("dashKey", 0x4c, CTRL)
        check(p.wait(lambda: "- [ ] draft the intro\n" in (p.daily / f"{YDAY}.md").read_text()),
              "Ctrl+L on a box done today opens it again, the day taken off")
        check(int(p.call("ticksHeard")) == heard + 1, "…with no sound: an untick is not a tick")
        p.call("tickSoundToggle")
        row("draft the intro", lambda r: not r["done"])
        p.call("dashKey", 0x4c, CTRL)
        check(p.wait(lambda: "- [x] draft the intro" in (p.daily / f"{YDAY}.md").read_text())
              and int(p.call("ticksHeard")) == heard + 1, "with the sound turned off in Settings, a tick is silent")
        p.call("tickSoundToggle")
        row("draft the intro", lambda r: r["done"])
        p.call("dashKey", 0x4c, CTRL)
        p.wait(lambda: "- [ ] draft the intro\n" in (p.daily / f"{YDAY}.md").read_text())

        row("ask about the rubric")
        check(p.call("dashType", "t") == "true", "t asks when")
        check(p.wait(lambda: json.loads(p.call("dashWhenField"))["focus"]),
              f"…and the field to say it in takes the keys ({p.call('dashWhenField')})")
        p.call("dashWhen", "tomorrow")
        tomorrow = (dt.date.today() + dt.timedelta(days=1)).isoformat()
        check(p.wait(lambda: f"⏳ {tomorrow}" in (p.daily / f"{YDAY}.md").read_text()),
              f"…read by the note's own parser, written as a day with no hour ({(p.daily / f'{YDAY}.md').read_text()!r}, {p.call('editQueue')})")
        check(p.wait(lambda: any(r.get("text") == "ask about the rubric" and r["when"] == tomorrow
                                 for r in json.loads(p.call("dashRows")))),
              f"…and the row moves to DOING ({[r for r in json.loads(p.call('dashRows')) if r.get('text') == 'ask about the rubric']})")

        row("loose thought")
        check(p.call("dashType", "p") == "true", "p is taken")
        check(p.wait(lambda: "- [ ] loose thought ⏫" in p.call("text")),
              f"p gives it a priority, written as Obsidian reads it ({p.call('text')[-40:]!r})")
        row("loose thought", lambda r: r["prio"] == 2)
        p.call("dashType", "p")
        check(p.wait(lambda: "- [ ] loose thought 🔽" in p.call("text")), "…and walks the three levels")
        row("loose thought", lambda r: r["prio"] == -1)
        p.call("dashType", "p")
        check(p.wait(lambda: "- [ ] loose thought\n" in p.call("text")), "…back round to none")

        row("loose thought", lambda r: r["prio"] == 0)
        check(p.call("dashKey", KEY_DELETE, 0) == "true", "Delete drops it")
        gone = f"- [-] loose thought ❌ {dt.date.today().isoformat()}"
        check(p.wait(lambda: gone in p.call("text")), f"…cancelled, with the day it was dropped ({p.call('text')[-45:]!r})")
        check(p.wait(lambda: not any(r.get("text") == "loose thought" for r in json.loads(p.call("dashRows")))),
              "…and it leaves the dashboard, because dropping is an answer")
        check(p.call("dashKey", KEY_Z, CTRL) == "true", "Ctrl+Z takes a drop back")
        check(p.wait(lambda: "- [ ] loose thought\n" in p.call("text")), "…with no mark left on the line")

        # 12f. the course strip (2026-11-03): ↑ from the first row climbs
        # onto it; moving along it shows each course at once; Space adds
        # one; Enter unfolds it; ⌕ takes what is typed; O orders the list.
        KEY_LEFT, KEY_UP, KEY_RIGHT, KEY_DOWN = 0x01000012, 0x01000013, 0x01000014, 0x01000015

        def strip():
            return json.loads(p.call("strip"))

        def courses_shown():
            return [r["tag"] for r in json.loads(p.call("dashRows")) if r["kind"] == "head" and r.get("tag")]

        st = strip()
        check("intsem" in st["chips"] and st["at"] == -1 and st["shown"] == st["total"],
              f"the strip has a chip for each course with something open, the list not narrowed ({st})")
        p.call("dashFocus", 0)
        p.call("dashKey", KEY_DOWN, 0)
        p.call("dashKey", KEY_UP, 0)
        p.call("dashKey", KEY_UP, 0)
        check(strip()["at"] == 1, f"↑ from the first row climbs onto the strip, on All ({strip()})")
        p.call("dashKey", KEY_RIGHT, 0)
        first = strip()["chips"][0]
        check(p.wait(lambda: strip()["lens"] == [first] and set(courses_shown()) <= {"#" + first}),
              f"→ shows the first course at once, and only it ({strip()}, {courses_shown()})")
        check(strip()["shown"] < strip()["total"], "…the line under the strip says how much of the list it shows")
        p.call("dashKey", KEY_RIGHT, 0)
        second = strip()["chips"][1]
        check(strip()["lens"] == [second], f"→ again shows the next one instead ({strip()})")
        p.call("dashKey", 0x20, 0)
        p.call("dashKey", KEY_LEFT, 0)
        check(strip()["lens"] == [second], f"Space keeps it: moving on no longer changes what is shown ({strip()})")
        p.call("dashKey", 0x20, 0)
        check(strip()["lens"] == [second, first], f"…and Space on another adds it ({strip()})")
        p.call("dashKey", 0x20, 0)
        check(strip()["lens"] == [second], f"…or takes it out again ({strip()})")
        p.call("dashKey", KEY_LEFT, 0)
        p.call("dashKey", 0x20, 0)
        p.call("dashKey", KEY_RIGHT, 0)
        p.call("dashKey", KEY_RETURN, 0)
        check(strip()["open"] and strip()["pick"] == 1, f"Enter unfolds it, on the course the cursor was on ({strip()})")
        p.call("dashKey", KEY_DOWN, 0)
        p.call("dashKey", KEY_RETURN, 0)
        check(not strip()["open"] and strip()["lens"] == [second], f"…and Enter there shows only that one ({strip()})")
        check(p.call("dashKey", KEY_ESC, 0) == "true" and strip()["lens"] == [] and strip()["at"] == 1,
              f"Esc on the strip clears the courses first ({strip()})")
        p.call("dashKey", KEY_ESC, 0)
        check(strip()["at"] == -1 and p.call("dashOpen") == "true", "…then gives the keys back to the list, the dashboard still open")
        check(p.call("dashType", "/") == "true" and strip()["at"] == 0, "/ goes to the strip's ⌕")
        # ⌕ is a line of text of its own (2026-11-13): it has the keys, its
        # words narrow the list a frame later, → past the last letter goes
        # on to All and ← comes back into it, Esc clears it.
        sf = lambda: json.loads(p.call("dashSearchField"))
        check(p.wait(lambda: sf()["focus"], 2), f"…and gives the keys to its line of text ({sf()})")
        p.call("dashSearchInsert", "rub")
        check(p.wait(lambda: strip()["query"] == "rub" and not sf()["pending"], 2), f"what is typed there narrows the list ({sf()})")
        p.call("dashSearchCursor", 1)
        check(p.call("dashSearchKey", KEY_RIGHT, 0) == "false" and strip()["at"] == 0, "→ inside the words moves the caret, not the strip")
        p.call("dashSearchCursor", 3)
        check(p.call("dashSearchKey", KEY_RIGHT, 0) == "true" and strip()["at"] == 1 and p.wait(lambda: not sf()["focus"], 2),
              f"→ past the last letter goes on to All ({strip()}, {sf()})")
        p.call("dashKey", KEY_LEFT, 0)
        check(p.wait(lambda: sf()["focus"] and sf()["text"] == "rub", 2), f"← comes back into the words ({sf()})")
        p.call("dashSearchKey", KEY_ESC, 0)
        check(strip()["query"] == "" and sf()["text"] == "" and strip()["at"] == 0, f"Esc there clears them ({sf()})")
        drawn = lambda: json.loads(p.call("dashDrawn"))

        def settled():
            # A read of the list asked for by the edits above may still land
            # and draw rows anew (each read starts a Python: later on
            # Windows). Taken once two looks a moment apart agree.
            last = drawn()
            for _ in range(20):
                time.sleep(0.5)
                now = drawn()
                if now["shown"] == last["shown"] and now["fresh"] == 0:
                    break
                last = now
            return now
        everything = settled()["shown"]
        for ch in "rubric":
            p.call("dashType", ch)
        check(p.wait(lambda: [r.get("text") for r in json.loads(p.call("dashRows")) if r["kind"] == "task"] == ["ask about the rubric"]),
              f"typed there, words narrow the list ({strip()}, {[r.get('text') for r in json.loads(p.call('dashRows'))]})")
        # Typing never draws the list anew (2026-11-13): what the words
        # leave out is hidden, and comes back as it was.
        now = drawn()
        check(any(x.startswith("ask about the rubric") for x in now["shown"]) and len(now["shown"]) < len(everything) and now["fresh"] == 0,
              f"…the rows it keeps are the ones drawn before, none made anew ({now})")
        p.call("dashKey", 0x01000003, CTRL)                # Ctrl+Backspace
        check(strip()["query"] == "", f"Ctrl+Backspace takes the word typed, not a letter ({strip()})")
        now = drawn()
        check(now["shown"] == everything and now["fresh"] == 0, f"…and the whole list is back, the same rows ({now})")
        for ch in "rubric":
            p.call("dashType", ch)
        p.call("dashKey", KEY_ESC, 0)
        check(strip()["query"] == "" and strip()["at"] == 0, "Esc clears what was typed")
        p.call("dashKey", KEY_ESC, 0)
        p.call("dashType", "o")
        check(strip()["order"] == "course" and json.loads(p.call("dashRows"))[0]["kind"] == "head"
              and json.loads(p.call("dashRows"))[0].get("tag"), f"O orders the list by course ({strip()})")
        p.call("dashType", "o")
        check(strip()["order"] == "date", "…then by date")
        # By date the bands fold: → on a folded one opens it, ← on a row
        # climbs to its band and ← again folds it; Shift and an arrow, all.
        def bands():
            return [r for r in json.loads(p.call("dashRows")) if r["kind"] == "band"]
        check(p.wait(lambda: any(b["id"] == "today" for b in bands())), f"by date, the bands, today among them ({bands()})")
        p.call("dashKey", KEY_RIGHT, SHIFT)
        check(p.wait(lambda: all(b["open"] for b in bands())), f"Shift+→ expands every band ({bands()})")
        p.call("dashKey", KEY_LEFT, SHIFT)
        check(p.wait(lambda: all(not b["open"] for b in bands() if b["count"] > 0 and b["id"] != "late")),
              f"Shift+← collapses them, all but what is late ({bands()})")
        rows = json.loads(p.call("dashRows"))
        at = int(p.call("dashAt"))
        check(rows[at]["kind"] == "band" and not rows[at]["open"], f"…the cursor on a folded band ({rows[at]})")
        p.call("dashKey", KEY_RIGHT, 0)
        check(p.wait(lambda: json.loads(p.call("dashRows"))[at]["open"]), "→ opens it")
        p.call("dashKey", KEY_RIGHT, 0)
        check(int(p.call("dashAt")) == at + 1, "→ again steps into it")
        p.call("dashKey", KEY_LEFT, 0)
        check(int(p.call("dashAt")) == at, "← climbs back to its band")
        p.call("dashKey", KEY_LEFT, 0)
        check(p.wait(lambda: not json.loads(p.call("dashRows"))[at]["open"]), "…and ← there folds it")
        check(json.loads((p.state / "longhand" / "page.json").read_text()).get("dashFolds", {}).get("*") is False,
              "the folds are kept in page.json")
        p.call("dashKey", KEY_RIGHT, SHIFT)
        p.call("dashType", "o")
        check(strip()["order"] == "ask" and p.wait(lambda: heads()[-4:] == ["DOING", "TO SCHEDULE",
                                                                             "Interdisciplinary Seminar", "Design Theory & Methods"]),
              f"…and back to what it asks ({heads()})")
        p.call("dashType", "1")
        check(strip()["lens"] == [first], f"1 shows the strip's first course from the list ({strip()})")
        p.call("dashType", "0")
        check(strip()["lens"] == [], "0 shows every course again")

        row("read the paper")
        p.call("dashKey", KEY_RETURN, 0)
        check(p.wait(lambda: p.call("dashOpen") == "false"), "Enter leaves the dashboard for the line")
        check(int(p.call("cursorLine")) == p.line_of("read the paper"),
              f"…with the cursor on it (cursor {p.call('cursorLine')}, line {p.line_of('read the paper')}, text {p.call('text')!r})")

        # 12a. one copy of a task (docs/tasks.md, 2026-10-17): Enter reaches
        # a line on any day; Ctrl+E renames; a deadline is cancelled through
        # its line; one that no note holds waits as the agent's, and Enter
        # writes it in.
        KEY_E = 0x45
        p.call("dash")
        row("ask about the rubric")
        p.call("dashKey", KEY_RETURN, 0)
        check(p.wait(lambda: p.call("dashOpen") == "false" and "ask about the rubric" in p.call("text")),
              "Enter on a task written on another day opens that day's note")
        check(p.wait(lambda: int(p.call("cursorLine")) == p.line_of("ask about the rubric")),
              f"…with the cursor on its line ({p.call('cursorLine')})")
        p.call("openDay", TODAY)
        p.wait(lambda: p.call("header").startswith(dt.date.today().strftime("%A")))

        p.call("dash")
        row("read the paper")
        check(p.call("dashKey", KEY_E, CTRL) == "true", "Ctrl+E renames")
        p.call("dashWhen", "read the whole paper")
        check(p.wait(lambda: "- [ ] read the whole paper ⏫" in p.call("text")),
              f"…the line's words, its facts kept ({p.call('text')[-60:]!r})")
        # The rest of the map (2026-10-28): F2 renames too, Shift+T takes
        # the day to work on it off, `?` shows the keys.
        KEY_F2, KEY_T, KEY_QUESTION = 0x01000031, 0x54, 0x3f
        row("read the whole paper")
        check(p.call("dashKey", KEY_F2, 0) == "true", "F2 renames as well")
        p.call("dashWhen", "read the paper")
        check(p.wait(lambda: "- [ ] read the paper ⏫" in p.call("text")), f"…the same way ({p.call('text')[-60:]!r})")
        row("read the paper")
        p.call("dashKey", KEY_T, 0)
        p.call("dashWhen", "2030-01-05")
        check(p.wait(lambda: "read the paper ⏫ ⏳ 2030-01-05" in p.call("text")), f"t gives it a day ({p.call('text')[-60:]!r})")
        row("read the paper", lambda r: r["when"] == "2030-01-05")
        check(p.call("dashKey", KEY_T, SHIFT) == "true", "Shift+T is taken")
        check(p.wait(lambda: "- [ ] read the paper ⏫\n" in p.call("text")),
              f"…and takes the day off again, the rest of the line kept ({p.call('text')[-60:]!r})")
        check(p.call("dashKey", KEY_QUESTION, SHIFT) == "true" and p.call("keysOpen") == "true", "? in the dashboard shows the keys")
        p.call("keys")
        if p.call("dashOpen") != "true":
            p.call("dash")

        # A deadline's row shows what its line holds, as a task's does
        # (2026-10-25): the day to work on it, the priority, the estimate;
        # and t and p write them on its line.
        out = p.pomo("add", "the lab notes", "2030-01-08")
        pid = int(re.search(r"#(\d+)", out).group(1))
        p.call("cursorEnd")
        p.call("insert", f"\n- [ ] the lab notes [est:: 2h] 🔽 ⏳ 2030-01-03 📅 2030-01-08 ^d{pid}")
        p.call("cursor", 1)
        p.wait(lambda: p.deadline(pid)["link"] != "")
        # Opened afresh, the list is read again with the new line in it.
        if p.call("dashOpen") == "true":
            p.call("dash")
        p.call("dash")
        def labnotes():
            return next((r for r in json.loads(p.call("dashRows")) if r.get("text") == "the lab notes"), {})
        check(p.wait(lambda: labnotes().get("kind") == "deadline" and labnotes()["mark"] == "▽"
                     and labnotes()["pills"][0].startswith("do ") and labnotes()["pills"][-1] == "2h"),
              f"a deadline's row draws its do-date, priority and estimate ({labnotes()})")
        row("the lab notes")
        check(p.call("dashType", "p") == "true", "p on a deadline row is taken")
        check(p.wait(lambda: f"- [ ] the lab notes [est:: 2h] ⏳ 2030-01-03 📅 2030-01-08 ^d{pid}" in p.call("text")),
              f"…and walks its line's priority ({p.call('text')[-80:]!r})")
        row("the lab notes", lambda r: r["mark"] != "▽")
        check(p.call("dashType", "t") == "true", "t on a deadline row asks when")
        p.call("dashWhen", "2030-01-04")
        check(p.wait(lambda: f"⏳ 2030-01-04 📅 2030-01-08 ^d{pid}" in p.call("text")),
              f"…the day to work on it, its due date kept ({p.call('text')[-80:]!r})")
        p.call("removeLine", p.line_of(f"^d{pid}"))
        p.wait(lambda: p.deadline(pid)["status"] == "cancelled")

        out = p.pomo("add", "essay outline", "2030-01-05")
        eid = int(re.search(r"#(\d+)", out).group(1))
        p.call("cursorEnd")
        p.call("insert", f"\n- [ ] essay outline 📅 2030-01-05 ^d{eid}")
        p.call("cursor", 1)
        check(p.wait(lambda: p.deadline(eid)["link"] != ""), "a line written with a tag is the deadline's line")
        p.call("dash")
        row("essay outline")
        check(p.call("dashKey", KEY_DELETE, 0) == "true", "Delete on a deadline row is taken")
        check(p.wait(lambda: "- [-] essay outline 📅 2030-01-05 ❌" in p.call("text")),
              f"…its line is cancelled, words kept ({p.call('text')[-70:]!r})")
        check(p.wait(lambda: p.deadline(eid)["status"] == "cancelled"), "…and so is the deadline")
        p.call("dashKey", KEY_Z, CTRL)
        check(p.wait(lambda: p.deadline(eid)["status"] == "open" and f"- [ ] essay outline 📅 2030-01-05 ^d{eid}" in p.call("text")),
              f"Ctrl+Z brings both back ({p.deadline(eid)}, {p.call('text')[-80:]!r}, {p.call('checkState')})")

        # Ctrl+L ticks a deadline in the sidebar's list for its day, as in
        # the note and the dashboard: the store and its line together.
        KEY_L = 0x4c
        p.call("dash")
        p.call("sidebar")
        p.call("calDay", 2030, 1, 5)
        check(p.call("dueKey", 0, KEY_L, CTRL) == "true", "Ctrl+L in the sidebar's deadline list is taken")
        check(p.wait(lambda: p.deadline(eid)["status"] == "done"
                     and f"- [x] essay outline 📅 2030-01-05 ✅ {dt.date.today().isoformat()} ^d{eid}" in p.call("text")),
              f"…the deadline is done and its line ticked ({p.deadline(eid)}, {p.call('text')[-80:]!r})")
        p.call("dueKey", 0, KEY_L, CTRL)
        check(p.wait(lambda: p.deadline(eid)["status"] == "open" and f"- [ ] essay outline 📅 2030-01-05 ^d{eid}" in p.call("text")),
              f"…and again, open ({p.deadline(eid)}, {p.call('text')[-80:]!r})")
        # …and it stays so once the check has read the note (2026-11-15: a
        # check that read the note while the save was still on its way saw
        # the line cancelled, and cancelled its deadline again).
        def settled_open():
            st = json.loads(p.call("checkState"))
            return (not st["wanted"] and not st["checking"] and p.deadline(eid)["status"] == "open"
                    and f"- [ ] essay outline 📅 2030-01-05 ^d{eid}" in p.note())
        time.sleep(1.0)
        check(p.wait(settled_open) and (time.sleep(1.0) or settled_open()),
              f"…and stays open once the check has read the note ({p.deadline(eid)}, {p.call('checkState')}, {p.note()[-70:]!r})")
        p.call("sidebar")
        p.call("dash")

        out = p.pomo("add", "Registered topic and supervisor", "2030-01-06")
        wid = int(re.search(r"#(\d+)", out).group(1))
        check(p.wait(lambda: "NOT IN A NOTE YET" in heads()), f"a deadline no note holds waits in its own band ({heads()})")
        row("Registered topic and supervisor")
        p.call("dashKey", KEY_RETURN, 0)
        check(p.wait(lambda: f"Registered topic and supervisor 📅 2030-01-06 ^d{wid}" in p.call("text")),
              "Enter writes it into today's note")
        check(p.wait(lambda: p.deadline(wid)["link"] != ""), "…and the store knows its line")
        # …and is the agent's, though no check ran while it waited (it is
        # written in at once): the page tells the check where it came from.
        led = p.state / "longhand" / "ledger.json"
        check(p.wait(lambda: (json.loads(led.read_text())["deadlines"].get(str(wid)) or {}).get("origin") == "agent"),
              f"…and the ledger keeps it as the agent's ({json.loads(led.read_text())['deadlines'].get(str(wid))})")

        # 12c. lifespans (2026-10-17): a box counts down through the last
        # quarter of its life and then waits under "not now"; `s` puts one
        # there by hand, `s` or `r` brings it back, and the note is never
        # touched. A deadline counts down to stepping aside, and `g` grades.
        KEY_S, KEY_R, KEY_G = 0x53, 0x52, 0x47
        old = (dt.date.today() - dt.timedelta(days=20)).strftime("%Y.%m.%d")
        oldnote = p.daily / f"{old}.md"
        oldnote.write_text(header(old) + "# Design Theory #dtm\n\n- [ ] a fading thought\n- [ ] an old aside\n")
        silence = p.state / "longhand" / "silence.json"
        clock = lifespan.load(silence) or {"checked": dt.date.today().isoformat(), "boxes": {}}
        for words, days in (("a fading thought", 6), ("an old aside", 9)):
            clock["boxes"][lifespan.key_of({"project": "dtm", "text": words})] = {
                "touched": (dt.date.today() - dt.timedelta(days=days)).isoformat()}
        lifespan.save(silence, clock)
        before = oldnote.read_text()
        if p.call("dashOpen") == "false":
            p.call("dash")
        check(p.wait(lambda: "goes quiet tomorrow" in row("a fading thought").get("where", "")),
              f"a box in its last day says so on its row ({row('a fading thought')})")
        check(p.wait(lambda: any(r["kind"] == "shelf" for r in json.loads(p.call("dashRows")))
                     and row("an old aside") == {}),
              "a box whose silence ran out leaves the list, folded under one row")
        shelf = next(n for n, r in enumerate(json.loads(p.call("dashRows"))) if r["kind"] == "shelf")
        p.call("dashFocus", shelf)
        p.call("dashKey", KEY_RETURN, 0)
        check(p.wait(lambda: "SET ASIDE" in heads() and "gone quiet" in row("an old aside").get("where", "")),
              f"Enter unfolds it: there to be found ({heads()})")
        row("an old aside")
        check(p.call("dashKey", KEY_S, 0) == "true", "s is taken")
        check(p.wait(lambda: row("an old aside").get("away") == ""), "s on a box that is away brings it back")
        row("a fading thought")
        p.call("dashKey", KEY_S, 0)
        check(p.wait(lambda: row("a fading thought").get("away") == "shelved"), "s puts a live box aside")
        row("a fading thought")
        check(p.call("dashKey", KEY_R, 0) == "true", "r is taken")
        check(p.wait(lambda: row("a fading thought").get("away") == ""
                     and "goes quiet" not in row("a fading thought").get("where", "")),
              "r keeps it: back, its clock started again")
        # Two boxes put aside in a row, faster than the first is written:
        # both are (the second was lost, 2026-10-25).
        rows_now = json.loads(p.call("dashRows"))
        i1, i2 = (next(n for n, r in enumerate(rows_now) if r.get("text") == w) for w in ("a fading thought", "an old aside"))
        p.call("dashFocus", i1)
        p.call("dashKey", KEY_S, 0)
        p.call("dashFocus", i2)
        p.call("dashKey", KEY_S, 0)
        check(p.wait(lambda: row("a fading thought").get("away") == "shelved" and row("an old aside").get("away") == "shelved"),
              f"s on two boxes in a row puts both aside ({row('a fading thought').get('away')!r}, {row('an old aside').get('away')!r})")
        for w in ("a fading thought", "an old aside"):
            row(w)
            p.call("dashKey", KEY_R, 0)
            p.wait(lambda: row(w).get("away") == "")
        check(oldnote.read_text() == before, "the decay is in the view: the note is never touched")

        late = int(re.search(r"#(\d+)", p.pomo("add", "Late essay",
                                               (dt.date.today() - dt.timedelta(days=12)).isoformat())).group(1))
        check(p.wait(lambda: re.search(r"steps aside in \d days", row("Late essay").get("where", ""))),
              f"a deadline in its last days before stepping aside counts them down ({row('Late essay')})")
        lab = int(re.search(r"#(\d+)", p.pomo("add", "Lab report", "2030-01-07")).group(1))
        p.pomo("done", str(lab), "--at", str(int(time.time()) - 2 * 86400))
        check(p.wait(lambda: any(r["kind"] == "grading" for r in json.loads(p.call("dashRows")))),
              "a done deadline with no grade waits, folded")
        grading = next(n for n, r in enumerate(json.loads(p.call("dashRows"))) if r["kind"] == "grading")
        p.call("dashFocus", grading)
        p.call("dashKey", KEY_RETURN, 0)
        check(p.wait(lambda: "WAITING FOR A GRADE" in heads()), "…and unfolds")
        row("Lab report")
        check(p.call("dashKey", KEY_G, 0) == "true", "g is taken")
        p.call("dashWhen", "7.5")
        check(p.wait(lambda: p.deadline(lab)["grade"] == "7.5"), f"g grades it ({p.deadline(lab)})")
        p.pomo("hide", str(late))
        p.call("dash")

        # 12c'. the day conversation (2026-10-21): the seal, at the header's
        # centre, opens and closes it; the date opens the sidebar; Ctrl+J
        # from anywhere; Ctrl+Shift+Enter points at the block; a block's
        # room returns to the day.
        if p.call("dashOpen") == "true":
            p.call("dash")
        p.call("openDay", TODAY)
        p.wait(lambda: p.call("header").startswith(dt.date.today().strftime("%A")))
        was = p.call("sidebarOpen")
        p.call("seal")
        check(p.wait(lambda: p.call("dayShown") == "true") and p.call("sidebarOpen") == was,
              "the seal opens the day's conversation, and nothing else")
        p.call("seal")
        check(p.wait(lambda: p.call("dayShown") == "false"), "…and closes it")
        p.call("dateClick")
        check(p.wait(lambda: p.call("sidebarOpen") != was), "the date opens or closes the sidebar")
        p.call("dateClick")
        check(p.wait(lambda: p.call("sidebarOpen") == was), "…and again, back as it was")
        KEY_J, KEY_ENTER = 0x4a, 0x01000004
        check(p.call("pageKey", 0x7c, CTRL) == "true" and p.wait(lambda: p.call("dayShown") == "true"),
              "Ctrl+| opens the day's chat from the note")
        p.call("daySend", "what comes first today?")
        check(p.wait(lambda: json.loads(p.call("dayTurns"))[-2:] == ["student: what comes first today?",
                                                                    "agent: day: what comes first today?"], timeout=12),
              f"a message to the day is answered, and kept in the day's state ({p.call('dayTurns')})")
        # The answer is drawn once it is written, a moment before the run's
        # process ends (longer on Windows); Esc while it runs stops it.
        p.wait(lambda: p.call("agentBusy", "day") == "false", 5)
        p.call("dayKey", 0x01000000, 0)
        check(p.wait(lambda: p.call("dayShown") == "false"), "Esc closes it")
        note_before = p.note()
        p.call("cursorEnd")
        p.call("type", "\n\nShould I ask the dean about the shortlist")
        p.wait(lambda: "ask the dean" in p.note())
        p.call("cursor", p.offset_of_line(p.line_of("ask the dean")) + 6)
        check(p.call("pageKey", KEY_ENTER, CTRL | SHIFT) == "true" and p.wait(lambda: p.call("dayShown") == "true")
              and p.call("dayBlockText") == "",
              f"Ctrl+Shift+Enter in a block opens the day's chat, pointing at nothing ({p.call('dayBlockText')!r})")
        p.call("dayType", "@dean")
        check(p.wait(lambda: json.loads(p.call("dayMention"))) and p.call("dayKey", KEY_ENTER, 0) == "true"
              and "ask the dean" in p.call("dayBlockText"), f"…@ points at the block ({p.call('dayBlockText')!r})")
        p.call("daySend", "and this one?")
        check(p.wait(lambda: json.loads(p.call("dayTurns"))[-1] == "agent: day: and this one?", timeout=12)
              and p.call("dayBlockText") == "", "…the block goes with the message, and the box lets go of it")
        st = json.loads((p.vault / "agents" / "longhand" / "daily" / f"{TODAY}.json").read_text())
        check(st["day"]["turns"][-2].get("block", "") != "", "…and the message keeps which block it pointed at")
        # One conversation, slice 2 (2026-11-18): what a message is about is a
        # row of chips above the box, seen before it is sent and removable.
        # The cursor's block, when it is a task, attaches itself (dimmer)
        # and follows the selection until typing starts; `@` adds a block
        # or an open task of another day; Backspace in the empty box lets
        # go of the last; the turn keeps them.
        chips = lambda: json.loads(p.call("dayChips"))
        check([(c["kind"], c.get("auto")) for c in chips()] == [("block", True)] and "ask the dean" in chips()[0]["head"],
              f"the paragraph under the cursor attaches itself too, as a block (the student's call, 2026-11-18) ({chips()})")
        p.call("dayKey", 0x01000000, 0)
        p.call("cursorEnd")
        p.call("type", "\n\n- [ ] email the dean about the shortlist")
        p.wait(lambda: "email the dean" in p.note())
        p.call("cursor", p.offset_of_line(p.line_of("email the dean")) + 8)
        p.call("pageKey", 0x7c, CTRL)
        check(p.wait(lambda: p.call("dayShown") == "true" and [(c["kind"], c.get("auto")) for c in chips()] == [("task", True)])
              and "email the dean" in chips()[0]["head"],
              f"the task under the cursor attaches itself to the day's chat, as its automatic chip ({chips()})")
        p.call("dayType", "@Should")
        p.wait(lambda: json.loads(p.call("dayMention")))
        heads = json.loads(p.call("dayMention"))
        check(len(heads) == 1 and "ask the dean" in heads[0] and p.call("dayKey", KEY_ENTER, 0) == "true"
              and p.wait(lambda: [c["kind"] for c in chips()] == ["task", "block"]),
              f"@ adds a second thing to point at, beside the automatic one ({chips()})")
        check(p.call("dayKey", 0x01000003, 0) == "true" and [c["kind"] for c in chips()] == ["task"]
              and p.call("dayKey", 0x01000003, 0) == "true" and chips() == [],
              f"Backspace in the empty box lets go of the last chip, then of the automatic one ({chips()})")
        p.call("dayType", "x")
        p.call("dayType", "")
        check(chips() == [], "…and it stays let go while the selection has not moved")
        p.call("dayKey", 0x01000000, 0)
        p.call("cursor", p.offset_of_line(p.line_of("ask the dean")) + 6)
        p.call("cursor", p.offset_of_line(p.line_of("email the dean")) + 8)
        p.call("pageKey", 0x7c, CTRL)
        check(p.wait(lambda: p.call("dayShown") == "true" and len(chips()) == 1), "…the selection moved: it attaches itself again")
        p.call("dayType", "@Should")
        p.wait(lambda: json.loads(p.call("dayMention")))
        p.call("dayKey", KEY_ENTER, 0)
        p.call("dayType", "these two")
        p.call("daySend", "these two")
        check(p.wait(lambda: json.loads(p.call("dayTurns"))[-1] == "agent: day: these two", timeout=12),
              f"a message with two chips is answered ({p.call('dayTurns')})")
        st = json.loads((p.vault / "agents" / "longhand" / "daily" / f"{TODAY}.json").read_text())
        refs = st["day"]["turns"][-2].get("refs") or []
        check([r["kind"] for r in refs] == ["task", "block"] and "email the dean" in refs[0]["head"],
              f"…and its turn keeps what it pointed at ({refs})")
        # Replying to passages of the agent's (2026-11-18, design A): words
        # picked make the box a reply to them, what it held set aside; Enter
        # attaches it (a pill) and gives the box back; a second is attached
        # beside the first, never in its place; a pill clicked is back in
        # the box to change; Esc cancels; Enter with none open sends them
        # all, each under its passage; a quote followed back lights its answer.
        reps = lambda: [(r["quote"], r["text"]) for r in json.loads(p.call("replies", "day"))]
        # Words selected in an answer are offered over the box, the key with
        # them; taking the offer makes the box a reply to them.
        at0 = p.call("lastAgentAt")
        got = p.call("selectInAnswer", "these two")
        check(got == "selected" and p.wait(lambda: (json.loads(p.call("replyOffer")) or {}).get("quote") == "these two"),
              f"words selected in an answer are offered over the box ({got}, {p.call('replyOffer')})")
        p.call("takeOffer")
        check(p.wait(lambda: (json.loads(p.call("replying", "day")) or {}).get("quote") == "these two")
              and json.loads(p.call("replyOffer")) is None and json.loads(p.call("replying", "day"))["at"] == at0,
              f"…taking it makes the box a reply to them, the offer gone ({p.call('replying', 'day')})")
        if json.loads(p.call("replying", "day")):
            p.call("dayKey", 0x01000000, 0)   # Esc: cancelled, for the checks after
        # Ctrl+R with the keys on the PDF or a paper's marks, as they stay
        # when words are dragged over in an answer (2026-11-19): the same.
        for where in ("pdfKey", "paperKey"):
            p.call("selectInAnswer", "these two")
            took = p.call(where, 0x52, CTRL)
            check(took == "true" and p.wait(lambda: (json.loads(p.call("replying", "day")) or {}).get("quote") == "these two"),
                  f"Ctrl+R from {where[:-3]} replies to the words selected in an answer ({took}, {p.call('replying', 'day')})")
            if json.loads(p.call("replying", "day")):
                p.call("dayKey", 0x01000000, 0)
        check(p.call("pdfKey", 0x52, CTRL) == "false", "…and with none selected, Ctrl+R there is not taken")
        rep_open = lambda: json.loads(p.call("replying", "day"))
        at = p.call("lastAgentAt")
        p.call("dayType", "anything else?")
        p.call("answerPassage", "day", "day: these two", at)
        check(rep_open() and rep_open()["quote"] == "day: these two" and p.call("dayFieldText") == "",
              f"reply picks a passage: the box is a reply to it, what it held set aside ({rep_open()})")
        check(json.loads(p.call("marksOf", "day", at)) == [{"quote": "day: these two", "n": 1, "state": "open"}],
              "…the passage lit and numbered in the answer while it is written")
        p.call("dayType", "yes, both")
        check(p.call("dayKey", KEY_RETURN, 0) == "true" and reps() == [("day: these two", "yes, both")] and not rep_open()
              and p.call("dayFieldText") == "anything else?",
              f"Enter attaches the reply, nothing sent, the box's own words back ({reps()}, {p.call('dayFieldText')!r})")
        p.call("answerPassage", "day", "these", at)
        p.call("dayType", "and why these?")
        p.call("answerPassage", "day", "two", at)
        check(reps() == [("day: these two", "yes, both"), ("these", "and why these?")] and rep_open()["quote"] == "two",
              f"a second reply goes beside the first; picking a third attaches the one open ({reps()})")
        check(p.call("dayKey", 0x01000000, 0) == "true" and not rep_open() and p.call("dayFieldText") == "anything else?"
              and p.call("dayShown") == "true", "Esc cancels the reply open, the box's words back, the pane still open")
        p.call("editReply", "day", 0)
        check(rep_open()["quote"] == "day: these two" and p.call("dayFieldText") == "yes, both" and len(reps()) == 1,
              "a pill clicked is back in the box, to change")
        p.call("dayType", "yes, both of them")
        p.call("dayKey", KEY_RETURN, 0)
        p.call("dayKey", KEY_RETURN, 0)       # none open: sends
        sent = "anything else?\n\n> these\nand why these?\n\n> day: these two\nyes, both of them"
        check(p.wait(lambda: json.loads(p.call("dayTurns"))[-2:-1] == ["student: " + sent], timeout=12) and reps() == [],
              f"Enter with no reply open sends the box's words and every reply, each under its passage ({json.loads(p.call('dayTurns'))[-2:]})")
        parts = json.loads(p.call("partsOf", sent))
        check([(x["quote"], x["text"]) for x in parts] == [("", "anything else?"), ("these", "and why these?"), ("day: these two", "yes, both of them")],
              f"…and it reads back as its parts ({parts})")
        check(sorted((m["quote"], m["n"], m["state"]) for m in json.loads(p.call("marksOf", "day", at)))
              == [("day: these two", 2, "sent"), ("these", 1, "sent")],
              f"…the answer keeps both passages numbered as the message numbered them ({p.call('marksOf', 'day', at)})")
        # The answer to it, in its parts (design A2): each under the reply it
        # answers, by number; a part's bubble under the pointer lights its
        # passage in the earlier answer.
        split = lambda: json.loads(p.call("lastAnswerParts"))
        check(p.wait(lambda: split() and [(x["n"], x["reply"]) for x in split()["parts"]] == [(1, "and why these?"), (2, "yes, both of them")], timeout=10)
              and split()["intro"] == "day: anything else?",
              f"the answer to several replies is in its parts, each under the reply it answers ({split()})")
        p.call("hoverOn", "these")
        check(("these", "hover") in [(m["quote"], m["state"]) for m in json.loads(p.call("marksOf", "day", at))],
              f"…a part under the pointer lights its passage in the earlier answer ({p.call('marksOf', 'day', at)})")
        p.call("hoverOn", "")
        p.call("followPassage", "day", "day: these two")
        check(p.wait(lambda: p.call("litPassage").endswith("|day")), f"a reply followed back lights the answer it came from ({p.call('litPassage')!r})")
        # One voice (slice 3): what the agent said on opening the page is a
        # turn in its place among the day's, answered in the box like any.
        st = json.loads((p.vault / "agents" / "longhand" / "daily" / f"{TODAY}.json").read_text())
        turns = st["day"]["turns"]
        st.setdefault("observations", []).append({"text": "Two things are due this week.", "trigger": "open",
                                                  "at": turns[1]["at"] if len(turns) > 1 and turns[1].get("at") else f"{TODAY}T00:00:01"})
        (p.vault / "agents" / "longhand" / "daily" / f"{TODAY}.json").write_text(json.dumps(st))
        # Before the first turn said after it (several may share a second).
        o_at = st["observations"][-1]["at"]
        place = next((k for k, x in enumerate(turns) if str(x.get("at") or "9") > o_at), len(turns))
        want = [["Two things are due this week."] if k == place else [] for k in range(4)]
        check(p.wait(lambda: json.loads(p.call("dayOpenings")) == want, timeout=8),
              f"what was said on opening the page is a turn in its place, after the turns said by then ({p.call('dayOpenings')})")
        # One chat that scrolls up into the days before (2026-11-21): the
        # last few days drawn whole above today, a rule between days; their
        # other places a line each; more on scrolling up; an earlier answer
        # can be replied to and found again.
        sys.path.insert(0, str(ROOT / "agent"))
        import convo as convolib
        back = [(dt.date.today() - dt.timedelta(days=k)).isoformat() for k in (5, 4, 3, 2, 1)]
        task_s, paper_s = "task:thesis\t- ask the dean", "paper:papers/dean.pdf"
        nm = {task_s: "ask the dean", paper_s: "dean2024"}
        seeded = []
        for k, d in enumerate(back):
            seeded += [convolib.turn("day", f"day:{d}", "student", f"question of day {k}", f"{d}T09:00:00",
                                     [f"day:{d}"] + ([task_s] if k == 4 else []), nm),
                       convolib.turn("day", f"day:{d}", "agent", f"answer of day {k}: the second option is the short one.",
                                     f"{d}T09:00:05", [f"day:{d}"], nm)]
        seeded += [convolib.turn("paper", paper_s, "student", "what is the sample?", f"{back[-1]}T10:00:00", [paper_s], nm),
                   convolib.turn("paper", paper_s, "agent", "Twelve interviews.", f"{back[-1]}T10:00:09", [paper_s], nm)]
        convolib.Log(p.vault / "agents" / "longhand" / "conversation", "elsewhere").append(seeded)
        p.call("loadConvo")
        hist = lambda: json.loads(p.call("historyRows"))  # noqa: E731
        check(p.wait(lambda: any(r["kind"] == "turn" and r["text"] == "question of day 4" for r in hist()), timeout=10),
              f"the days before are drawn above today's chat, said whole ({[r.get('text') or r.get('label') for r in hist()][:6]})")
        h = hist()
        days = [r for r in h if r["kind"] == "day"]
        yrow = next(r for r in h if r["kind"] == "turn" and r["text"] == "question of day 4")
        check(len(days) == 3 and days[-1]["date"] == back[-1] and h[0]["kind"] == "day"
              and [r["text"] for r in h if r["kind"] == "turn"][:2] == ["question of day 2", "answer of day 2: the second option is the short one."],
              f"…the last three days, each under its rule, the oldest first ({[d['label'] for d in days]})")
        check(yrow["chips"] == ["task · ask the dean"] and any(r["kind"] == "fold" and r["head"].startswith("paper · dean2024") for r in h)
              and p.call("todayLabel").startswith("Today · "),
              f"…a message keeps what it pointed at; another place is a line; today has its rule ({yrow['chips']}, {p.call('todayLabel')!r})")
        view = lambda: json.loads(p.call("dayView"))  # noqa: E731
        check(view()["title"] == "", f"today's whole chat has no header: its first line is today's rule ({view()['title']!r})")
        check(p.wait(lambda: view()["top"] > 0 and view()["y"] >= view()["top"] - 2
                     and (view()["room"] == 0 or abs(view()["y"] - view()["top"]) <= 2)),
              f"at rest the days before are out of sight: a short day opens at today's rule, a long one at its foot ({view()})")
        check(any(r["key"] == f"g:{back[-1]}:{paper_s}" for r in json.loads(p.call("convoRows"))),
              "…and ↑ from the box goes through yesterday's other places too")
        check(p.call("moreHistory") == "true" and len([r for r in hist() if r["kind"] == "day"]) == 5
              and p.call("moreHistory") == "false",
              "scrolling to the top brings the days before, until there are no more")
        yans = next(r for r in hist() if r["kind"] == "turn" and r["text"].startswith("answer of day 4"))
        p.call("answerPassage", "day", "the second option is the short one", yans["at"])
        check(p.wait(lambda: (json.loads(p.call("replying", "day")) or {}).get("at") == yans["at"]),
              f"an answer of yesterday's can be replied to: the reply goes with today's message ({p.call('replying', 'day')})")
        p.call("dayKey", 0x01000000, 0)
        p.call("followPassage", "day", "the second option is the short one")
        check(p.wait(lambda: p.call("litPassage") == yans["at"] + "|day"),
              f"…and a quote of it is followed back to yesterday's answer ({p.call('litPassage')!r})")

        # "Everything": today's other places, folded to a line each, among
        # the day's turns; ↑ from the empty box goes to them, Enter opens.
        check(p.wait(lambda: len(json.loads(p.call("convoRows"))) > 0, timeout=10),
              f"the pane reads the one conversation's view: today's other chats, a line each ({p.call('convoRows')})")
        p.call("dayType", "")
        rows = json.loads(p.call("convoRows"))
        check(p.call("dayKey", 0x01000013, 0) == "true" and p.call("dayFoldKey") == rows[-1]["key"],
              f"↑ from the empty box goes to the last folded line ({p.call('dayFoldKey')!r})")
        check(p.call("dayKey", 0x01000000, 0) == "true" and p.call("dayFoldKey") == "" and p.call("dayShown") == "true",
              "…Esc goes back to the box, the pane still open")
        p.call("cursor", p.offset_of_line(p.line_of("ask the dean")) + 6)
        p.call("dive")
        check(p.wait(lambda: p.call("dayShown") == "false") and json.loads(p.call("panel"))["margin"],
              "a block's own conversation is a room stepped into from the day")
        p.call("back")
        check(p.wait(lambda: p.call("dayShown") == "true"), "…and leaving it comes back to the day")
        p.call("dayKey", 0x01000000, 0)
        # "About this" (slice 2, the rest): a task's chat beside the
        # dashboard is one stream, its own turns and what the day's chat said
        # about it, read from the log; `@` there adds a task of another day
        # as a chip, sent with the message.
        p.call("closePanes")
        p.call("dash")
        p.wait(lambda: any(r.get("text") == "email the dean about the shortlist" for r in json.loads(p.call("dashRows"))), 10)
        p.call("dashFocus", next(i for i, r in enumerate(json.loads(p.call("dashRows"))) if r.get("text") == "email the dean about the shortlist"))
        p.call("dashKey", 0x43, 0)          # C: its chat
        stream = lambda: json.loads(p.call("talkStream"))
        check(p.wait(lambda: any(s["elsewhere"] and s["text"] == "these two" for s in stream()), timeout=12),
              f"a task's chat shows what the day's chat said about it, in one stream ({stream()})")
        check(any(s["elsewhere"] and s["place"] == "in the day's chat" for s in stream()), "…each such turn saying where it was said")
        p.call("chatBoxType", "@rubric")
        check(p.wait(lambda: any("task · ask about the rubric" in h for h in json.loads(p.call("marginMention")))),
              f"@ in a task's chat offers a task of another day ({p.call('marginMention')})")
        p.call("chatBoxKey", 0x01000004)    # Enter: picked
        check(p.wait(lambda: [r["head"] for r in json.loads(p.call("marginRefs"))] == ["ask about the rubric"])
              and p.call("chatBoxText") == "", f"…picked, it is a chip of its own, the words gone from the box ({p.call('marginRefs')})")
        p.call("chatBoxKey", 0x01000003)    # Backspace in the empty box
        check(json.loads(p.call("marginRefs")) == [], "…Backspace in the empty box lets go of it")
        p.call("chatBoxType", "@rubric")
        p.wait(lambda: json.loads(p.call("marginMention")))
        p.call("chatBoxKey", 0x01000004)
        p.call("talkSend", "with the rubric?")
        st_path = p.vault / "agents" / "longhand" / "daily" / f"{TODAY}.json"
        def asked_refs():
            for rec in json.loads(st_path.read_text())["blocks"].values():
                for tt in rec.get("chat") or []:
                    if tt.get("text") == "with the rubric?":
                        return tt.get("refs") or []
            return None
        check(p.wait(lambda: asked_refs() and asked_refs()[0].get("date") == YDAY and "line" in asked_refs()[0], timeout=15)
              and json.loads(p.call("marginRefs")) == [],
              f"…sent with the message, kept on its turn, the box letting go of it ({asked_refs()})")
        p.call("closePanes")
        # The note as the sections after this one expect it.
        (p.daily / f"{TODAY}.md").write_text(note_before)
        p.open_fresh()

        # Words, not numbers (the UX evaluation's re-run, F5): what an answer
        # left out said as the student would; a move named by its task; a
        # row done or dropped shows no line of its chat.
        check(p.call("leftOutSample")
              == "a day for a box that is not on the list; dropping a deadline that is not open; a deadline for “made up”; "
                 "moving a deadline that is not open, or to a day it cannot have",
              f"what an answer left out reads as what it would have done, no numbers ({p.call('leftOutSample')})")
        check("#61" not in p.call("moveSaid", "row") and "Finish the Themenvorschlag" in p.call("moveSaid", "row")
              and "#61" not in p.call("moveSaid", "under"), f"a move's row names its task, not its number ({p.call('moveSaid', 'row')})")
        check(p.call("rowClosedOf", "deadline", "done") == "true" and p.call("rowClosedOf", "task", "cancelled") == "true"
              and p.call("rowClosedOf", "deadline", "open") == "false" and p.call("rowClosedOf", "task", "open") == "false",
              "a row done or dropped is closed, and says no more of its chat")

        # 12c''. what the day may search (slice 2): Settings → Ctrl+F lists the
        # vault's folders, the daily notes' own on; a switch is kept in
        # settings.json; a citation in an answer opens the note at its line.
        KEY_F, KEY_SPACE = 0x46, 0x20
        p.call("settings")
        check(p.call("settingsKey", KEY_F, CTRL) == "false", "Ctrl+F in settings is no longer a key of its own")
        p.call("settingsPick", "search")
        check(p.call("settingsKey", KEY_RETURN, 0) == "true" and p.call("settingsView") == "search",
              "Enter on what the agent may search opens it")
        check(p.wait(lambda: "Daily=on" in json.loads(p.call("searchFolders"))),
              f"…every folder of the vault, the daily notes' own on ({p.call('searchFolders')})")
        i = json.loads(p.call("searchFolders")).index("Daily=on")
        p.call("searchFocus", i)
        p.call("searchKey", KEY_SPACE, 0)
        settings_json = p.tmp / "config" / "longhand" / "settings.json"
        check(p.wait(lambda: settings_json.exists() and json.loads(settings_json.read_text()).get("searchFolders", {}).get("Daily") is False),
              "Space switches a folder off, kept in settings.json")
        p.call("searchKey", KEY_SPACE, 0)
        check(p.wait(lambda: json.loads(settings_json.read_text())["searchFolders"]["Daily"] is True), "…and on again")
        # 12c, the horizon (docs/files.md, 2026-10-26): the row above the
        # folders moves it by a month, Backspace puts it back; a day before
        # it has no agent, and the header says why.
        KEY_LEFT, KEY_BACKSPACE = 0x01000012, 0x01000003
        check(p.wait(lambda: (json.loads(p.call("horizon"))["data"] or {}).get("horizon") == "2000-01-01"),
              f"the horizon is read from the runner ({p.call('horizon')})")
        p.call("searchFocus", -1)
        p.call("searchKey", KEY_LEFT, 0)
        check(p.wait(lambda: json.loads(settings_json.read_text()).get("horizon") == "1999-12-01"),
              "← on the horizon moves it a month earlier, kept in settings.json")
        p.call("searchKey", KEY_BACKSPACE, 0)
        check(p.wait(lambda: "horizon" not in json.loads(settings_json.read_text())), "…and Backspace puts the default back")
        p.call("searchKey", 0x01000000, 0)
        p.call("settingsKey", 0x01000000, 0)
        cur = json.loads(settings_json.read_text())
        settings_json.write_text(json.dumps(dict(cur, horizon=dt.date.today().isoformat())))
        p.call("loadHorizon")
        p.call("openDay", YDAY)
        check(p.wait(lambda: json.loads(p.call("horizon"))["before"] and not json.loads(p.call("horizon"))["agentOn"]),
              f"a day before the horizon: the agent is off for it ({p.call('horizon')})")
        check(p.wait(lambda: json.loads(p.call("privateLook"))["sunk"]), "…and its sheet is the sunk paper")
        settings_json.write_text(json.dumps(cur))
        p.call("loadHorizon")
        p.call("openDay", TODAY)
        check(p.wait(lambda: not json.loads(p.call("horizon"))["before"]), "…and today is not")
        link = p.call("linkCitations", f"You wrote it in `Daily/{YDAY}.md` line 3.")
        check(f"(cite:Daily%2F{YDAY}.md#3)" in link and f"[{YDAY} · line 3]" in link,
              f"a citation in an answer becomes a link ({link!r})")
        p.call("openCitation", f"cite:Daily%2F{YDAY}.md#3")
        check(p.wait(lambda: p.call("header") != "" and not p.call("header").startswith(dt.date.today().strftime("%A")))
              and p.wait(lambda: p.call("cursorLine") == "2"), f"…which opens that day's note at its line ({p.call('cursorLine')})")
        p.call("openDay", TODAY)
        p.wait(lambda: p.call("header").startswith(dt.date.today().strftime("%A")))

        # 12d. Settings → Calendar (2026-10-17): the timetable's address
        # pasted in the page, saved to settings.json, fetched at once, and
        # what came of it said — never the address itself.
        import http.server, threading
        soon = dt.date.today() + dt.timedelta(days=2)
        feed = ("BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:s1\r\n"
                f"DTSTART:{soon:%Y%m%d}T090000\r\nDTEND:{soon:%Y%m%d}T103000\r\n"
                "SUMMARY:A seminar\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n").encode()

        class Uni(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                # /locked plays IT:U's feed on 2026-10-17: a redirect to its
                # sign-in, and a sign-in page where the calendar should be.
                if self.path.startswith("/locked"):
                    self.send_response(307)
                    self.send_header("Location", "/sso/login?id=1")
                    self.end_headers()
                    return
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"<html><title>Sign in to your account</title></html>"
                                 if self.path.startswith("/sso") else feed)

            def log_message(self, *a):
                pass

        uni = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Uni)
        threading.Thread(target=uni.serve_forever, daemon=True).start()
        settings_json = p.tmp / "config" / "longhand" / "settings.json"
        KEY_COMMA, KEY_BACKSPACE = 0x2c, 0x01000003
        check(p.call("pageKey", KEY_COMMA, CTRL) == "true" and p.call("settingsOpen") == "true", "Ctrl+, opens settings")
        check(p.wait(lambda: any("No calendar yet" in l for l in json.loads(p.call("settingsLines")))),
              f"…which says there is no calendar yet ({p.call('settingsLines')})")
        p.call("settingsSave", "not a link")
        check("not a calendar address" in p.call("settingsNote")
              and (not settings_json.exists() or not json.loads(settings_json.read_text()).get("calendars")),
              "something that is not an address is refused, and nothing is written")

        def cals():
            return json.loads(settings_json.read_text()).get("calendars", [])

        url = f"http://127.0.0.1:{uni.server_port}/feed.ics?token=SECRET"
        p.call("settingsSave", url)
        check(p.wait(lambda: settings_json.exists() and [c["url"] for c in cals()] == [url]),
              "a calendar added goes to settings.json, beside the config")
        check(cals()[0]["agent"] == "classes", "…and starts narrow: the agent sees its classes only")
        check(p.wait(lambda: any(l.startswith("Working · fetched just now · 1 event ahead") for l in json.loads(p.call("settingsLines"))), timeout=10),
              f"…is fetched at once, and says what came of it ({p.call('settingsLines')})")
        lines = json.loads(p.call("settingsLines"))
        check(lines[0] == f"127.0.0.1:{uni.server_port} · 127.0.0.1:{uni.server_port}/…" and "SECRET" not in json.dumps(lines),
              f"…named for where it goes, never with its token ({lines[0]})")
        check("The agent sees its classes only" in lines, "…saying what the agent sees of it")
        check(json.loads(p.call("surfaces")).keys() >= {"settings"} and "sheet" not in json.loads(p.call("surfaces")),
              f"settings takes the sheet's place ({p.call('surfaces')})")
        KEY_A = 0x41
        check(p.call("settingsKey", KEY_A, CTRL | SHIFT) == "true", "Ctrl+Shift+A is taken")
        check(p.wait(lambda: cals()[0]["agent"] == "all"
                     and any(l.startswith("The agent sees everything in it") for l in json.loads(p.call("settingsLines")))),
              "…and shares the picked calendar whole: titles, times and places")

        p.call("settingsSave", f"http://127.0.0.1:{uni.server_port}/locked.ics?token=SECRET")
        check(p.wait(lambda: len(cals()) == 2 and json.loads(p.call("settingsLines"))[4].startswith("Not working yet"), timeout=10),
              f"a second calendar, landing on a sign-in page, says it is not working ({p.call('settingsLines')})")
        lines = json.loads(p.call("settingsLines"))
        check("sign-in page" in lines[4] and lines[1].startswith("Working"),
              f"…why, in words, while the first still works ({lines})")
        check(p.call("settingsKey", KEY_BACKSPACE, CTRL | SHIFT) == "false", "Ctrl+Shift+Backspace is no longer a key in settings")
        check(p.call("settingsPicked") == "calendar" and p.call("settingsKey", KEY_DELETE, 0) == "true"
              and p.call("settingsAsking") == "1" and len(cals()) == 2,
              f"Del on the picked calendar asks first, removing nothing yet ({p.call('settingsAsking')}, {len(cals())})")
        check(p.call("settingsKey", KEY_ESC, 0) == "true" and p.call("settingsAsking") == "-1"
              and p.call("settingsOpen") == "true" and len(cals()) == 2, "…Esc keeps it, and settings stays open")
        p.call("settingsKey", KEY_DELETE, 0)
        check(p.call("settingsKey", KEY_RETURN, 0) == "true", "…Del again, then Enter")
        check(p.wait(lambda: [c["url"] for c in cals()] == [url]), "…removes the picked calendar, the new one")
        p.wait(lambda: len(json.loads(p.call("settingsLines"))) < 5)
        p.call("settingsFocus", 0)
        p.call("settingsKey", KEY_DELETE, 0)
        p.call("settingsKey", KEY_RETURN, 0)
        check(p.wait(lambda: cals() == [] and any("No calendar yet" in l for l in json.loads(p.call("settingsLines")))),
              "…and the last one, back to no calendar")
        # Settings is a list (2026-10-28): ↑↓ walk every setting, Space or
        # Enter changes the picked one, typing picks the address field.
        KEY_SPACE, KEY_DOWN, KEY_S = 0x20, 0x01000015, 0x53
        check(p.call("settingsKey", KEY_S, CTRL | SHIFT) == "false", "Ctrl+Shift+S is no longer the sound in settings")
        p.call("settingsPick", "sound")
        was = p.call("tickSoundOn")
        check(p.call("settingsKey", KEY_SPACE, 0) == "true" and p.wait(lambda: p.call("tickSoundOn") != was),
              "Space on the picked sound turns it off or on")
        p.call("settingsKey", KEY_SPACE, 0)
        check(p.wait(lambda: p.call("tickSoundOn") == was), "…and back")
        check(p.call("settingsKey", KEY_DOWN, 0) == "true" and p.call("settingsPicked") == "pointer", "↓ walks on to the pointer")
        mode = p.call("pointerMode")
        p.call("settingsKey", KEY_RETURN, 0)
        check(p.wait(lambda: p.call("pointerMode") != mode), f"…and Enter changes it ({mode} → {p.call('pointerMode')})")
        p.call("settingsKey", KEY_RETURN, 0)
        p.call("settingsKey", KEY_RETURN, 0)
        check(p.wait(lambda: p.call("pointerMode") == mode), "…round to where it was")
        check(p.call("settingsKey", KEY_DOWN, 0) == "true" and p.call("settingsPicked") == "pointer", "…the last row stays the last")
        p.call("settingsType", "w")
        check(p.call("settingsPicked") == "field", "typing from any row picks the address field")
        check(p.call("settingsKey", KEY_SPACE, 0) == "false", "…where Space is typed")
        p.call("settingsType", "")
        check(p.call("settingsKey", 0x01000000, 0) == "true" and p.call("settingsOpen") == "false", "Esc goes back")
        uni.shutdown()

        # 12c'. the calendars and the first pass of the day (2026-10-18): what
        # reads the calendars waits for the fetch the same opening started.
        (p.stub / "slow-fetch").write_text("")
        # A plan still running from before is the day's plan, and the
        # opening asks for no other (runPlan): let it end first, or the
        # opening's never starts and its start was in the log cleared here
        # (slower on Windows, 2026-11-25).
        p.wait(lambda: p.call("planRunning") == "false", 30)
        p.call("closeAll")
        p.calls.write_text("")
        (p.state / "longhand" / "plan.json").unlink(missing_ok=True)
        p.open_fresh()
        def order():
            # Runners started side by side append to the log at once; on
            # Windows an append is a seek and a write, not one step, so a
            # line can come torn: passed over.
            rows = [l.split(" ", 2) for l in p.calls.read_text().splitlines() if l.strip()]
            return [(float(r[0]), r[1], r[2].strip()) for r in rows
                    if len(r) == 3 and re.fullmatch(r"\d+\.\d+", r[0]) and r[1] in ("start", "end")]
        p.wait(lambda: any(r[2].startswith("plan") for r in order()) and any(r[2] == "run open" for r in order()), timeout=12)
        o = order()
        fetch_end = next((t for t, w, r in o if w == "end" and r == "projects"), None)
        first = {r: t for t, w, r in reversed(o) if w == "start"}
        check(fetch_end is not None and first.get("run open", 0) > fetch_end,
              f"the open pass starts after the opening's fetch has ended ({o})")
        check(fetch_end is not None and first.get("plan", 0) > fetch_end, "…and so does the day's plan")
        (p.stub / "slow-fetch").unlink()

        # 12d'. Settings → what the agent knows (slice 3, 2026-10-18): the
        # notebook line by line; forget and correct, kept in corrections.md.
        know = p.vault / "agents" / "longhand" / "knowledge"
        know.mkdir(parents=True, exist_ok=True)
        (know / "profile.md").write_text("# Profile\n\n- Lives in Vienna.\n  - Commutes by train.\n- Grading scale not yet confirmed.\n")
        p.call("settings")
        p.call("settingsPick", "notebook")
        check(p.call("settingsKey", KEY_RETURN, 0) == "true" and p.wait(lambda: p.call("settingsView") == "notebook"),
              "Enter on what the agent knows, in settings, opens it")
        check(p.wait(lambda: any(r["text"] == "Lives in Vienna." for r in json.loads(p.call("notebookRows")))),
              "…its notes, line by line")
        rows = json.loads(p.call("notebookRows"))
        check(rows[0]["kind"] == "head" and rows[0]["text"] == "Profile" and rows[int(p.call("notebookPicked"))]["kind"] == "line",
              "…under each file's title, the first line picked")
        p.call("notebookFocus", next(i for i, r in enumerate(rows) if r["text"] == "Lives in Vienna."))
        check(p.call("notebookKey", KEY_DELETE, 0) == "true" and p.call("notebookAsking") == "true",
              "Del on the picked line asks first")
        check(p.call("notebookKey", KEY_ESC, 0) == "true" and p.call("settingsView") == "notebook"
              and "Vienna" in (know / "profile.md").read_text(), "…Esc keeps it, and stays in the notebook")
        p.call("notebookKey", KEY_DELETE, 0)
        check(p.call("notebookKey", KEY_RETURN, 0) == "true", "…Del again, then Enter forgets it")
        check(p.wait(lambda: "Vienna" not in (know / "profile.md").read_text()), "…taken out of the agent's file, with what hung off it")
        check(p.wait(lambda: "forget · profile.md: «Lives in Vienna.»" in (know / "corrections.md").read_text()),
              "…and recorded in corrections.md, so it stays forgotten")
        check(p.wait(lambda: "stays forgotten" in p.call("notebookNote")), f"…and the page says so ({p.call('notebookNote')})")
        p.wait(lambda: not any(r["text"] == "Lives in Vienna." for r in json.loads(p.call("notebookRows"))))
        rows = json.loads(p.call("notebookRows"))
        p.call("notebookFocus", next(i for i, r in enumerate(rows) if r["text"].startswith("Grading")))
        p.call("notebookKey", KEY_RETURN, 0)
        check(p.call("notebookCorrecting") == "true", "Enter on a line starts correcting it")
        p.call("notebookType", "Grades run 1 to 5; 4 passes.")
        p.call("notebookKey", KEY_RETURN, 0)
        check(p.wait(lambda: "- Grades run 1 to 5; 4 passes.\n" in (know / "profile.md").read_text()),
              f"…Enter puts the student's words in its place (note: {p.call('notebookNote')!r}; "
              f"correcting: {p.call('notebookCorrecting')}; file: {(know / 'profile.md').read_text()!r})")
        check(p.wait(lambda: any(r["kind"] == "correction" and "4 passes" in r["text"] for r in json.loads(p.call("notebookRows")))),
              "…and the correction is listed under the student's corrections")
        check(p.call("notebookKey", KEY_ESC, 0) == "true" and p.call("settingsView") == "main" and p.call("settingsOpen") == "true",
              "Esc goes back to settings")
        p.call("settingsKey", KEY_ESC, 0)

        # 12e. a tick in the note, as in the dashboard: the day it was done
        # on the line, and the sound asked for; an untick takes the day off
        # and is silent.
        if p.call("dashOpen") == "true":
            p.call("dash")
        # A line of its own at the very start (the end of the note may hold
        # a bound line whose hidden tail an insert would land before).
        p.call("cursor", 0)
        p.call("insert", "- [ ] a box ticked in the note\n")
        heard = int(p.call("ticksHeard"))
        p.call("tick", p.line_of("a box ticked in the note"))
        check(p.wait(lambda: f"- [x] a box ticked in the note ✅ {dt.date.today().isoformat()}" in p.call("text")),
              f"Ctrl+L in the note ticks with the day it was done ({p.call('text')[-60:]!r})")
        check(int(p.call("ticksHeard")) == heard + 1, "…and asks for the tick's sound")
        p.call("tick", p.line_of("a box ticked in the note"))
        check(p.wait(lambda: "- [ ] a box ticked in the note" in p.call("text") and "note ✅" not in p.call("text")),
              "…and Ctrl+L again opens it, the day off, in silence")
        check(int(p.call("ticksHeard")) == heard + 1, "…no sound for the untick")

        # 12f. who made it (docs/agent.md): a line the agent made keeps its
        # mark through a tick, becomes "together" when the person changes its
        # words, follows its line, is found again when the note is read, and
        # shows in the dashboard; a deadline the agent proposed is the
        # agent's once written in.
        if p.call("dashOpen") == "true":
            p.call("dash")
        check(p.wait(lambda: p.call("authorOf", p.line_of("Registered topic and supervisor")) == "agent"),
              f"a deadline the agent proposed, written into the note, is the agent's ({p.call('authorOf', p.line_of('Registered topic and supervisor'))!r})")
        # On an empty line: a cursor is never inside a box's own markers, so
        # an insert at the start of a box's line would land in that line.
        p.call("cursor", p.offset_of_line(p.lines().index("")))
        p.call("insert", "- [ ] steps the agent wrote\n")
        ln = p.line_of("steps the agent wrote")
        p.call("markAgent", ln)
        check(p.call("authorOf", ln) == "agent", "a line marked as the agent's is drawn as the agent's")
        check(p.wait(lambda: '"author":"agent"' in p.call("authorsStore").replace(" ", "")),
              "…and kept in the layer, by its words")
        authors_file = p.state / "longhand" / "authors.json"
        check(p.wait(lambda: authors_file.exists() and "steps the agent wrote" in authors_file.read_text()),
              "…written to authors.json, never into the note")
        check("agent" not in p.note().split("steps the agent wrote")[1].split("\n")[0], "…with nothing added to the line")
        p.call("tick", ln)
        check(p.wait(lambda: "- [x] steps the agent wrote ✅" in p.call("text")) and p.call("authorOf", ln) == "agent",
              f"a tick is a fact: still the agent's ({p.call('authorOf', ln)!r}, line {ln}, {p.call('text')[:90]!r})")
        p.call("tick", ln)
        p.wait(lambda: "- [ ] steps the agent wrote\n" in p.call("text"))
        at = p.offset_of_line(ln) + len("- [ ] steps the agent wrote")
        p.call("cursor", at)
        p.call("type", " fully")
        check(p.wait(lambda: p.call("authorOf", p.line_of("steps the agent wrote fully")) == "together"),
              "the person's words in it make it made together")
        p.call("cursor", p.offset_of_line(p.lines().index("")))
        p.call("insert", "A line above it.\n\n")
        check(p.wait(lambda: p.call("authorOf", p.line_of("steps the agent wrote fully")) == "together"),
              "lines added above: the mark follows its line")
        check(p.call("authorOf", p.line_of("A line above it.")) == "", "…and prose is the person's")
        p.call("openDay", YDAY)
        p.wait(lambda: "ask about the rubric" in p.call("text"))
        p.call("openDay", TODAY)
        check(p.wait(lambda: "steps the agent wrote fully" in p.call("text")
                     and p.call("authorOf", p.line_of("steps the agent wrote fully")) == "together"),
              "the note read again: found again by its words")
        p.call("dash")
        def author_row(title):
            rows = json.loads(p.call("dashRows"))
            i = next((n for n, r in enumerate(rows) if r.get("text") == title), -1)
            return p.call("rowAuthor", i) if i >= 0 else None
        check(p.wait(lambda: author_row("steps the agent wrote fully") == "together"),
              f"the dashboard draws it too ({author_row('steps the agent wrote fully')!r})")
        check(p.wait(lambda: author_row("Registered topic and supervisor") == "agent"),
              "…and the agent's deadline there")
        p.call("dash")

        # 12g. the agent plans (docs/agent.md, slice 2): its do-date is a row
        # under the box it is about, accepted with the app's own key, written
        # on the box's line by the page; its question is answered in words;
        # a decline is recorded; nothing is written without the person.
        (p.stub / "plan-on").write_text("")
        if p.call("dashOpen") == "false":
            p.call("dash")
        p.call("plan", "true")

        def asks():
            return [(n, r) for n, r in enumerate(json.loads(p.call("dashRows"))) if r["kind"] in ("proposal", "question")]
        check(p.wait(lambda: any(r["kind"] == "proposal" for _, r in asks()) and any(r["kind"] == "question" for _, r in asks()), timeout=15),
              f"a plan asked for: a do-date and a question arrive as rows ({asks()})")
        rows = json.loads(p.call("dashRows"))
        i, prop = next((n, r) for n, r in asks() if r["kind"] == "proposal")
        check(rows[i - 1]["kind"] in ("task", "deadline") and rows[i - 1]["text"] == prop["under"],
              f"the do-date sits right under the box it is about ({rows[i - 1].get('text')!r} / {prop['under']!r})")
        check(p.call("rowAuthor", i) == "agent", "…marked as the agent's")

        # Whose turn (2026-10-23): what arrived since the dashboard was last
        # left is new, counted on the agent's chip; N walks the queue, round again.
        check(all(r["fresh"] for _, r in asks()) and json.loads(p.call("dashAgent"))["fresh"] == 2,
              f"what arrived since the last visit is new, and counted ({p.call('dashAgent')}; {p.call('newSince')})")
        ask_rows = [n for n, _ in asks()]
        p.call("dashFocus", 0)
        p.call("dashType", "n")
        check(int(p.call("dashAt")) == ask_rows[0], f"N goes to the first thing to settle ({p.call('dashAt')} / {ask_rows})")
        p.call("dashType", "n")
        check(int(p.call("dashAt")) == ask_rows[1], "…N again to the next")
        p.call("dashType", "n")
        check(int(p.call("dashAt")) == ask_rows[0], "…and round again at the end")
        p.call("dashKey", 0x4e, SHIFT)
        check(int(p.call("dashAt")) == ask_rows[1], "Shift+N goes back")
        p.call("dashFocus", 0)
        check(int(p.call("clickAgentChip")) == ask_rows[0], f"the agent's chip, clicked, goes there as N does ({p.call('dashAt')} / {ask_rows})")
        p.call("dash")
        p.call("dash")
        check(not any(r["fresh"] for _, r in asks()) and json.loads(p.call("dashAgent"))["fresh"] == 0,
              f"left and opened again: nothing is new ({p.call('dashAgent')})")
        ledger_file = p.state / "longhand" / "proposals.json"
        notes_before = {f.name: f.read_text() for f in p.daily.glob("*.md")}
        check(all(f.read_text() == notes_before[f.name] for f in p.daily.glob("*.md")), "proposing wrote nothing into a note")
        p.call("dashFocus", i)
        check(p.call("dashKey", 0x20, 0) == "true", "Space on the proposal accepts it")
        when = prop["date"]
        check(p.wait(lambda: any(f"⏳ {when}" in f.read_text() for f in p.daily.glob("*.md"))),
              f"…and the page writes the do-date on the box's line (⏳ {when})")
        check(p.wait(lambda: any(x["kind"] == "do-date" and x["status"] == "accepted"
                                 for x in json.loads(ledger_file.read_text())["items"])), "…recorded as accepted")
        # Its row, by its id: the planner, still on, may have proposed again.
        check(p.wait(lambda: not any(r["kind"] == "proposal" and r["id"] == prop["id"] for _, r in asks())),
              f"…and the row goes ({prop['id']}; {[(r['kind'], r['id']) for _, r in asks()]})")
        qi = next(n for n, r in asks() if r["kind"] == "question")
        p.call("dashFocus", qi)
        p.call("dashKey", KEY_RETURN, 0)
        t = json.loads(p.call("talk"))
        check(t["open"] and t["item"] == "Do you work on weekends?", f"Enter on a question opens a conversation on it ({t})")
        (p.stub / "talk-reply.json").write_text(json.dumps({"reply": "Sundays it is.", "settle": "accept", "answer": "Sometimes, on Sundays"}))
        p.call("talkSend", "sometimes, on sundays")
        answers = p.vault / "agents" / "longhand" / "knowledge" / "answers.md"
        check(p.wait(lambda: answers.exists() and "Do you work on weekends? → Sometimes, on Sundays" in answers.read_text(), 10),
              "…and answering it there, agreed, keeps the answer for the agent")
        check(p.wait(lambda: json.loads(p.call("talk"))["settled"] == "answered" and not any(r["kind"] == "question" for _, r in asks())),
              f"…the question settled, its row gone ({p.call('talk')})")
        check(p.wait(lambda: json.loads(p.call("talk"))["turns"][-1:] == ["agent: Sundays it is."]), "…the planner's last word still in the margin")
        (p.stub / "talk-reply.json").unlink()
        p.call("talkKey", KEY_ESC, 0)
        p.call("plan", "true")
        check(p.wait(lambda: any(r["kind"] == "proposal" for _, r in asks()), timeout=15), "planning again proposes for the next box")
        i2 = next(n for n, r in asks() if r["kind"] == "proposal")
        p.call("dashFocus", i2)
        check(p.call("dashKey", KEY_DELETE, 0) == "true", "Delete on the proposal declines it")
        check(p.wait(lambda: any(x["kind"] == "do-date" and x["status"] == "declined"
                                 for x in json.loads(ledger_file.read_text())["items"])), "…recorded as declined")

        # 12g'. talking with the planner about a proposal (2026-10-20): Enter
        # on its row opens the margin beside the dashboard, on the box's one
        # conversation; the planner answers, revises, and an agreement
        # settles it — written by the page like any accept.
        p.call("cursor", len(p.call("text")))
        p.call("type", "\n- [ ] talk it over ⏫\n- [ ] talk it over again ⏫")
        p.wait(lambda: "talk it over again" in p.note())
        p.call("dash")                            # the dashboard opened again reads the new boxes
        p.call("dash")
        p.wait(lambda: any(r.get("text") == "talk it over again" for r in json.loads(p.call("dashRows"))))
        # The first box is the one whose day was just declined: another day
        # for it, since a declined day is never proposed again.
        (p.stub / "plan-later").write_text("")
        p.call("plan", "true")
        def offered():
            plans = sorted((p.state / "longhand" / "payloads").rglob("*-plan.md")) if (p.state / "longhand" / "payloads").exists() else []
            if not plans:
                return "no plan payload"
            data = json.loads(re.search(r"```json\n(.*?)\n```", plans[-1].read_text(), re.S).group(1))
            led = json.loads(ledger_file.read_text())["items"] if ledger_file.exists() else []
            return {"candidates": [(c["title"], c["due"]) for c in data.get("candidates", [])][:4],
                    "ledger": [(x["kind"], x.get("title"), x.get("date"), x["status"]) for x in led][-6:]}
        check(p.wait(lambda: any(r["kind"] == "proposal" for _, r in asks()), timeout=15), f"a proposal to talk about ({offered()})")
        (p.stub / "plan-later").unlink()
        wide = json.loads(p.call("talk"))["dashWidth"]
        ti = next(n for n, r in asks() if r["kind"] == "proposal")
        p.call("dashFocus", ti)
        check(p.call("dashKey", KEY_RETURN, 0) == "true", "Enter on the proposal")
        t = json.loads(p.call("talk"))
        check(t["open"] and t["visible"] and t["item"].startswith("do ") and t["thread"] != "",
              f"…opens the margin on it, the proposal pinned ({t})")
        check(t["dashWidth"] < wide and t["marginX"] >= t["dashX"] + t["dashWidth"],
              f"…beside the dashboard, which gives up the room ({wide} → {t['dashWidth']}, margin at {t['marginX']})")
        check(p.call("dashOpen") == "true" and p.wait(lambda: json.loads(p.call("talk"))["chatFocus"]),
              "…the dashboard still open, the conversation box ready")
        first = t["id"]
        (p.stub / "talk-reply.json").write_text(json.dumps({"reply": "Tomorrow is free and nothing is due."}))
        p.call("talkSend", "why that day?")
        check(p.wait(lambda: json.loads(p.call("talk"))["turns"] == ["student: why that day?", "agent: Tomorrow is free and nothing is due."], 10),
              f"the planner answers in the margin ({json.loads(p.call('talk'))['turns']})")
        (p.stub / "talk-reply.json").write_text(json.dumps({"reply": "Another day, then.", "revise": "another day"}))
        p.call("talkSend", "I can't, another day please")
        check(p.wait(lambda: json.loads(p.call("talk"))["id"] not in (first, -1), 10),
              f"a revision takes the proposal's place, the conversation following it ({p.call('talk')})")
        revised = next(x for x in json.loads(ledger_file.read_text())["items"] if x["id"] == json.loads(p.call("talk"))["id"])
        check(p.wait(lambda: json.loads(p.call("talk"))["item"].startswith("do " + p.call("sayDate", revised["date"]) + " · ")),
              f"…pinned with its new day ({json.loads(p.call('talk'))['item']})")
        check(any(r["kind"] == "proposal" and r.get("date") == revised["date"] for _, r in asks()),
              "…and its row in the dashboard says so too")
        (p.stub / "talk-reply.json").write_text(json.dumps({"reply": "Good, it is on its line.", "settle": "accept"}))
        p.call("talkSend", "ok, that works")
        check(p.wait(lambda: any(f"⏳ {revised['date']}" in f.read_text() for f in p.daily.glob("*.md")), 10),
              f"agreeing settles it: the page writes the do-date on the box's line (⏳ {revised['date']}; status {p.call('status')!r}; "
              f"calls: {p.calls.read_text().splitlines()[-6:]}; talk: {p.call('talk')})")
        got = next(x for x in json.loads(ledger_file.read_text())["items"] if x["id"] == revised["id"])
        check(p.wait(lambda: next(x for x in json.loads(ledger_file.read_text())["items"] if x["id"] == revised["id"])["status"] == "accepted")
              and next(x for x in json.loads(ledger_file.read_text())["items"] if x["id"] == revised["id"]).get("reason") == "ok, that works",
              f"…accepted, the student's words kept as the reason ({got.get('status')}, {got.get('reason')!r})")
        # The margin hears of it when the talk is read again, after the ledger.
        check(p.wait(lambda: json.loads(p.call("talk"))["settled"] == "accepted"
                     and "Good, it is on its line." in json.loads(p.call("talk"))["turns"][-1]),
              f"…and the margin says how it ended, after the planner's last word ({p.call('talk')[:300]})")
        check(p.call("talkKey", KEY_ESC, 0) == "true" and not json.loads(p.call("talk"))["open"]
              and json.loads(p.call("talk"))["dashWidth"] == wide and p.call("dashOpen") == "true",
              "Esc: back to the list, the dashboard whole again")
        settled = {first, revised["id"]}
        # Ctrl+Shift+Enter on the task's own row (Alt+→ until 2026-10-23):
        # the agent summoned to think it through, on the task's one
        # conversation — the planner's turns in it — and a message there
        # goes to the margin, about the task's block.
        ALT, KEY_RIGHT_ = 0x08000000, 0x01000014
        talked = revised["title"]
        def task_row():
            # A task's row, or — bound to the store by now — its deadline's.
            return next((n for n, r in enumerate(json.loads(p.call("dashRows")))
                         if r.get("kind") in ("task", "deadline") and r.get("text") == talked), -1)
        check(p.wait(lambda: task_row() >= 0),
              f"the task talked about has its row ({talked!r} in {[r.get('text') for r in json.loads(p.call('dashRows')) if r.get('kind') in ('task', 'deadline')]})")
        p.call("dashFocus", task_row())
        check(p.call("dashKey", 0x43, 0) == "true", "C on a task's row")
        check(p.wait(lambda: "student: why that day?" in json.loads(p.call("talk"))["turns"]),
              f"…opens the task's conversation beside the dashboard, what was said with the planner in it ({p.call('talk')})")
        check(json.loads(p.call("talk"))["item"] == "", "…nothing pinned to accept: it is the task itself")
        p.call("talkSend", "help me think it through")
        check(p.wait(lambda: "agent: stub answer to: help me think it through" in json.loads(p.call("talk"))["turns"], 10),
              f"…a message there is answered by the margin agent, in the same conversation ({json.loads(p.call('talk'))['turns'][-3:]})")
        th_key = json.loads(p.call("talk"))["thread"]
        p.call("talkKey", KEY_ESC, 0)
        # Its row, in brief (slice 2): the gutter bar's state, and where the
        # chat left off. Read while it was open, so not unread.
        def chat_row():
            return json.loads(p.call("dashRows"))[task_row()]
        p.call("dash")
        p.call("dash")
        thread_last = json.loads(subprocess.run([str(p.runner), "thread", "--key", th_key], capture_output=True, text=True,
                                                env=p.env).stdout)["turns"][-1]["text"].split("\n")[0]
        check(p.wait(lambda: chat_row().get("chat") == "read" and chat_row().get("last") == thread_last),
              f"the row says its chat was read, and where it left off: the one conversation's last turn ({chat_row()}, {thread_last!r})")
        led = json.loads(ledger_file.read_text())
        led["threads"][th_key]["turns"].append({"role": "agent", "text": "One more thing.\nand a second line", "at": "2099-01-01T00:00:00"})
        ledger_file.write_text(json.dumps(led))
        p.call("dash")
        p.call("dash")
        check(p.wait(lambda: chat_row().get("chat") == "unread" and chat_row().get("last") == "One more thing."),
              f"…a newer word from the agent: unread, its first line ({chat_row()})")
        p.call("dashFocus", task_row())
        p.call("dashKey", 0x43, 0)
        p.wait(lambda: "agent: One more thing.\nand a second line" in json.loads(p.call("talk"))["turns"])
        p.call("talkKey", KEY_ESC, 0)
        check(p.wait(lambda: chat_row().get("chat") == "read"), f"…read once its chat is opened ({chat_row()})")
        check(json.loads((p.state / "longhand" / "page.json").read_text()).get("chatSeen", {}).get(th_key) == "2099-01-01T00:00:00",
              "…and remembered in page.json")
        quiet = [r for r in json.loads(p.call("dashRows")) if r.get("kind") == "task" and r.get("text") != talked and not r.get("priv")]
        check(quiet and any(r.get("chat") == "" for r in quiet), "a box never talked about shows nothing")
        p.call("dash")
        p.call("cursor", p.offset_of_line(next(i for i, l in enumerate(p.lines()) if re.match(r"- \[.\] " + re.escape(talked) + r"( |$)", l))) + 8)
        check(p.wait(lambda: "planner agent: Another day, then." in p.call("noteTurns")
                     and "agent: stub answer to: help me think it through" in p.call("noteTurns")),
              f"the note's margin on the box shows the same one conversation ({p.call('noteTurns')}; chat {p.call('chat')}; line {p.call('cursorLine')})")
        p.call("dash")
        # A box never proposed about. The first candidate by date is the
        # deadline whose do-date was declined; until 2026-11-03 its line was
        # written at the note's end, inside #intsem's section, which changed
        # its key and let the planner offer the declined proposal again.
        (p.stub / "plan-reply.json").write_text(json.dumps({"proposals": [
            {"kind": "do-date", "key_of": "read the paper", "date": (dt.date.today() + dt.timedelta(days=1)).isoformat(),
             "why": "Tomorrow is free."}], "questions": [], "knowledge": []}))
        p.call("plan", "true")
        def planned():
            f = p.stub / "plan-data.json"
            data = json.loads(f.read_text()) if f.exists() else {}
            return {"open": [(b.get("title"), b.get("key"), b.get("due"), b.get("when")) for b in data.get("open_boxes", [])],
                    "candidates": [(c.get("title"), c.get("key")) for c in data.get("candidates", [])],
                    "ledger": [(x["id"], x.get("key"), x.get("date"), x["status"]) for x in json.loads(ledger_file.read_text())["items"]][-5:]}
        check(p.wait(lambda: any(r["kind"] == "proposal" and r["id"] not in settled for _, r in asks()), timeout=15),
              f"another proposal ({planned()}; cancelled by the check: "
              f"{p.cancels.read_text()[-1500:] if p.cancels.exists() else 'nothing'})")
        (p.stub / "plan-reply.json").unlink()
        p.call("dashFocus", next(n for n, r in asks() if r["kind"] == "proposal" and r["id"] not in settled))
        p.call("dashKey", KEY_RETURN, 0)
        other = json.loads(p.call("talk"))["id"]
        check(p.call("talkKey", KEY_DELETE, 0) == "true"
              and p.wait(lambda: next(x for x in json.loads(ledger_file.read_text())["items"] if x["id"] == other)["status"] == "declined"),
              f"Delete on the pinned proposal declines it, as on its row ({p.call('talk')}; calls: {p.calls.read_text().splitlines()[-6:]}; "
              f"ledger: {[(x['id'], x['status']) for x in json.loads(ledger_file.read_text())['items']][-4:]})")
        check(json.loads(p.call("talk"))["settled"] == "declined", "…and the margin says so")
        p.call("dash")
        check(not json.loads(p.call("talk"))["open"] and json.loads(p.call("talk"))["thread"] == "", "closing the dashboard closes the conversation")
        p.call("dash")
        (p.stub / "talk-reply.json").unlink()

        (p.stub / "plan-on").unlink()
        for n, r in asks():
            p.call("dashFocus", n)
            p.call("dashKey", KEY_DELETE, 0)

        # 12h. documents (docs/agent.md, slice 4): a PDF in the inbox that
        # names a course is a row to file it; accepting moves it into the
        # course's documents, which the project in the sidebar lists. An
        # invoice beside it is never shown.
        sys.path.insert(0, str(ROOT / "tests"))
        from test_documents import pdf
        inbox = p.tmp / "Downloads"
        pdf(inbox / "DTM_handout.pdf", "Week two")
        pdf(inbox / "Rechnung_4711.pdf", "Invoice")
        p.call("refreshProposals")
        def filing():
            return [(n, r) for n, r in enumerate(json.loads(p.call("dashRows"))) if r["kind"] == "proposal" and r.get("file")]
        check(p.wait(lambda: len(filing()) == 1), f"a document in the inbox arrives as a row to file it ({filing()}; "
              f"runner: {subprocess.run([str(p.runner), 'proposals'], capture_output=True, text=True, env=p.env).stdout[:400]!r})")
        fi, frow = filing()[0]
        check(frow["file"] == f"{TODAY_ISO} DTM handout.pdf" and "its name says Design Theory" in frow["why"],
              f"…named, and saying why it is the course's ({frow})")
        check("Rechnung" not in p.call("dashRows"), "…and the invoice beside it is not listed")
        check(p.call("rowAuthor", fi) == "agent", "…as the agent's proposal")
        p.call("dashFocus", fi)
        check(p.call("dashKey", 0x20, 0) == "true", "Space files it")
        filed = p.vault / "projects" / "dtm" / "docs" / f"{TODAY_ISO} DTM handout.pdf"
        check(p.wait(lambda: filed.is_file() and not (inbox / "DTM_handout.pdf").exists()),
              "…moved from the inbox into projects/dtm/docs/")
        check((inbox / "Rechnung_4711.pdf").exists(), "…and nothing else moved")
        # Filed by a key pressed in passing (2026-11-18): Ctrl+Z on the
        # dashboard puts it back where it came from, and it is not offered
        # again.
        check(json.loads(p.call("lastUndo")) == {"unfile": frow["id"]}, "…with Ctrl+Z ready to put it back")
        check(p.call("dashKey", 0x5a, CTRL) == "true"
              and p.wait(lambda: (inbox / "DTM_handout.pdf").is_file() and not filed.exists(), timeout=10),
              "Ctrl+Z puts the document back in the inbox")
        p.call("refreshProposals")
        time.sleep(1.5)
        check(not filing(), f"…and it is not offered again ({filing()})")
        (inbox / "DTM_handout.pdf").replace(filed)       # filed again by hand, as the checks after this expect
        time.sleep(1)                                    # the put-back's own read of the projects, done
        p.call("refreshProjects")
        p.call("dash")
        side_was = p.call("sidebarOpen")
        check(p.wait(lambda: "dtm|" in "".join(json.loads(p.call("projects")))), "the projects are listed")
        p.call("openProject", next(n for n, x in enumerate(json.loads(p.call("projects"))) if x.startswith("dtm|")))
        check(p.wait(lambda: [d["name"] for d in json.loads(p.call("projectDocs"))] == [f"{TODAY_ISO} DTM handout"]),
              f"the project in the sidebar lists its documents ({p.call('projectDocs')})")
        # Since the one-list view (ProjectView.js, 2026-11-16) its files
        # are folded at the foot, a key away.
        prows = lambda: json.loads(p.call("projectRows"))["rows"]
        check(p.wait(lambda: "fold|fold:files" in prows()), f"…folded under Files at the foot ({prows()})")
        p.call("projectPick", "fold:files")
        p.call("projectOpenRow")
        check(p.wait(lambda: any(r.startswith("f|") or (r.startswith("doc|") and "DTM handout" in r) for r in prows())),
              f"…which unfolds to them ({prows()})")
        # The project's page (plan.md item 5): P gathers the project into one
        # note outside the vault, opened read-only.
        dash_was = p.call("dashOpen")
        p.call("sideKey", 0x50, 0)                          # P
        fl = lambda: json.loads(p.call("files"))
        check(p.wait(lambda: fl()["filePath"].replace("\\", "/").endswith("/longhand/pages/dtm.md") and fl()["readOnly"]
                     and "Working files" in p.call("text") and "DTM handout" in p.call("text"), 20),
              f"P inside a project opens its page, read-only, its documents on it ({fl()}, {p.call('text')[:300]!r})")
        check(fl()["filePath"].startswith(str(p.state)), "…written in the state folder, not the vault")
        if p.call("dashOpen") != dash_was:
            p.call("dash")
        p.call("leaveProject")
        if p.call("sidebarOpen") != side_was:
            p.call("sidebar")
        read = {"documents": [{"document": "Seven Myths", "words": "autonomy", "found": True, "pages": [1, 4]},
                              {"document": "Brief", "words": "", "found": True, "whole": True},
                              {"document": "Rechnung", "words": "", "found": False}]}
        check(p.call("sayReads", json.dumps(read)) == "read: Seven Myths (p. 1, 4) · Brief (whole)",
              f"under a reply, what the agent read for it, with the pages ({p.call('sayReads', json.dumps(read))})")
        check(p.call("sayReads", json.dumps({"reply": "x"})) == "", "…and nothing when it read nothing")

        # 12i. the agent's other actions (docs/agent.md, slice 5): steps and
        # a deadline proposed and accepted, written by the page as the
        # agent's; a priority raised to "do it and tell me" done on its own,
        # told, and undone with one key; the levels set in Settings.
        p.call("openDay", TODAY)
        p.wait(lambda: p.call("header") != "" and p.call("header").startswith(dt.date.today().strftime("%A")))
        p.call("cursor", len(p.call("text")))
        p.call("type", "\n- [ ] write the essay")
        check(p.wait(lambda: "- [ ] write the essay" in p.note()), "a box to work on")
        poster_day = (dt.date.today() + dt.timedelta(days=20)).isoformat()
        (p.stub / "plan-reply.json").write_text(json.dumps({"proposals": [
            {"kind": "priority", "key_of": "write the essay", "priority": 2, "why": "due soonest"},
            {"kind": "steps", "key_of": "write the essay", "steps": ["outline it", "draft the intro"], "why": "a big box"},
            {"kind": "deadline", "title": "Poster", "date": poster_day, "project": "", "why": "the note says so"},
            {"kind": "project", "name": "Bikeability", "tag": "bikeability", "why": "the notes keep coming back to it"}],
            "questions": [], "knowledge": []}))
        p.call("setAutonomy", "priority", "do")
        settings_json = p.tmp / "config" / "longhand" / "settings.json"
        check(p.wait(lambda: settings_json.exists() and json.loads(settings_json.read_text()).get("autonomy") == {"priority": "do"}),
              "a level set in Settings is kept in settings.json")
        p.call("dash")
        p.call("plan", "true")
        def acts():
            return [(n, r) for n, r in enumerate(json.loads(p.call("dashRows"))) if r["kind"] in ("proposal", "told")]
        def essay_record():
            led = json.loads((p.state / "longhand" / "proposals.json").read_text())["items"]
            return [(x["id"], x["kind"], x.get("title"), x.get("date") or x.get("priority"), x["status"], x.get("auto"), x["at"][11:19])
                    for x in led if "essay" in (x.get("title") or "")]
        check(p.wait(lambda: {r.get("ask") for _, r in acts()} >= {"steps", "deadline", "priority", "project"}, timeout=15),
              f"four kinds arrive as rows ({[(r['kind'], r.get('ask')) for _, r in acts()]}; ledger: {essay_record()}; "
              f"line: {[l for l in p.note().splitlines() if 'write the essay' in l]}; "
              f"runner: {subprocess.run([str(p.runner), 'proposals'], capture_output=True, text=True, env=p.env).stdout[:600]!r}; "
              f"plan: {(p.state / 'longhand' / 'plan.json').read_text() if (p.state / 'longhand' / 'plan.json').exists() else ''!r}; "
              f"stub: {[f.name for f in p.stub.iterdir()]})")
        check(p.wait(lambda: re.search(r"- \[ \] write the essay ⏫", p.note())), "the priority, at do it and tell me, is set on its own")
        told = next(r for _, r in acts() if r.get("ask") == "priority")
        check(told["kind"] == "told" and told["say"].startswith("done: priority ▲ high"), f"…and told ({told['say']!r})")
        check(next(r for _, r in acts() if r.get("ask") == "steps")["say"] == "steps: outline it · draft the intro",
              "steps are proposed under their box")
        # The cursor on the deadline's row while the steps are accepted (by
        # mouse, say): the rows they add above must not move it.
        p.call("dashFocus", next(n for n, r in acts() if r.get("ask") == "deadline"))
        check(p.call("acceptRow", "proposal", "steps") == "true", "the steps accepted")
        check(p.wait(lambda: "  - [ ] outline it" in p.note()) and p.wait(lambda: p.call("focusedDashRow") == "proposal/deadline")
              and p.call("focusedDashRow") == "proposal/deadline",
              f"rows added above the cursor do not move it off its row ({p.call("focusedDashRow")})")
        check(p.wait(lambda: re.search(r"- \[ \] write the essay ⏫[^\n]*\n  - \[ \] outline it\n  - \[ \] draft the intro\n", p.note() + "\n")),
              f"accepting writes the steps under the box, one level in ({p.note()[-160:]!r})")
        check(p.wait(lambda: p.call("authorOf", p.line_of("- [ ] outline it")) == "agent"), "…as the agent's (◇)")
        p.wait(lambda: not any(r.get("ask") == "steps" for _, r in acts()))
        check(p.call("dashKeyOn", "proposal", "deadline", 0x20, 0) == "true", "Space accepts the deadline")
        check(p.wait(lambda: f"- [ ] Poster 📅 {poster_day}" in p.note()),
              f"accepting a deadline found in the writing writes its box (rows now: "
              f"{[(r['kind'], r.get('ask'), r.get('say')) for _, r in acts()]}; text has it: {'Poster' in p.call('text')}; "
              f"note tail: {p.note()[-160:]!r}; ledger: {[(x['kind'], x['status']) for x in json.loads(ledger_file.read_text())['items'][-4:]]})")
        check(p.wait(lambda: p.call("authorOf", p.line_of("Poster 📅")) == "agent"), "…the agent's too")
        p.wait(lambda: not any(r.get("ask") == "deadline" for _, r in acts()))
        made = p.vault / "agents" / "longhand" / "knowledge" / "projects" / "bikeability.md"
        check(next(r for _, r in acts() if r.get("ask") == "project")["say"] == "make it a project: Bikeability #bikeability"
              and not made.exists(), "a new project is proposed, and nothing made until it is accepted")
        check(p.call("acceptRow", "proposal", "project") == "true", "the project accepted")
        check(p.wait(lambda: made.exists()) and made.read_text() == "# Bikeability\n\n- Tag: `#bikeability`\n",
              "…makes it, by the runner")
        check(p.wait(lambda: any(x.startswith("bikeability|") for x in json.loads(p.call("projects")))), "…and the page lists it")
        made.unlink()
        check(p.call("dashKeyOn", "told", "priority", KEY_RETURN, 0) == "true"
              and json.loads(p.call("talk"))["item"].startswith("done: priority"),
              f"Enter on what it did on its own opens a conversation too ({json.loads(p.call('talk'))['item']!r})")
        p.call("talkKey", KEY_ESC, 0)
        check(p.call("dashKeyOn", "told", "priority", KEY_DELETE, 0) == "true", "Delete on what it did undoes it")
        check(p.wait(lambda: re.search(r"- \[ \] write the essay(?! ⏫)[^\n⏫]*\n  - \[ \] outline it", p.note())),
              f"…the priority comes off the line ({p.note()[-200:]!r})")
        check(p.wait(lambda: any(x["kind"] == "priority" and x["status"] == "undone"
                                 for x in json.loads(ledger_file.read_text())["items"])), "…recorded as undone")
        (p.stub / "plan-reply.json").unlink()
        p.call("dash")
        p.call("settings")
        KEY_M, KEY_RIGHT = 0x4d, 0x01000014
        p.call("settingsPick", "autonomy")
        check(p.call("settingsKey", KEY_RETURN, 0) == "true" and p.call("settingsView") == "autonomy", "Enter on what the agent may do opens it")
        check(p.wait(lambda: "priority=do" in p.call("autonomyKinds") and len(json.loads(p.call("autonomyKinds"))) == 11),
              f"…every kind with its level ({p.call('autonomyKinds')})")
        p.call("autonomyFocus", 0)
        p.call("autonomyKey", KEY_RIGHT, 0)
        check(p.wait(lambda: json.loads(settings_json.read_text())["autonomy"].get("do-date") == "do"),
              "→ raises the picked kind one level")
        last = json.loads(p.call("autonomyKinds")).index("done=ask")
        p.call("autonomyFocus", last)
        p.call("autonomyKey", KEY_RIGHT, 0)
        check(p.wait(lambda: json.loads(settings_json.read_text())["autonomy"].get("done") == "never"),
              "…a question only goes from ask me straight to never")
        p.call("autonomyKey", 0x01000000, 0)
        p.call("settingsKey", 0x01000000, 0)
        settings_json.write_text(json.dumps({k: v for k, v in json.loads(settings_json.read_text()).items() if k != "autonomy"}))

        # 12i'. the day conversation's @ and its cards (slice 3): `@` lists
        # the note's blocks and points at one; what the day proposes is
        # checked as the planner's are and shows as a card under the answer,
        # the same item as the dashboard's row: ↑ from the empty box onto
        # the cards, Enter does it, Del declines.
        if p.call("dashOpen") == "true":
            p.call("dash")
        (p.daily / f"{TODAY}.md").write_text(p.note().rstrip("\n") + "\n\n- [ ] read the ethics chapter\n")
        p.open_fresh()
        p.wait(lambda: "read the ethics chapter" in p.call("text"))
        p.call("seal")
        p.wait(lambda: p.call("dayShown") == "true")
        p.call("dayType", "about @ethics")
        check(p.wait(lambda: json.loads(p.call("dayMention")) and "read the ethics chapter" in json.loads(p.call("dayMention"))[0]),
              f"@ in the day's box lists the note's blocks, narrowed as you type ({p.call('dayMention')})")
        check(p.call("dayKey", KEY_RETURN, 0) == "true" and p.call("dayBlockText").startswith("read the ethics chapter")
              and p.call("dayFieldText") == "about ", f"Enter points at it, and the @words leave the box ({p.call('dayFieldText')!r})")
        exam_day = (dt.date.today() + dt.timedelta(days=9)).isoformat()
        (p.stub / "day-reply.json").write_text(json.dumps([
            {"kind": "priority", "key_of": "read the ethics chapter", "priority": 1, "why": "the exam is close"},
            {"kind": "deadline", "title": "Ethics exam", "date": exam_day, "project": "", "source": "the note", "why": "said so"},
            {"kind": "do-date", "key": "no such box", "date": exam_day, "why": "made up"}]))
        p.call("dayType", "about PROPOSE what to do with it")
        p.call("dayKey", KEY_RETURN, 0)
        check(p.wait(lambda: json.loads(p.call("dayCards")) == [{"kind": "priority", "state": "open"}, {"kind": "deadline", "state": "open"}], timeout=15),
              f"what it proposes, checked, shows as cards under the answer ({p.call('dayCards')})")
        (p.stub / "day-reply.json").unlink()
        check(p.call("dayKey", 0x01000013, 0) == "true" and p.call("dayCardFocus") == "1", "↑ from the empty box: onto the last card")
        check(p.call("dayKey", 0x01000007, 0) == "true"
              and p.wait(lambda: [c["state"] for c in json.loads(p.call("dayCards"))] == ["open", "declined"]),
              f"Del declines it ({p.call('dayCards')})")
        check(p.wait(lambda: any(x["kind"] == "deadline" and x.get("from") == "day" and x["status"] == "declined"
                                 for x in json.loads(ledger_file.read_text())["items"])), "…in the one ledger")
        check(p.call("dayCardFocus") == "0" and p.call("dayKey", KEY_RETURN, 0) == "true"
              and p.wait(lambda: re.search(r"- \[ \] read the ethics chapter 🔼", p.note())),
              f"Enter does what the card says, written by the page ({p.note()[-120:]!r})")
        check(p.wait(lambda: [c["state"] for c in json.loads(p.call("dayCards"))] == ["accepted", "declined"])
              and p.call("dayCardFocus") == "-1", f"…the cards stay, faint, saying how; the keys back in the box ({p.call('dayCards')})")
        # Helpful or not (slice 5): Alt+= on the last answer, kept on its turn.
        day_state = p.vault / "agents" / "longhand" / "daily" / f"{TODAY}.json"
        check(p.call("dayKey", 0x3d, 0x08000000) == "true"
              and p.wait(lambda: (json.loads(day_state.read_text())["day"]["turns"][-1].get("rating") or {}).get("value") == "up"),
              "Alt+= says the day's last answer was helpful, kept on its turn")
        p.call("dayKey", 0x3d, 0x08000000)
        check(p.wait(lambda: "rating" not in json.loads(day_state.read_text())["day"]["turns"][-1]), "…and again takes it back")
        # What one message can do from anywhere (slice 4 of "One
        # conversation"): a task asked for, a card that writes it into
        # today's note under its course; a box ticked because the student
        # asked, done at once and told, one key undoing it; something opened.
        (p.stub / "day-reply.json").write_text(json.dumps([
            {"kind": "task", "title": "email the dean about the exam", "project": "", "why": "asked"},
            {"kind": "done", "key_of": "read the ethics chapter", "asked": True, "why": "asked"}]))
        p.call("dayType", "add a task and PROPOSE ticking the chapter")
        p.call("dayKey", KEY_RETURN, 0)
        check(p.wait(lambda: re.search(r"- \[x\] read the ethics chapter", p.note()), timeout=15),
              f"a box ticked because the student asked is ticked at once, by the page ({p.note()[-160:]!r})")
        check(p.wait(lambda: sorted(json.loads(p.call("dayOpenCardKinds"))) == ["done", "task"], timeout=8),
              f"…shown as a card to let stand or undo, beside the new task's ({p.call('dayCards')})")
        (p.stub / "day-reply.json").unlink()
        idx = json.loads(p.call("dayOpenCardKinds")).index("task")
        p.call("dayCardAt", idx)
        check(p.call("dayKey", KEY_RETURN, 0) == "true" and p.wait(lambda: "- [ ] email the dean about the exam" in p.note()),
              f"Enter on the task's card writes it into today's note ({p.note()[-160:]!r})")
        idx = json.loads(p.call("dayOpenCardKinds")).index("done")
        p.call("dayCardAt", idx)
        check(p.call("dayKey", 0x01000007, 0) == "true" and p.wait(lambda: re.search(r"- \[ \] read the ethics chapter", p.note())),
              f"Del on the tick undoes it: the box open again ({p.note()[-160:]!r})")
        (p.stub / "day-open.json").write_text(json.dumps([{"day": str(dt.date.today() - dt.timedelta(days=1))}]))
        p.call("dayType", "open yesterday")
        p.call("dayKey", KEY_RETURN, 0)
        yday = (dt.date.today() - dt.timedelta(days=1)).strftime("%Y.%m.%d")
        check(p.wait(lambda: p.call("noteDate") == yday, timeout=15), f"what it opens is opened when the answer arrives ({p.call('noteDate')})")
        (p.stub / "day-open.json").unlink()
        p.call("openDay", TODAY)
        p.call("dayKey", 0x01000000, 0)

        # 12b. the keys sheet: every key the page answers to, listed; one
        # moved through the sheet, kept in keys.json, and working in the note
        # (onto Ctrl+Shift+K, free since Ctrl+K became the link, 2026-10-28)
        KEY_B, KEY_K = 0x42, 0x4b
        keysjson = p.tmp / "config" / "longhand" / "keys.json"

        def keys_of(i):
            return json.loads(p.call("keysOf", i))

        p.call("keys")
        check(p.call("keysOpen") == "true", "the keys sheet opens")
        check(keys_of("bold") == ["Ctrl+B"] and keys_of("dashPriority") == ["p"], "…listing every key, bold on Ctrl+B")
        p.call("keysFind", "bold")
        p.call("keysKey", KEY_RETURN, 0)
        p.call("keysKey", KEY_K, CTRL | SHIFT)
        check(keys_of("bold") == ["Ctrl+Shift+K"], "Enter, then a key: bold moves to it")
        check(p.wait(lambda: keysjson.exists() and json.loads(keysjson.read_text()) == {"bold": ["Ctrl+Shift+K"]}),
              "…and keys.json keeps only that")
        p.call("keysFind", "italic")
        p.call("keysKey", KEY_RETURN, 0)
        p.call("keysKey", KEY_K, 0)
        check("would be typed" in p.call("keysNote"), f"a letter alone is refused where you write ({p.call('keysNote')})")
        p.call("keysKey", KEY_K, CTRL | SHIFT)
        check("again" in p.call("keysNote") and keys_of("bold") == ["Ctrl+Shift+K"], "a key bold has: asked first, not taken")
        p.call("keysKey", KEY_K, CTRL | SHIFT)
        check(keys_of("italic") == ["Ctrl+Shift+K"] and keys_of("bold") == [], "…and taken on the second press")
        check(p.call("tip", "italic") == "does   Ctrl+Shift+K" and p.call("tip", "bold") == "does   no key (Ctrl+/ gives it one)",
              f"a hover's hint names the moved key, or says there is none ({p.call('tip', 'bold')!r})")
        p.call("keysFind", "bold")
        p.call("keysKey", KEY_DELETE, 0)
        check(keys_of("bold") == ["Ctrl+B"], "Del gives bold its own key back")
        check(p.wait(lambda: json.loads(keysjson.read_text()) == {"italic": ["Ctrl+Shift+K"]}), "…and the file follows")
        p.call("keysKey", KEY_ESC, 0)
        p.call("keysKey", KEY_ESC, 0)
        check(p.call("keysOpen") == "false", "Esc clears the search, then closes the sheet")

        # Edited by hand, read again; the moved key works in the note.
        keysjson.write_text(json.dumps({"bold": ["ctrl+shift+k"]}))
        check(p.wait(lambda: keys_of("bold") == ["Ctrl+Shift+K"]), "keys.json edited by hand is read again")
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "a word here\n")
        p.open_fresh()
        p.wait(lambda: "a word here" in p.call("text"))
        p.call("cursor", p.call("text").index("word") + 1)
        check(p.call("pageKey", KEY_B, CTRL) == "false", "Ctrl+B is nothing once bold has moved")
        check(p.call("pageKey", KEY_K, CTRL | SHIFT) == "true", "…and Ctrl+Shift+K is bold")
        check(p.call("tip", "ask") == "does   Ctrl+Enter" and p.call("tip", "bold") == "does   Ctrl+Shift+K", "…and the hints say so")
        check(p.wait(lambda: "a **word** here" in p.call("text")), f"…on the word ({p.call('text')!r})")
        keysjson.write_text("{}\n")
        check(p.wait(lambda: keys_of("bold") == ["Ctrl+B"]), "an empty keys.json is every key its own")

        # 12b. The panes (docs/navigation.md): the digits are the sidebar,
        # the middle and the agent's pane, from any box; a pane's number goes
        # there, opening it, and in it switches what the pane shows; Ctrl+\
        # and Ctrl+| open and close the side panes; Esc closes what it is
        # in. The window never has the keyboard, but the page's own focus is
        # real in it, so where the keys land (`here`) is checked; the frame
        # and the pointer are not.
        KEY_1, KEY_2, KEY_3, KEY_BS, KEY_BAR = 0x31, 0x32, 0x33, 0x5c, 0x7c
        def panes():
            return json.loads(p.call("panes"))
        p.call("closePanes")
        check(panes()["panes"] == ["center"] and panes()["center"] == "note", f"the note alone ({panes()})")
        # At 701 px (narrow window), side panes are mutually exclusive so the
        # note stays readable: opening one closes the opposite.
        check(p.call("pageKey", KEY_1, CTRL) == "true" and panes()["panes"] == ["left", "center"] and panes()["here"] == "left",
              f"Ctrl+1 opens the sidebar, the keys in it ({panes()})")
        check(p.call("pageKey", KEY_3, CTRL) == "true" and panes()["panes"] == ["center", "right"] and panes()["here"] == "right",
              f"on a narrow window, Ctrl+3 closes the sidebar so the note stays readable ({panes()})")
        check(p.call("pageKey", KEY_1, CTRL) == "true" and panes()["panes"] == ["left", "center"] and panes()["here"] == "left",
              f"…and Ctrl+1 closes the agent's pane ({panes()})")
        p.call("closePanes")
        # Wide enough for both side panes beside a >= 420 px note:
        p.resize(1150, 850)
        p.call("closePanes")
        check(p.call("pageKey", KEY_1, CTRL) == "true" and panes()["panes"] == ["left", "center"] and panes()["here"] == "left",
              f"Ctrl+1 opens the sidebar on a wide window ({panes()})")
        space = json.loads(p.call("files"))["space"]
        check(p.call("sideKey", KEY_1, CTRL) == "true" and json.loads(p.call("files"))["space"] != space and panes()["panes"] == ["left", "center"],
              f"…Ctrl+1 in it: the other space, nothing closed ({p.call('files')[:60]})")
        p.call("sideKey", KEY_1, CTRL)
        check(json.loads(p.call("files"))["space"] == space, "…and again, back")
        check(p.call("pageKey", KEY_3, CTRL) == "true" and panes()["panes"] == ["left", "center", "right"] and panes()["right"] == "day"
              and panes()["here"] == "right", f"Ctrl+3 opens the agent's pane, on the day, the keys in it ({panes()})")
        def against():
            sd = json.loads(p.call("sides"))
            return sd["left"] is not None and sd["right"] is not None \
                and sd["left"] == sd["edge"] and sd["rightEnd"] == sd["width"] - sd["edge"] \
                and sd["x"] >= sd["leftEnd"] + sd["gap"] and sd["x"] + sd["w"] + sd["gap"] <= sd["right"]
        check(p.wait(against, 2), f"both panes stand against the window's edges, the note between them ({p.call('sides')})")
        check(p.call("pageKey", KEY_2, CTRL) == "true" and panes()["here"] == "center" and panes()["center"] == "note",
              f"Ctrl+2 from the agent's pane: the keys to the middle, nothing flipped ({panes()})")
        check(p.call("pageKey", KEY_2, CTRL) == "true" and panes()["center"] == "dash" and panes()["right"] == "day",
              f"…and again in the middle: the dashboard, the day beside it ({panes()})")
        check(p.call("dashKey", KEY_ESC, 0) == "true" and panes()["center"] == "note" and panes()["right"] == "day",
              f"Esc on the dashboard: the note, the day still beside it ({panes()})")
        check(p.call("pageKey", KEY_3, CTRL) == "true" and panes()["here"] == "right", f"Ctrl+3 from the note: the keys to the day ({panes()})")
        check(p.call("dayKey", 0x48, CTRL) == "true" and panes()["here"] == "center" and panes()["center"] == "note"
              and panes()["right"] == "day", f"Ctrl+H from the agent's pane: home, today's note with the keys, the pane left open ({panes()})")
        check(p.call("pageKey", KEY_BS, CTRL) == "true" and panes()["panes"] == ["center", "right"] and panes()["here"] == "center",
              f"Ctrl+\\ with the keys in the middle closes the sidebar ({panes()})")
        check(p.call("pageKey", KEY_BAR, CTRL) == "true" and panes()["panes"] == ["center"],
              f"Ctrl+| closes the agent's pane, wherever the keys are ({panes()})")
        check(p.call("pageKey", KEY_BAR, CTRL) == "true" and panes()["right"] == "day" and panes()["here"] == "right",
              f"…and opens it again, on the day ({panes()})")
        check(p.call("pageKey", KEY_BS, CTRL) == "true" and panes()["panes"] == ["left", "center", "right"] and panes()["here"] == "left",
              f"Ctrl+\\ opens the sidebar, the keys in it ({panes()})")
        p.call("pageKey", KEY_3, CTRL)
        check(p.call("dayKey", KEY_ESC, 0) == "true" and panes()["panes"] == ["left", "center"],
              f"Esc in the day's chat closes the pane ({panes()})")
        # Ctrl+Alt+2: the dashboard from anywhere, in one press; it only
        # shows, so pressed on it it stays; it is a step back can undo.
        ALT2 = CTRL | 0x08000000
        p.call("pageKey", KEY_1, CTRL)
        check(panes()["here"] == "left" and panes()["center"] == "note", f"the keys in the sidebar, the note in the middle ({panes()})")
        check(p.call("sideKey", KEY_2, ALT2) == "true" and panes()["center"] == "dash" and panes()["here"] == "center",
              f"Ctrl+Alt+2 from the sidebar: the dashboard in one press, the keys on it ({panes()})")
        check(p.call("dashKey", KEY_2, ALT2) == "true" and panes()["center"] == "dash",
              f"…pressed on it, it stays ({panes()})")
        p.call("pageKey", KEY_1, CTRL)
        check(p.call("sideKey", KEY_2, ALT2) == "true" and panes()["center"] == "dash" and panes()["here"] == "center",
              f"…from the sidebar with the dashboard up: the keys to it, nothing flipped ({panes()})")
        p.call("dashKey", 0x2f, CTRL)
        check(panes()["center"] == "keys", f"the keys sheet over the dashboard ({panes()})")
        check(p.call("keysKey", KEY_2, ALT2) == "true" and panes()["center"] == "dash" and p.call("keysOpen") == "false",
              f"…Ctrl+Alt+2 closes it, the dashboard back ({panes()})")
        check(p.call("dashKey", 0x5b, CTRL) == "true" and panes()["center"] == "note",
              f"Ctrl+[ after it: the note, one step back ({panes()})")
        p.call("pageKey", 0x2f, CTRL)
        check(p.call("keysKey", KEY_2, ALT2) == "true" and panes()["center"] == "dash" and p.call("keysOpen") == "false",
              f"Ctrl+Alt+2 from the keys over the note: the dashboard ({panes()})")
        p.call("dashKey", KEY_ESC, 0)
        check(panes()["pointer"] == "panes", "the pointer follows pane changes unless told otherwise")
        p.call("closePanes")

        # 12c. Hyprland's six: listed as Hyprland's until the page is let
        # keep them (Enter twice on the row that offers), then moved like
        # the rest — into hypr/longhand.lua, never a line the student wrote —
        # with Hyprland in a submap of the sheet's own while it waits.
        META, ALT, KEY_F, KEY_L = 0x10000000, 0x08000000, 0x46, 0x4c
        calls = p.hypr / "calls"
        ours = p.hypr / "longhand.lua"

        def hk():
            return json.loads(p.call("hyprKeys"))

        def hrow(i):
            return next(a for a in hk()["actions"] if a["id"] == i)["keys"]

        def last_call():
            return calls.read_text().splitlines()[-1]

        p.call("keys")
        check(p.wait(lambda: hrow("pomoToggle") == ["Alt+Super+P"]), "the sheet reads Hyprland's key for the timer")
        rows = json.loads(p.call("keyRows"))
        check(any(r["kind"] == "offer" for r in rows) and next(r for r in rows if r["id"] == "hypr:pomoToggle")["kind"] == "fixed",
              "…listed as Hyprland's, under a row that offers to keep them")
        p.call("keysFind", "pomo toggle")
        p.call("keysKey", KEY_RETURN, 0)
        check("Enter again" in p.call("keysNote") and not ours.exists(), "Enter on it says what it will write, and writes nothing")
        p.call("keysKey", KEY_RETURN, 0)
        # The adopt waits behind the sheet's read of the keys (hyprNext),
        # and writes, backs up and reloads: with three suites at once here
        # the two took 13 s (2026-11-25). Waited for longer.
        check(p.wait(lambda: hk()["owned"], 10), "…Enter again: the page keeps them")
        b = (p.hypr / "bindings.lua").read_text()
        check(b.count("hypr.longhand") == 1 and '-- o.bind("SUPER + ALT + P", "Pomo toggle"' in b and b.startswith('o.bind("SUPER + SHIFT + T"'),
              "…bindings.lua loads longhand.lua, the six commented out, the student's own line kept")
        check([x.read_text() for x in p.hypr.glob("bindings.lua.bak.*")] == [BINDINGS], "…after a backup of it as it was")
        p.call("keysFind", "pomo toggle")
        check(json.loads(p.call("keyRows"))[1]["kind"] == "hypr", "the timer's row moves now")
        p.call("keysKey", KEY_RETURN, 0)
        check(p.call("keysListening") == "true" and p.wait(lambda: 'hl.dsp.submap("longhand-keys"))' in last_call()),
              "Enter: Hyprland goes into the sheet's submap while it waits")
        p.call("keysKey", KEY_K, ALT)
        check(p.wait(lambda: "Super" in p.call("keysNote")) and p.call("keysListening") == "true",
              f"a key without Super is refused, still waiting ({p.call('keysNote')})")
        p.call("keysKey", KEY_K, ALT | META)
        check(p.wait(lambda: hrow("pomoToggle") == ["Alt+Super+K"]), "Super+Alt+K: the timer moves to it")
        check('o.bind("SUPER + ALT + K", "Pomo toggle", "pomo toggle")' in ours.read_text() and "reload config-only" in calls.read_text(),
              "…written into longhand.lua, and Hyprland reloaded")
        # (Not the very last call: the pointer following the keys asks
        # Hyprland too, docs/navigation.md.)
        def left_submap():
            ls = calls.read_text().splitlines()
            enter = max((n for n, l in enumerate(ls) if 'hl.dsp.submap("longhand-keys"))' in l), default=-1)
            return any(l.startswith("eval if hl.get_current_submap()") for l in ls[enter + 1:])
        check(p.wait(lambda: p.call("keysListening") == "false" and left_submap()),
              "…and out of the submap")
        p.call("keysKey", KEY_RETURN, 0)
        p.call("keysKey", KEY_F, ALT | META)
        check(p.wait(lambda: "Full width" in p.call("keysNote")) and hrow("pomoToggle") == ["Alt+Super+K"],
              "Super+Alt+F, Hyprland's Full width: asked first, not taken")
        p.call("keysKey", KEY_F, ALT | META)
        check(p.wait(lambda: hrow("pomoToggle") == ["Alt+Super+F"]), "…and taken on the second press")
        check('hl.unbind("SUPER + ALT + F")  -- was: Full width' in ours.read_text(), "…unbound in longhand.lua, saying what it was")
        p.call("keysKey", KEY_DELETE, 0)
        check(p.wait(lambda: hrow("pomoToggle") == ["Alt+Super+P"]), "Del gives the timer its own key back")
        check("hl.unbind" not in ours.read_text(), "…and Full width its own")
        (p.hypr / "break").write_text("SUPER + ALT + L")
        before = ours.read_text()
        p.call("keysKey", KEY_RETURN, 0)
        p.call("keysKey", KEY_L, ALT | META)
        check(p.wait(lambda: "refused" in p.call("keysNote")) and ours.read_text() == before and hrow("pomoToggle") == ["Alt+Super+P"],
              "a key Hyprland refuses: the file is put back, and the sheet says so")
        p.call("keysKey", KEY_ESC, 0)
        # Not the very last call, as above: the pointer asks Hyprland too.
        check(p.wait(lambda: p.call("keysListening") == "false" and left_submap()),
              "Esc stops waiting and leaves the submap")
        (p.hypr / "break").unlink()
        p.call("keysKey", KEY_ESC, 0)
        p.call("keysKey", KEY_ESC, 0)

        # 12d. days by key: the day before or after that has a note, and
        # today from anywhere, the dashboard included
        ALT, KEY_H, KEY_PGUP, KEY_LBRACKET, KEY_RBRACKET = 0x08000000, 0x48, 0x01000016, 0x5b, 0x5d
        p.call("closeAll")
        for old in p.daily.glob("*.md"):
            old.unlink()
        before = (dt.date.today() - dt.timedelta(days=3)).strftime("%Y.%m.%d")
        (p.daily / f"{before}.md").write_text(header(before) + "three days ago\n")
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "today's words\n")
        p.open_fresh()
        p.wait(lambda: "today's words" in p.call("text"))
        ALT_ = 0x08000000
        p.call("pageKey", KEY_LBRACKET, ALT_)
        check(p.wait(lambda: "three days ago" in p.call("text")), "Alt+[: the day before that has a note, days without one skipped")
        p.call("pageKey", KEY_PGUP, CTRL)
        check(p.wait(lambda: "no note before" in p.call("hint")), f"…and at the first note Ctrl+PgUp says so ({p.call('hint')!r})")
        p.call("pageKey", KEY_RBRACKET, ALT_)
        check(p.wait(lambda: "today's words" in p.call("text")), "Alt+]: the next one")
        p.call("pageKey", KEY_LBRACKET, ALT_)
        p.wait(lambda: "three days ago" in p.call("text"))
        p.call("dash")
        p.call("dashKey", KEY_H, CTRL)
        check(p.wait(lambda: "today's words" in p.call("text") and p.call("dashOpen") == "false"),
              "Ctrl+H from the dashboard: today's note, the dashboard closed")

        # A bound line moved with Alt+Up keeps its deadline; nothing asks.
        p.call("cursorEnd")
        p.call("enter")
        p.call("type", "- [ ] essay due fri 17:00")
        p.call("cursor", 1)
        p.wait(lambda: "essay 📅 " in p.note())
        def essay_line():
            return next(i for i, l in enumerate(p.call("text").split("\n")) if "essay" in l)
        was = essay_line()
        p.call("cursor", p.call("text").index("essay") + 1)
        p.call("moveLines", -1)
        check(p.wait(lambda: essay_line() == was - 1), f"Alt+Up moves the line up one ({p.call('text')!r})")
        check(p.call("ask") == "null" and "^d" in next(l for l in p.call("text").split("\n") if "essay" in l),
              "…with its deadline anchor, and nothing asked")

        # 12e. in the window, nothing is drawn on anything else: the sidebar
        # beside the note, the dashboard and the keys sheet; the margin never
        # over the dashboard
        def overlaps():
            sf = json.loads(p.call("surfaces"))
            names = sorted(sf)
            bad = [(a, b) for i, a in enumerate(names) for b in names[i + 1:]
                   if sf[a]["x"] < sf[b]["x"] + sf[b]["w"] and sf[b]["x"] < sf[a]["x"] + sf[a]["w"]]
            return sf, bad

        p.open_fresh()
        p.call("sidebar")
        for what, on, off in (("the note", None, None), ("the dashboard", "dash", "dash"), ("the keys sheet", "keys", "keys")):
            if on:
                p.call(on)
            time.sleep(0.3)
            sf, bad = overlaps()
            check("sidebar" in sf and not bad, f"the sidebar beside {what}, nothing over it ({sf})")
            if off:
                p.call(off)
        p.call("marginOpen", "true")
        p.call("dash")
        time.sleep(0.3)
        sf, bad = overlaps()
        check("margin" not in sf and not bad, f"a margin left open does not sit on the dashboard ({sf})")
        p.call("dash")
        p.call("marginOpen", "false")
        p.call("sidebar")

        # 14. the window's own, the shape the student uses most (2026-10-25):
        # Esc in the note leaves it open; Alt+←/→ walk the open panes and
        # stop at the edges; a sheet opened from a pane gives the keys back
        # to that pane when it closes (openedFrom, docs/navigation.md).
        ALT, KEY_LEFT, KEY_RIGHT_A, KEY_SLASH, KEY_F11 = 0x08000000, 0x01000012, 0x01000014, 0x2f, 0x0100003a
        def shape():
            return json.loads(p.call("state"))
        p.open_fresh()
        p.call("closePanes")
        check(p.call("pageKey", KEY_ESC, 0) == "true" and shape()["window"] and not shape()["overlay"],
              f"Esc in the note leaves the window open ({shape()})")
        p.call("pageKey", KEY_1, CTRL)
        p.call("pageKey", KEY_3, CTRL)
        check(panes()["panes"] == ["left", "center", "right"] and panes()["here"] == "right", f"three panes, the keys on the right ({panes()})")
        p.call("pageKey", KEY_LEFT, ALT)
        check(panes()["here"] == "center", f"Alt+←: the middle ({panes()})")
        p.call("pageKey", KEY_LEFT, ALT)
        check(panes()["here"] == "left", f"…Alt+← again: the sidebar ({panes()})")
        p.call("pageKey", KEY_LEFT, ALT)
        check(panes()["here"] == "left" and panes()["panes"] == ["left", "center", "right"],
              f"…and at the edge nothing opens or closes ({panes()})")
        p.call("pageKey", KEY_RIGHT_A, ALT)
        p.call("pageKey", KEY_RIGHT_A, ALT)
        check(panes()["here"] == "right", f"Alt+→ twice: back on the right ({panes()})")
        p.call("pageKey", KEY_RIGHT_A, ALT)
        check(panes()["here"] == "right" and panes()["panes"] == ["left", "center", "right"],
              f"…and at the right edge, from a pane, nothing opens ({panes()})")
        check(p.call("pageKey", KEY_SLASH, CTRL) == "true" and panes()["center"] == "keys", f"Ctrl+/ from the agent's pane: the keys ({panes()})")
        p.call("pageKey", KEY_SLASH, CTRL)
        check(p.wait(lambda: panes()["center"] == "note" and panes()["here"] == "right", 2),
              f"…closed, the keys go back to the pane they came from ({panes()})")
        p.call("closePanes")

        # 14b. the overlay, on purpose only: it covers the screen and takes
        # the keyboard while it is up, so it runs with --overlay (a few
        # seconds). Its geometry is also checked offscreen (tst_layout).
        if "--overlay" in sys.argv:
            p.call("closeAll")
            p.call("summon", "{}")
            check(p.wait(lambda: shape()["overlay"] and shape()["ready"]), f"{{}} brings the overlay up ({shape()})")
            time.sleep(0.5)
            lay = json.loads(p.call("layout"))
            check(71.5 <= lay["chars"] <= 72.5 and lay["x"] > 0, f"the overlay's note holds 72 characters, centred ({lay})")
            p.call("pageKey", KEY_1, CTRL)
            p.call("pageKey", KEY_3, CTRL)
            check(p.wait(against, 2), f"…the panes inside its margin, the note between them ({p.call('sides')})")
            p.call("closePanes")
            check(p.call("pageKey", KEY_F11, 0) == "true" and p.wait(lambda: shape()["window"] and not shape()["overlay"], 3),
                  f"F11: from the overlay to the window ({shape()})")
            p.call("pageKey", KEY_F11, 0)
            check(p.wait(lambda: shape()["overlay"] and not shape()["window"], 3), f"…F11 again: the overlay, the window closed ({shape()})")
            p.call("summon", '{"shape":"alongside"}')
            check(p.wait(lambda: shape()["window"] and not shape()["overlay"], 3),
                  f"the window asked for takes the sheet back from the overlay ({shape()})")
            p.call("summon", "{}")
            p.wait(lambda: shape()["overlay"], 3)
            check(p.call("pageKey", KEY_ESC, 0) == "true" and p.wait(lambda: not shape()["overlay"], 3),
                  f"Esc in the note closes the overlay ({shape()})")
            check(shape()["window"], "…and the window under it stays")
        else:
            print("skip the overlay: python3 tests/page/run.py --overlay")

        # 15. coming back where you left (docs/navigation.md, "Checkpoints"):
        # a pane closing gives the keys back to the pane they came from, at
        # its checkpoint — the note's cursor at the same letter — or to the
        # middle when that pane has closed since; and Esc out of a task's
        # conversation goes to the day's, when it is open (the Esc rule, 2).
        KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_PGDN = 0x01000001, 0x01000013, 0x01000015, 0x01000012, 0x01000014, 0x01000017
        def note_focus():
            return json.loads(p.call("noteFocus"))
        p.call("closeAll")
        for old in p.daily.glob("*.md"):
            old.unlink()
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "The morning, in long sentences.\n\n- [ ] write the intro ⏫\n")
        (p.daily / f"{YDAY}.md").write_text(header(YDAY) + "yesterday's words\n")
        p.open_fresh()
        p.call("closePanes")
        morning = p.line_of("The morning")
        at = p.offset_of_line(morning) + len("The morn")
        p.call("cursor", at)
        check(p.wait(lambda: note_focus() == {"row": morning, "at": at, "active": True}, 2), f"the cursor in a line, mid-word ({note_focus()})")
        p.call("dive")
        check(p.wait(lambda: panes()["right"] == "margin" and panes()["here"] == "right", 2), f"the block's conversation, with the keys ({panes()})")
        p.call("back")
        check(p.wait(lambda: panes()["here"] == "center" and note_focus() == {"row": morning, "at": at, "active": True}, 2),
              f"Esc there: the keys back in the note, the cursor at the same letter ({panes()}, {note_focus()})")
        p.call("pageKey", KEY_1, CTRL)
        check(p.call("sideKey", KEY_3, CTRL) == "true" and p.wait(lambda: panes()["here"] == "right" and panes()["right"] == "day", 2),
              f"Ctrl+3 from the sidebar: the day's chat ({panes()})")
        p.call("dayKey", KEY_ESC, 0)
        check(p.wait(lambda: panes()["panes"] == ["left", "center"] and panes()["here"] == "left", 2),
              f"…Esc: the keys back to the sidebar they came from ({panes()})")
        p.call("sideKey", KEY_3, CTRL)
        p.wait(lambda: panes()["here"] == "right", 2)
        p.call("sidebar")                          # closed under the keys, as a click on the date does
        check(panes()["panes"] == ["center", "right"] and panes()["here"] == "right", f"the sidebar closed, the keys still on the right ({panes()})")
        p.call("dayKey", KEY_ESC, 0)
        check(p.wait(lambda: panes()["panes"] == ["center"] and panes()["here"] == "center"
                     and note_focus() == {"row": morning, "at": at, "active": True}, 2),
              f"…Esc: the pane they came from has gone, so the keys go to the middle, the cursor where it was ({panes()}, {note_focus()})")
        p.resize(701, 850)

        p.call("dash")
        p.call("dashKey", KEY_3, CTRL)
        p.call("dashKey", KEY_2, CTRL)
        check(p.wait(lambda: panes()["center"] == "dash" and panes()["right"] == "day" and panes()["here"] == "center", 2),
              f"the dashboard, the day beside it, the keys on the rows ({panes()})")
        p.wait(lambda: any(r.get("text") == "write the intro" for r in json.loads(p.call("dashRows"))), 8)   # the rows read, not raced
        p.call("dashFocus", next(n for n, r in enumerate(json.loads(p.call("dashRows"))) if r.get("text") == "write the intro"))
        check(p.call("dashKey", KEY_3, CTRL) == "true" and panes()["here"] == "right" and panes()["right"] == "day",
              f"Ctrl+3 from the dashboard: the keys to the day beside it ({panes()})")
        check(p.call("dayKey", KEY_3, CTRL) == "true" and p.wait(lambda: panes()["right"] == "talk", 2),
              f"…Ctrl+3 in it: the selected task's chat ({panes()})")
        # (The margin asks the page's global keys first, as every place does;
        # the harness's talkKey is only the margin's own.)
        check(p.call("pageKey", KEY_3, CTRL) == "true" and p.wait(lambda: panes()["right"] == "day", 2),
              f"…and again: the day's ({panes()})")
        p.call("pageKey", KEY_2, CTRL)
        check(p.wait(lambda: panes()["here"] == "center" and panes()["center"] == "dash", 2),
              f"Ctrl+2: back on the rows ({panes()})")
        check(p.call("dashKey", 0x43, 0) == "true" and p.wait(lambda: panes()["right"] == "talk" and panes()["here"] == "right", 2),
              f"C on a task: its chat in the day's place ({panes()})")
        check(p.call("talkKey", KEY_ESC, 0) == "true" and p.wait(lambda: panes()["right"] == "day" and panes()["here"] == "right", 2),
              f"…Esc: back to the day's conversation, the pane's home, with the keys ({panes()})")
        p.call("dayKey", KEY_ESC, 0)
        check(p.wait(lambda: panes()["panes"] == ["center"] and panes()["center"] == "dash" and p.call("dashFocused") == "true", 2),
              f"…and Esc again closes the pane, the keys back on the dashboard ({panes()})")
        check(p.call("dashKey", KEY_RETURN, CTRL) == "true" and p.wait(lambda: panes()["right"] == "talk", 2)
              and not any("- [x] write the intro" in f.read_text() for f in p.daily.glob("*.md")),
              f"Ctrl+Enter on a task: the same chat, and not done ({panes()})")
        p.call("talkKey", KEY_ESC, 0)
        p.wait(lambda: panes()["panes"] == ["center"], 2)
        check(p.call("dashKey", KEY_RETURN, CTRL | SHIFT) == "true" and p.wait(lambda: panes()["right"] == "day", 2),
              f"Ctrl+Shift+Enter on the dashboard: the day's chat ({panes()})")
        p.call("dayKey", KEY_ESC, 0)
        p.wait(lambda: panes()["panes"] == ["center"], 2)

        # Cancelled rows stay on the dashboard until tomorrow, as done ones
        # do (docs/tasks.md, rule 5): one cancelled today is listed, one
        # cancelled yesterday is not — and is still in the store, as history.
        cid = int(re.search(r"#(\d+)", p.pomo("add", "cancelled this morning", "2030-02-01")).group(1))
        yid = int(re.search(r"#(\d+)", p.pomo("add", "cancelled yesterday", "2030-02-02")).group(1))
        p.pomo("cancel", str(cid))
        p.pomo("cancel", str(yid))
        noon = int(dt.datetime.combine(dt.date.today() - dt.timedelta(days=1), dt.time(12)).timestamp())
        p.store.write_text("".join(
            "\t".join(f[:4] + [str(noon)] + f[5:]) + "\n" if int(f[0]) == yid else "\t".join(f) + "\n"
            for f in (l.split("\t") for l in p.store.read_text().splitlines())))
        p.call("dash")
        p.call("dash")
        def deadline_rows():
            return {r["text"]: r["status"] for r in json.loads(p.call("dashRows")) if r["kind"] == "deadline"}
        check(p.wait(lambda: deadline_rows().get("cancelled this morning") == "cancelled"),
              f"a deadline cancelled today keeps its row on the dashboard ({deadline_rows()})")
        check("cancelled yesterday" not in deadline_rows() and p.deadline(yid)["status"] == "cancelled",
              f"…one cancelled yesterday is gone from it, and kept in the store ({deadline_rows()}, {p.deadline(yid)})")
        p.call("dash")

        # A past day's conversation is read, not talked in (docs/plan.md,
        # 0): the pane follows the note to yesterday, its turns shown, its
        # box read-only, and nothing sent from it.
        (p.vault / "agents" / "longhand" / "daily").mkdir(parents=True, exist_ok=True)
        (p.vault / "agents" / "longhand" / "daily" / f"{YDAY}.json").write_text(json.dumps(
            {"date": YDAY, "blocks": {}, "day": {"turns": [{"role": "student", "text": "what was yesterday for?"},
                                                         {"role": "agent", "text": "the outline"}]}}))
        p.call("openDay", YDAY)
        p.wait(lambda: "yesterday's words" in p.call("text"))
        p.call("pageKey", KEY_3, CTRL)
        check(p.wait(lambda: p.call("dayShown") == "true" and json.loads(p.call("dayTurns")) == ["student: what was yesterday for?", "agent: the outline"]),
              f"yesterday's note: the agent's pane shows yesterday's conversation ({p.call('dayTurns')})")
        check(p.call("dayReadOnly") == "true", "…its box read-only")
        sent = p.calls.read_text().count("start day")
        p.call("dayType", "can I still ask?")
        p.call("dayKey", KEY_RETURN, 0)
        time.sleep(1)
        check(p.calls.read_text().count("start day") == sent and len(json.loads(p.call("dayTurns"))) == 2,
              f"…and Enter there sends nothing ({p.call('dayTurns')})")
        p.call("dayType", "")
        p.call("openDay", TODAY)
        check(p.wait(lambda: p.call("dayReadOnly") == "false"), "back on today's note, the box takes words again")
        p.call("closePanes")

        # The calendar's keys (the sidebar): the arrows walk the days and
        # weeks, PgDn a month; Tab goes on to the day's deadlines, then the
        # projects, and Esc backs a list out to the calendar; Enter opens
        # the day; Esc on the calendar closes the sidebar.
        def side():
            return json.loads(p.call("sideFocus"))
        p.pomo("add", "the calendar's deadline", "2030-03-13")
        p.call("pageKey", KEY_1, CTRL)
        # (The sidebar comes back to the row it was left on, plan.md item
        # 19: out to the calendar first.)
        if side() != {"due": -1, "proj": -1}:
            p.call("sideKey", KEY_ESC, 0)
        p.call("calDay", 2030, 3, 12)
        steps = [(KEY_RIGHT, "2030-03-13"), (KEY_LEFT, "2030-03-12"), (KEY_DOWN, "2030-03-19"), (KEY_UP, "2030-03-12"), (KEY_PGDN, "2030-04-12")]
        walked = [(p.call("sideKey", k, 0), p.call("calAt")) for k, _ in steps]
        check(walked == [("true", d) for _, d in steps], f"→ ← ↓ ↑ and PgDn walk the calendar ({walked})")
        p.call("calDay", 2030, 3, 13)
        check(p.call("sideKey", KEY_TAB, 0) == "true" and side() == {"due": 0, "proj": -1} and panes()["here"] == "left",
              f"Tab on a day with a deadline: into its list ({side()})")
        check(p.call("sideKey", KEY_ESC, 0) == "true" and side() == {"due": -1, "proj": -1} and panes()["panes"] == ["left", "center"],
              f"…Esc backs out to the calendar, the sidebar open ({side()}, {panes()})")
        p.call("sideKey", KEY_TAB, 0)
        check(p.call("sideKey", KEY_TAB, 0) == "true" and side() == {"due": -1, "proj": 0}, f"Tab, Tab: on to the projects ({side()})")
        check(p.call("sideKey", KEY_ESC, 0) == "true" and side() == {"due": -1, "proj": -1} and panes()["panes"] == ["left", "center"],
              f"…Esc backs out to the calendar too ({side()}, {panes()})")
        p.call("calDay", 2030, 3, 14)
        check(p.call("sideKey", KEY_TAB, 0) == "true" and side() == {"due": -1, "proj": 0}, f"Tab on a day with none: straight to the projects ({side()})")
        check(p.call("sideKey", 0x3f, 0x02000000) == "true" and p.call("keysOpen") == "true", "? in the sidebar's lists shows the keys")
        p.call("keys")
        p.call("sideKey", KEY_ESC, 0)

        # Reaching a project (plan.md item 19, 2026-11-17): under the
        # calendar the lists are one walk — ↓ goes on from the day's
        # deadlines into the projects, ↑ back, stopping at the top; Tab and
        # Shift+Tab skip a list; Shift+Tab in the calendar lands on the
        # projects; Home and End.
        KEY_BACKTAB, KEY_HOME_, KEY_END_, KEY_7 = 0x01000002, 0x01000010, 0x01000011, 0x37
        walk = lambda: json.loads(p.call("sideWalk"))
        p.call("calDay", 2030, 3, 13)
        p.call("sideKey", KEY_TAB, 0)
        check(p.call("sideKey", KEY_DOWN, 0) == "true" and side() == {"due": -1, "proj": 0},
              f"↓ at the end of the day's deadlines goes on into the projects ({side()})")
        check(p.call("sideKey", KEY_UP, 0) == "true" and side() == {"due": 0, "proj": -1}, f"…↑ back into the deadlines ({side()})")
        check(p.call("sideKey", KEY_UP, 0) == "true" and side() == {"due": 0, "proj": -1} and p.call("calAt") == "2030-03-13",
              f"…and ↑ at the top stays, the calendar's day unmoved ({side()})")
        nproj = len(walk()["order"])
        check(p.call("sideKey", KEY_END_, 0) == "true" and side() == {"due": -1, "proj": nproj - 1}, f"End: the last project ({side()})")
        check(p.call("sideKey", KEY_HOME_, 0) == "true" and side() == {"due": 0, "proj": -1}, f"Home: the first row ({side()})")
        check(p.call("sideKey", KEY_TAB, 0) == "true" and side() == {"due": -1, "proj": 0}, f"Tab skips to the next list ({side()})")
        check(p.call("sideKey", KEY_BACKTAB, SHIFT) == "true" and side() == {"due": 0, "proj": -1}, f"Shift+Tab to the list before ({side()})")
        check(p.call("sideKey", KEY_BACKTAB, SHIFT) == "true" and side() == {"due": -1, "proj": -1}, f"…and before the first, the calendar ({side()})")
        check(p.call("sideKey", KEY_BACKTAB, SHIFT) == "true" and side() == {"due": -1, "proj": 0}, f"Shift+Tab in the calendar: straight to the projects ({side()})")
        p.call("sideKey", KEY_ESC, 0)
        # Type to go: `#` and the letters, Enter opens; the project used rises.
        # (The list read again first: a project made and taken away above
        # is still listed until the sidebar opens.)
        p.call("sidebar")
        p.call("sidebar")
        check(p.wait(lambda: len(walk()["order"]) == len(list(pd.glob("*.md")))), f"the projects read again ({walk()})")
        p.call("sideKey", KEY_ESC, 0) if walk()["list"] != "" else None
        order = walk()["order"]
        last = order[-1]
        p.call("sideType", "#" + last[:2])
        check(walk()["typing"] and walk()["list"] == "proj" and order[walk()["at"]] == last,
              f"# and the letters pick the project, from the calendar ({walk()})")
        p.call("sideKey", KEY_RETURN, 0)
        check(p.wait(lambda: walk()["open"] == last) and not walk()["typing"] and panes()["here"] == "left",
              f"…Enter opens it, the keys in it ({walk()})")
        p.call("sideKey", KEY_ESC, 0)                       # out of the project, onto its row
        p.call("sidebar")
        p.call("sidebar")
        check(p.wait(lambda: walk()["list"] == "proj" and walk()["order"][walk()["at"]] == last),
              f"the sidebar opened again comes back to the row it was left on ({walk()})")
        used_file = p.state / "longhand" / "projects-used.json"
        check(p.wait(lambda: used_file.exists() and last in json.loads(used_file.read_text())),
              "…its use kept, for the order (the most used first)")
        p.call("sideType", "#zzz")
        check(walk()["typing"] and walk()["order"][walk()["at"]] == last, f"letters nothing has keep the row ({walk()})")
        p.call("sideKey", KEY_ESC, 0)
        check(not walk()["typing"] and walk()["list"] == "proj", f"…Esc stops typing, where it was ({walk()})")
        # Letters alone, with no `#` (2026-11-22): from the calendar too.
        p.call("sideKey", KEY_ESC, 0)
        first = walk()["order"][0]
        p.call("sideType", first[:2])
        check(walk()["typing"] and walk()["list"] == "proj" and walk()["order"][walk()["at"]] == first,
              f"letters alone find the project, from the calendar ({walk()})")
        p.call("sideKey", KEY_ESC, 0)
        p.call("sideKey", KEY_ESC, 0)
        p.call("sideType", "qqz")
        p.call("sideKey", KEY_RETURN, 0)
        check(p.wait(lambda: p.call("addingProject") == "true" and p.call("sidebarProjectText") == "qqz") and not walk()["typing"],
              f"…Enter on letters nothing has asks for a new project, its name in ({walk()})")
        p.call("closeSidebarProject")
        p.call("keysToSidebar")
        p.call("sideKey", KEY_ESC, 0)
        # A key per project, from anywhere: Alt and its place.
        p.call("pageKey", KEY_1, CTRL)
        p.call("pageKey", KEY_2, CTRL)
        second = walk()["order"][1]
        check(p.call("pageKey", 0x32, ALT_) == "true" and p.wait(lambda: walk()["open"] == second and panes()["here"] == "left"),
              f"Alt+2 from the note: the second project open, the keys on it ({walk()}, {panes()})")
        check(p.call("pageKey", KEY_7 + 2, ALT_) == "true" and p.wait(lambda: p.call("hint").startswith("the sidebar lists")),
              f"…Alt+9 with fewer projects says so ({p.call('hint')!r})")
        p.call("sideKey", KEY_ESC, 0)
        p.call("sideKey", KEY_ESC, 0)
        # The switcher (Ctrl+O): from the middle, "#" and letters, Enter.
        p.call("pageKey", KEY_2, CTRL)
        sw = lambda: json.loads(p.call("switcher"))
        check(p.call("pageKey", 0x4f, CTRL) == "true" and sw()["open"] and sw()["matches"] == walk()["order"],
              f"Ctrl+O opens the switcher on every project ({sw()})")
        p.call("switcherType", "#" + second[:2])
        check(sw()["matches"][0] == second, f"…typing narrows it ({sw()})")
        check(p.call("switcherKey", KEY_ESC, 0) == "true" and not sw()["open"] and panes()["here"] == "center",
              f"…Esc closes it, the keys back in the middle ({sw()}, {panes()})")
        p.call("pageKey", 0x4f, CTRL)
        p.call("switcherType", second)
        check(p.call("switcherKey", KEY_RETURN, 0) == "true" and p.wait(lambda: walk()["open"] == second and not sw()["open"]),
              f"…Enter opens the project in the sidebar ({walk()}, {sw()})")
        p.call("sideKey", KEY_ESC, 0)
        p.call("sideKey", KEY_ESC, 0)
        # (Not whether a line of the note has the keys: a note shorter than
        # the line the cursor was on drops them, 2026-10-25, a bug of its own.)
        y = dt.date.today() - dt.timedelta(days=1)
        p.call("calDay", y.year, y.month, y.day)
        check(p.call("sideKey", KEY_RETURN, 0) == "true" and p.wait(lambda: "yesterday's words" in p.call("text") and panes()["here"] == "center"),
              f"Enter opens the day in the sheet, the keys in the middle ({panes()}, {note_focus()})")
        p.call("pageKey", KEY_1, CTRL)
        check(panes()["here"] == "left", "Ctrl+1: back in the sidebar")
        check(p.call("sideKey", KEY_ESC, 0) == "true" and p.wait(lambda: panes()["panes"] == ["center"] and panes()["here"] == "center", 2),
              f"Esc on the calendar closes the sidebar, the keys back in the middle ({panes()})")
        p.call("openDay", TODAY)

        # 12h. the sidebar's spaces and the Files space (docs/files.md,
        # 2026-10-26): Ctrl+1, and again in it, goes to Files; folders open as they are asked
        # for, hidden ones never listed; a file opens in the sheet, editable
        # and with no day's machinery; the agent's files read only; Ctrl+H
        # is home; a fresh open lands on Time.
        print("-- spaces and files")
        KEY_RIGHT, KEY_SLASH = 0x01000014, 0x2f
        course = p.vault / "Studies" / "Course A"
        course.mkdir(parents=True)
        (course / "Session 1.md").write_text("# Session 1\n\nNotes from the first session.\n")
        (p.vault / "_Attachments").mkdir()
        (p.vault / "_Attachments" / "hidden.md").write_text("never listed\n")
        kept = p.vault / "agents" / "longhand" / "knowledge"
        kept.mkdir(parents=True, exist_ok=True)
        (kept / "about-you.md").write_text("What the agent keeps.\n")
        fs = lambda: json.loads(p.call("files"))
        p.call("pageKey", KEY_1, CTRL)
        check(p.wait(lambda: fs()["open"] and fs()["here"] == "left" and fs()["space"] == "time"), f"Ctrl+1: the sidebar opens on Time ({fs()})")
        p.call("sideKey", KEY_1, CTRL)
        check(p.wait(lambda: fs()["space"] == "files" and fs()["open"] and fs()["here"] == "left"),
              f"…Ctrl+1 in it: Files, the keys in it ({fs()})")
        check(p.wait(lambda: "> Studies" in fs()["rows"]), f"…your notes' first level listed ({fs()['rows']})")
        rows = fs()["rows"]
        check(not any(r.endswith("Daily") or "_Attachments" in r or r.endswith("agents") for r in rows),
              "the daily folder, _ folders and the agent's root are not among yours")
        p.call("filesFocus", rows.index("> Studies"))
        p.call("filesKey", KEY_RIGHT, 0)
        check(p.wait(lambda: "> Course A" in fs()["rows"]), f"→ opens a folder in place ({fs()['rows']})")
        p.call("filesFocus", fs()["rows"].index("> Course A"))
        p.call("filesKey", KEY_RIGHT, 0)
        check(p.wait(lambda: "Session 1" in fs()["rows"]), "…and the one inside it")
        p.call("filesFocus", fs()["rows"].index("Session 1"))
        p.call("filesKey", KEY_RETURN, 0)
        check(p.wait(lambda: fs()["filePath"] == "Studies/Course A/Session 1.md" and fs()["here"] == "center"
                     and "Notes from the first session." in p.call("text")),
              f"Enter opens the file in the sheet, the keys in it ({fs()})")
        f = fs()
        check(not f["dayNote"] and not f["agentOn"] and not f["readOnly"] and f["label"] == "Session 1",
              f"…a file, not a day: no agent, yours to edit, named in the header ({f})")
        p.call("cursorEnd")
        p.call("type", " More.")
        check(p.wait(lambda: "Notes from the first session.\n More." in (course / "Session 1.md").read_text()),
              "what is typed in it is saved to it")
        check("More." not in p.note(), "…and not to the day")
        # A note's own conversation (step 3): asked about in the header, the
        # file lit as the keys go to the pane, answered beside it, never
        # written; Ctrl+Shift+Enter points at a part of it.
        nt = lambda: json.loads(p.call("noteTalk"))
        check(nt()["askable"] and not nt()["room"], f"a file can be asked about ({nt()})")
        p.call("blipReset")
        p.call("askNote")
        check(p.wait(lambda: nt()["room"] and nt()["shown"] and nt()["here"] == "right"),
              f"ask about this note: its own conversation opens beside it, the keys in it ({nt()})")
        check(p.wait(lambda: nt()["blip"] == "sheet"), f"…and the whole note lights as they go ({nt()})")
        before = (course / "Session 1.md").read_text()
        p.call("daySend", "what was the first session about?")
        check(p.wait(lambda: nt()["turns"] == 2 and any(t.startswith("agent: ") for t in json.loads(p.call("dayTurns"))), 15),
              f"…answered there, kept by the note's path ({nt()}, {p.call('dayTurns')})")
        check((course / "Session 1.md").read_text() == before, "…and the note is not written")
        # Helpful or not, as in the day's chat: Alt+- on the last answer,
        # kept on its turn of the note's conversation.
        import hashlib
        talk_file = p.vault / "agents" / "longhand" / "notes" / (hashlib.md5(b"Studies/Course A/Session 1.md").hexdigest()[:16] + ".json")
        note_rating = lambda: (json.loads(talk_file.read_text())["turns"][-1].get("rating") or {}).get("value") if talk_file.is_file() else None
        check(p.call("dayKey", 0x2d, 0x08000000) == "true" and p.wait(lambda: note_rating() == "down"),
              f"Alt+- says the note's last answer was not helpful, kept on its turn ({note_rating()})")
        p.call("dayKey", 0x2d, 0x08000000)
        check(p.wait(lambda: note_rating() is None), "…and again takes it back")
        p.call("dayKey", KEY_ESC, 0)
        check(p.wait(lambda: not nt()["shown"] and nt()["here"] == "center"), f"Esc closes it, the keys back in the note ({nt()})")
        p.call("cursor", p.call("text").index("Notes from") + 3)
        p.call("blipReset")
        p.call("pageKey", KEY_RETURN, CTRL | SHIFT)
        check(p.wait(lambda: nt()["room"] and nt()["shown"]) and p.call("dayBlockText") == "",
              f"Ctrl+Shift+Enter in a file: the note's chat, the whole of it ({nt()}, {p.call('dayBlockText')!r})")
        check(p.wait(lambda: nt()["blip"] == "sheet"), f"…and the whole note lights ({nt()})")
        p.call("dayKey", KEY_ESC, 0)
        p.call("pageKey", KEY_1, CTRL)
        p.call("filesKey", KEY_SLASH, 0)
        p.call("filesFilter", "session")
        check(p.wait(lambda: any(r.startswith("Session 1 @Studies/Course A") for r in fs()["rows"])),
              f"/ filters every note by name, its folder beside it ({fs()['rows']})")
        check(p.wait(lambda: not any("hidden" in r for r in fs()["rows"])) and (p.call("filesFilter", "hidden") or True)
              and p.wait(lambda: fs()["rows"] == []), "…never a hidden one")
        p.call("filesFilter", "")
        p.call("filesKey", KEY_ESC, 0)
        # How private looks (B · Paper): a private block sunk with a lock in
        # the gutter, the sheet itself sunk for a note marked private.
        (course / "Journal.md").write_text("Out loud.\n\n> [!private]\n> Only for me.\n\nOut loud again.\n")
        (course / "Locked.md").write_text("---\nagent: false\n---\nAll of it mine.\n")
        p.call("openFile", "Studies/Course A/Journal.md", "false")
        look = lambda: json.loads(p.call("privateLook"))
        check(p.wait(lambda: look() == {"sunk": False, "blocks": 1}), f"a private block is sunk, the sheet is not ({look()})")
        # Ctrl+P: the block the cursor is in, made private and back; the
        # cursor stays in its words; one undo takes it back.
        journal = course / "Journal.md"
        before = journal.read_text()
        p.call("cursor", p.call("text").index("Out loud again.") + 4)
        p.call("pageKey", 0x50, CTRL)                      # Ctrl+P
        # Two private blocks, only a blank line between: one sheet, one
        # lock (2026-11-13).
        check(p.wait(lambda: "> [!private]\n> Out loud again.\n" in journal.read_text() and look()["blocks"] == 1),
              f"Ctrl+P makes the block private, one sheet with the one above ({journal.read_text()!r}, {look()})")
        at = int(p.call("cursorAt"))
        check(p.call("text")[at - 4:at] == "Out ", f"…the cursor still in its words ({p.call('text')[at - 6:at + 6]!r})")
        p.call("pageKey", 0x50, CTRL)
        check(p.wait(lambda: journal.read_text() == before), f"again: not private, the note as it was ({journal.read_text()!r})")
        p.call("cursor", p.call("text").index("Only for me.") + 2)
        p.call("pageKey", 0x50, CTRL)
        check(p.wait(lambda: journal.read_text() == "Out loud.\n\nOnly for me.\n\nOut loud again.\n"),
              f"on a private block, Ctrl+P unwraps it ({journal.read_text()!r})")
        p.call("undo")
        check(p.wait(lambda: journal.read_text() == before), "…and one undo puts it back")
        # Backspace at the start of its first line does the same (2026-11-13):
        # taking that line's `> ` off used to leave the rest a quote of its
        # own, no longer private.
        p.call("cursor", p.call("text").index("Only for me."))
        p.call("lineKey", KEY_BACKSPACE, 0)
        check(p.wait(lambda: journal.read_text() == "Out loud.\n\nOnly for me.\n\nOut loud again.\n")
              and p.call("hint").startswith("not private"),
              f"Backspace on a private block's first line unwraps it, and says so ({journal.read_text()!r}, {p.call('hint')!r})")
        p.call("undo")
        check(p.wait(lambda: journal.read_text() == before), "…and one undo puts it back")
        p.call("openFile", "Studies/Course A/Locked.md", "false")
        check(p.wait(lambda: look()["sunk"]), f"a note marked private: the whole sheet is sunk ({look()})")
        # A box in a private block (2026-10-27): drawn as a box, never bound
        # to a deadline however dated, on the dashboard with a lock, and the
        # agent not offered on it.
        p.call("openDay", TODAY)
        p.wait(lambda: p.call("header").startswith(dt.date.today().strftime("%A")))
        p.call("cursorEnd")
        p.call("type", "\n\n> [!private]\n> - [ ] therapy appointment by friday 17:00")
        line = p.line_of("therapy appointment")
        check(json.loads(p.call("rowKinds"))[line] == "task", "a box in a private block is a box")
        p.call("cursor", 1)
        p.wait(lambda: "therapy" in p.note(), 5)            # on disk first, then a moment for a binding
        time.sleep(1.2)
        check("^d" not in ([l for l in p.note().split("\n") if "therapy" in l] or ["^d (not saved)"])[0],
              f"…left with a date at its end, it is not bound ({[l for l in p.note().split(chr(10)) if 'therapy' in l]})")
        p.call("cursor", p.offset_of_line(line) + 8)
        p.call("askNow")
        check(p.wait(lambda: p.call("hint").startswith("private: the agent sees nothing of this block"))
              and json.loads(p.call("panes"))["right"] != "margin" and p.call("ask") == "null",
              f"Ctrl+Enter in it: no chat opens, nothing is sent ({p.call('hint')!r})")
        p.call("cursor", 1)
        p.call("dash")
        trow = lambda: next((r for r in json.loads(p.call("dashRows")) if r.get("text", "").startswith("therapy")), None)
        check(p.wait(lambda: (trow() or {}).get("priv") is True, 8), f"…on the dashboard, marked private ({trow()})")
        p.call("dashFocus", next(n for n, r in enumerate(json.loads(p.call("dashRows"))) if r.get("text", "").startswith("therapy")))
        p.call("dashKey", 0x43, 0)
        check(p.wait(lambda: p.call("hint").startswith("private: the agent sees nothing of this box")) and not json.loads(p.call("noteTalk"))["shown"],
              f"…and talking about it with the agent is refused ({p.call('hint')!r})")
        p.call("dash")
        # A PDF (step 5): listed with your notes, opened in the note's place,
        # found in, closed with Esc back to the note.
        sys.path.insert(0, str(ROOT / "tests"))
        from test_documents import pdf as make_pdf
        make_pdf(course / "Reading.pdf", "Reflexive thematic analysis is a method.")
        p.call("openFile", "Studies/Course A/Reading.pdf", "false")
        pd = lambda: json.loads(p.call("pdf"))
        check(p.wait(lambda: pd()["shown"] and pd()["ready"] and pd()["pages"] == 1 and pd()["label"] == "Reading"),
              f"a PDF opens in the note's place, read and named ({pd()})")
        check(p.wait(lambda: pd()["here"] == "center"), "…the keys in it")
        p.call("pdfKey", 0x46, CTRL)                        # Ctrl+F
        p.call("pdfFind", "thematic")
        check(p.wait(lambda: pd()["finding"] and pd()["found"] >= 1), f"Ctrl+F finds in it ({pd()})")
        p.call("pdfFindKey", KEY_ESC, 0)
        check(p.wait(lambda: not pd()["finding"]), "Esc closes the find bar, the PDF stays")
        # Marks (plan.md, item 15): words selected, `m` keeps them in the
        # paper's reading note and draws them; clicked, `q` makes it a
        # question; `n` writes a note under it; `x` removes it.
        mk = lambda: json.loads(p.call("pdfMarks"))
        check(p.wait(lambda: mk()["dressed"] >= 1 and mk()["markable"] and mk()["read"]["marks"] == []),
              f"a PDF never marked has no marks, and its pages can take them ({mk()})")
        check(mk()["dragPans"] is False, "a mouse drag on it selects, never moves the pages")
        p.call("keysToSidebar")
        check(p.wait(lambda: pd()["here"] == "left"), f"(the keys in the sidebar, as after opening it from the Files tree: {pd()['here']})")
        check(p.call("pdfDrag", "0", "73", "69", "200", "69") == "true" and p.wait(lambda: mk()["selected"] != ""),
              f"a mouse dragged across words selects them ({mk()})")
        check(p.wait(lambda: pd()["here"] == "center"), f"…bring the keys to it, so m reaches them ({pd()['here']})")
        picked = mk()["selected"]
        p.call("pdfKey", 0x4D, 0)                           # m
        check(p.wait(lambda: len(mk()["read"]["marks"]) == 1 and mk()["drawn"] >= 1 and mk()["selected"] == ""),
              f"m keeps them as a highlight, drawn on the page, the selection let go ({mk()})")
        m1 = mk()["read"]["marks"][0]
        reading = p.vault / mk()["read"]["note"]
        check(m1["kind"] == "h" and m1["placed"] and reading.is_file() and f"> {m1['text']}" in reading.read_text()
              and "Reflexive" in m1["text"] and m1["text"] in " ".join(picked.split()),
              f"…in the paper's reading note, as its words ({m1}, {reading})")
        check(mk()["lastMade"] == m1["id"], "…and it is the last one made")
        # Its project (plan.md item 15, step 1): nothing makes it plain (no
        # line it was followed from, no project's folder), so it is asked,
        # once; the choice goes into its reading note.
        ask = lambda: json.loads(p.call("pdfAsk"))
        check(p.wait(lambda: ask()["asking"] and len(ask()["choices"]) > 0),
              f"the paper's first mark asks which project it is for ({ask()})")
        first_tag = ask()["choices"][0]
        p.call("pdfChooseProject", first_tag)
        check(p.wait(lambda: ask()["tags"] == [first_tag] and f"#{first_tag}" in reading.read_text() and not ask()["asking"]),
              f"…chosen, the project's tag is kept in its reading note ({ask()})")
        # …and the project lists it among its papers.
        ppx = lambda: json.loads(p.call("projectPapers"))
        p.call("openProject", next(n for n, x in enumerate(json.loads(p.call("projects"))) if x.startswith(first_tag + "|")))
        check(p.wait(lambda: ppx()["open"] and "Reading" in ppx()["papers"]), f"the project's view lists the paper ({ppx()})")
        p.call("leaveProject")
        if p.call("sidebarOpen") == "true":
            p.call("sidebar")
        if p.call("sidebarOpen") == "true":
            p.call("sidebar")
        r = m1["boxes"][0]["rects"][0]
        p.call("pdfClick", "0", str(r[0] + r[2] / 2), str(r[1] + r[3] / 2))
        check(p.wait(lambda: mk()["picked"] == m1["id"]), f"a click on the mark picks it ({mk()['picked']!r})")
        p.call("pdfKey", 0x51, 0)                           # q
        check(p.wait(lambda: mk()["read"]["marks"][0]["kind"] == "q" and "> [!question]" in reading.read_text()),
              f"clicked, q makes it a question ({mk()})")
        p.call("pdfKey", 0x4E, 0)                           # n
        check(p.wait(lambda: mk()["noting"]), "n opens a line for a note under it")
        p.call("pdfWriteNote", "the method, in one line")
        check(p.wait(lambda: mk()["read"]["marks"][0]["note"] == "the method, in one line" and not mk()["noting"]
                     and "the method, in one line" in reading.read_text()),
              f"…and Enter writes it under the quote ({mk()})")
        check(mk()["picked"] == m1["id"], "…which stays picked")
        p.call("pdfKey", KEY_ESC, 0)
        check(p.wait(lambda: mk()["picked"] == "") and pd()["shown"], "Esc lets go of the mark clicked, and the PDF stays")
        p.call("pdfClick", "0", str(r[0] + r[2] / 2), str(r[1] + r[3] / 2))
        p.wait(lambda: mk()["picked"] == m1["id"])
        p.call("pdfClick", "0", str(r[0] + r[2] / 2), str(r[1] + r[3] + 120))
        check(p.wait(lambda: mk()["picked"] == "") and pd()["shown"], f"…as does a click on the page away from it ({mk()['picked']!r})")
        p.call("pdfPick", m1["id"])
        p.call("pdfKey", 0x58, 0)                           # x
        check(p.wait(lambda: mk()["read"]["marks"] == [] and mk()["drawn"] == 0 and m1["id"] not in reading.read_text()
                     and "the method, in one line" not in reading.read_text()),
              f"x removes it, with its note, from the page and the note ({mk()})")
        # The paper's room (plan.md item 15, step 2): beside the PDF, one
        # chat for the paper and its marks as a list. A question marked opens
        # the chat with it attached, nothing sent until Enter; Esc turns the
        # pane to the list; quotes in an answer show their words.
        pr = lambda: json.loads(p.call("paper"))
        p.call("pdfDrag", "0", "73", "69", "115", "69")
        p.wait(lambda: mk()["selected"] != "")
        p.call("pdfKey", 0x4D, 0)                           # m
        p.wait(lambda: len(mk()["read"]["marks"]) == 1)
        hid = mk()["read"]["marks"][0]["id"]
        p.call("pdfDrag", "0", "160", "69", "250", "69")
        p.wait(lambda: mk()["selected"] != "")
        p.call("pdfKey", 0x51, 0)                           # q
        check(p.wait(lambda: len(mk()["read"]["marks"]) == 2 and pr()["room"] and not pr()["list"] and len(pr()["marks"]) == 1
                     and pr()["here"] == "right"),
              f"q marks a question and opens the paper's chat with it attached, the keys in its box ({pr()})")
        qid = pr()["marks"][0]
        check(json.loads(p.call("dayTurns")) == [] and pr()["waiting"] == [qid], "…nothing sent: the question waits for its words")
        p.call("dayType", "what does this mean here?")
        p.call("dayKey", KEY_RETURN, 0)
        check(p.wait(lambda: qid in pr()["answered"] and pr()["waiting"] == [], 20),
              f"Enter asks it; answered, it waits no more ({pr()}, {p.call('dayTurns')})")
        paper_talk = p.vault / "agents" / "longhand" / "notes" / (hashlib.md5(b"Studies/Course A/Reading.pdf").hexdigest()[:16] + ".json")
        check(paper_talk.is_file() and json.loads(paper_talk.read_text())["turns"][-2].get("marks") == [qid],
              "…kept as the paper's conversation, the message pointing at the mark")
        check(pr()["marks"] == [], "…and the box lets go of it once sent")
        p.wait(lambda: p.call("agentBusy", "day") == "false", 5)    # Esc while it runs stops it (as above)
        p.call("dayKey", KEY_ESC, 0)
        check(p.wait(lambda: pr()["list"] and pr()["here"] == "right" and sorted(pr()["rows"]) == sorted([hid, qid])),
              f"Esc in the chat turns the pane to the marks ({pr()})")
        # A question hovered in the PDF shows its answer; Enter opens the
        # chat at that exchange, lit (2026-11-16). A highlight with no note
        # has nothing to say.
        ac = lambda: json.loads(p.call("pdfAcronyms"))
        # The pointer left where the test puts it: following the selection
        # it would move off the mark hovered.
        p.call("setPointer", "off")

        def rest_on_mark(mid, tip=True):
            m = next(x for x in mk()["read"]["marks"] if x["id"] == mid)
            r = m["boxes"][0]["rects"][0]
            for _ in range(6):
                p.call("pdfHover", "0", "300", "600")
                p.wait(lambda: ac()["mark"] == "", 2)
                p.call("pdfHover", "0", str(r[0] + r[2] / 2), str(r[1] + r[3] / 2))
                if p.wait(lambda: ac()["mark"] == mid and (ac()["tip"] or not tip), 2):
                    return True
            return False
        check(rest_on_mark(qid) and "opens it in the paper's chat" in ac()["says"]
              and ac()["says"].startswith("you asked: “what does this mean here?” | "),
              f"a question hovered shows what was asked, and its answer ({ac()['mark']!r}, {ac()['says']!r})")
        asked_at = next(n for n, t in enumerate(json.loads(p.call("dayTurns"))) if t.startswith("student: what does this mean"))
        p.call("pdfKey", KEY_RETURN, 0)
        check(p.wait(lambda: not pr()["list"] and pr()["pin"] == asked_at and pr()["lit"] == asked_at),
              f"…Enter opens the chat at that exchange, lit ({pr()}, asked at turn {asked_at})")
        # At 701 px a paper and its chat show one at a time (2026-11-22,
        # docs/navigation.md): the chat, keys in it, covers the paper, so the
        # keys go back to the paper before the mouse rests on it.
        p.call("pageKey", KEY_2, CTRL)
        p.call("pdfHover", "0", "300", "600")
        p.wait(lambda: ac()["mark"] == "", 2)
        rest_on_mark(hid, tip=False)
        p.wait(lambda: ac()["tip"], 1)
        check(ac()["mark"] == hid and not ac()["tip"], f"a highlight with no note shows no tip ({ac()['says']!r})")
        turns_before = len(json.loads(p.call("dayTurns")))
        p.call("pdfKey", KEY_RETURN, 0)
        check(p.wait(lambda: not pr()["list"] and pr()["marks"] == [hid])
              and len(json.loads(p.call("dayTurns"))) == turns_before,
              f"…Enter on it opens the paper's chat with it attached, nothing sent ({pr()})")
        p.call("pdfHover", "0", "300", "600")
        p.call("setPointer", "every")
        p.call("dayKey", KEY_ESC, 0)
        p.wait(lambda: pr()["list"])
        p.call("paperKey", 0x33, 0)                         # 3
        check(p.wait(lambda: pr()["filter"] == "q" and pr()["rows"] == [qid]), "3: only the questions")
        p.call("paperKey", 0x31, 0)                         # 1
        check(p.wait(lambda: pr()["focus"] == -1), "the first row is the paper as a whole")
        p.call("paperKey", KEY_RETURN, 0)
        check(p.wait(lambda: not pr()["list"] and pr()["marks"] == [] and pr()["here"] == "right"),
              f"Enter on it: the chat, nothing attached, to ask about the paper as a whole ({pr()})")
        p.call("dayKey", KEY_ESC, 0)
        p.wait(lambda: pr()["list"])
        p.call("paperKey", KEY_DOWN, 0)
        p.call("paperKey", KEY_DOWN, 0)
        check(p.wait(lambda: pr()["focus"] == 1 and pr()["picked"] == pr()["rows"][1]), f"↓: the marks below it, each picked in the PDF too ({pr()})")
        p.call("paperKey", KEY_RETURN, 0)
        check(p.wait(lambda: not pr()["list"] and pr()["marks"] == [pr()["rows"][1]]), f"Enter: the chat, that mark attached ({pr()})")
        p.call("dayKey", 0x01000003, 0)                     # Backspace in the empty box
        check(p.wait(lambda: pr()["marks"] == []), "Backspace in the empty box lets go of it")
        p.call("dayKey", KEY_ESC, 0)
        p.call("paperKey", KEY_RETURN, CTRL)
        check(p.wait(lambda: "no question is waiting" in pr()["hint"]), f"Ctrl+Enter with none waiting says so ({pr()['hint']!r})")
        # Another paper pointed at with `@` (2026-11-19, the student: "@ a
        # different paper so I can mention it to the agent"): offered from
        # the paper's own chat, a chip beside its marks, sent with the
        # message; a quote of it opens it there.
        make_pdf(course / "Other 2026.pdf", "Stress hotspots on the commute.")
        # One named by its key is shown as its bibliography has it (2026-11-19,
        # the student: "the meaningful names instead of the file names").
        make_pdf(course / "lee2020two.pdf", "Two riders, one road.")
        (course / "refs.bib").write_text('@article{lee2020two, author = {Lee, Ann and Park, Bo}, title = {Two of Us}, year = {2020}}\n')
        # The test vault's papers are in `Studies/`, which the agent does not
        # see unless switched on (search's default is `human/Studies`):
        # switched on for this part, as Settings → what the agent may search.
        sj = p.tmp / "config" / "longhand" / "settings.json"
        kept_settings = sj.read_text() if sj.exists() else None
        sset = json.loads(kept_settings) if kept_settings else {}
        sset.setdefault("searchFolders", {})["Studies"] = True
        sj.parent.mkdir(parents=True, exist_ok=True)
        sj.write_text(json.dumps(sset))
        p.call("paperKey", KEY_TAB, 0)
        p.wait(lambda: not pr()["list"])
        p.call("dayType", "@lee")
        check(p.wait(lambda: json.loads(p.call("dayMention")) == ["paper · Lee and Park 2020 · Two of Us"], 10),
              f"@ names a paper by its bibliography, its title beside it ({p.call('dayMention')})")
        p.call("dayType", "@Other")
        check(p.wait(lambda: json.loads(p.call("dayMention")) == ["paper · Other 2026"], 10),
              f"@ in a paper's chat offers the other papers, this one left out ({p.call('dayMention')})")
        check(p.call("dayKey", KEY_ENTER, 0) == "true"
              and p.wait(lambda: [(r["kind"], r["head"]) for r in json.loads(p.call("dayRefs"))] == [("paper", "Other 2026")]),
              f"…Enter makes it a chip ({p.call('dayRefs')})")
        # …and its name stays in the sentence, in the link's colour, tied to
        # the chip (2026-11-19, the student: "if I press backspace on the
        # name, the pill also disappears … so I can @ again").
        refs_heads = lambda: [r["head"] for r in json.loads(p.call("dayRefs"))]
        check(p.call("dayFieldText") == "Other 2026 " and json.loads(p.call("dayNames")) == ["Other 2026"]
              and ">Other 2026</span>" in p.call("dayDrawn"),
              f"…its name stays in the sentence, drawn as a link ({p.call('dayFieldText')!r}, {p.call('dayDrawn')!r})")
        p.call("dayInsert", "agree?")
        p.call("dayBackspace")
        check(p.call("dayFieldText") == "Other 2026 agree" and json.loads(p.call("dayNames")) == ["Other 2026"],
              f"…writing on after it leaves it a name ({p.call('dayFieldText')!r})")
        p.call("dayCursorAt", len("Other 2026 "))
        p.call("dayBackspace")
        check(p.call("dayFieldText") == "@Other agree" and refs_heads() == []
              and p.wait(lambda: json.loads(p.call("dayMention")) == ["paper · Other 2026"], 10),
              f"…Backspace after it takes the name and its chip, and gives back the @ with the list ({p.call('dayFieldText')!r}, {refs_heads()})")
        check(p.call("dayKey", KEY_ENTER, 0) == "true" and p.call("dayFieldText") == "Other 2026 agree"
              and refs_heads() == ["Other 2026"] and json.loads(p.call("dayNames")) == ["Other 2026"],
              f"…picked again, name and chip are back, one space ({p.call('dayFieldText')!r})")
        p.call("dayCursorAt", 3)
        p.call("dayInsert", "x")
        check(p.call("dayFieldText") == "Othxer 2026 agree" and refs_heads() == [] and json.loads(p.call("dayNames")) == []
              and p.call("dayDrawn") == "",
              f"…an edit inside the name leaves it words, and the chip goes ({p.call('dayFieldText')!r}, {refs_heads()})")
        p.call("dayType", "@Other")
        p.wait(lambda: json.loads(p.call("dayMention")) == ["paper · Other 2026"], 10)
        p.call("dayKey", KEY_ENTER, 0)
        p.call("dayInsert", "and the commute")
        p.call("dayChipDrop", 0)
        check(p.call("dayFieldText") == "and the commute" and refs_heads() == [],
              f"…the chip's × takes its name out of the sentence too ({p.call('dayFieldText')!r})")
        p.call("dayType", "@Other")
        p.wait(lambda: json.loads(p.call("dayMention")) == ["paper · Other 2026"], 10)
        p.call("dayKey", KEY_ENTER, 0)
        p.wait(lambda: refs_heads() == ["Other 2026"])
        p.call("daySend", "does Other agree?")
        check(p.wait(lambda: json.loads(paper_talk.read_text())["turns"][-1]["role"] == "agent"
                     and json.loads(paper_talk.read_text())["turns"][-2].get("text") == "does Other agree?", 20),
              "…the message is answered in the paper's chat")
        asked_other = json.loads(paper_talk.read_text())["turns"][-2]
        check(asked_other.get("refs") == [{"file": "Studies/Course A/Other 2026.pdf", "kind": "paper", "head": "Other 2026"}]
              and json.loads(p.call("dayRefs")) == [],
              f"…the turn keeps the paper it pointed at, and the box lets go of it ({asked_other.get('refs')})")
        links = p.call("paperLinks", "It says “Stress hotspots on the commute” (`Studies/Course A/Other 2026.pdf`, p. 1).")
        check("[“Stress hotspots on the commute” (Other 2026, p. 1)](pquote:1:" in links and "cite:" not in links,
              f"a quote of the other paper is one link, by its name and page ({links})")
        links2 = p.call("paperLinks", "“Two riders, one road” (`Studies/Course A/lee2020two.pdf`, p. 1)")
        check("(Lee and Park 2020, p. 1)](pquote:1:" in links2, f"…by the name @ gave it ({links2})")
        p.call("openLink", re.search(r"\((pquote:[^)]+)\)", links).group(1))
        check(p.wait(lambda: pd()["label"] == "Other 2026" and pr()["flash"] > 0, 10),
              f"…opened, that paper shows, its words lit ({pd()['label']}, {pr()})")
        p.call("openFile", "Studies/Course A/Reading.pdf", "false")
        p.wait(lambda: pd()["label"] == "Reading" and pd()["ready"])
        p.call("pageKey", KEY_3, CTRL)
        check(p.wait(lambda: pr()["room"] and pr()["shown"]), f"…and back on the first paper, its room again ({pr()})")
        if not pr()["list"]:
            p.call("dayKey", KEY_ESC, 0)
            p.wait(lambda: pr()["list"])
        if kept_settings is None:
            sj.unlink()
        else:
            sj.write_text(kept_settings)
        # The paper's marks are read again as it comes back: the keys wait
        # for its rows (a process of their own, later on Windows).
        p.wait(lambda: pr()["rows"])
        p.call("paperKey", KEY_DOWN, 0)                     # as it was before: a mark picked, from the list
        p.call("paperKey", KEY_DOWN, 0)
        check(p.wait(lambda: pr()["picked"] != ""), f"↓ in the paper's list picks a mark again ({pr()})")
        links = p.call("paperLinks", "It says “Reflexive thematic analysis” (p. 1), plainly.")
        check("](quote:1:" in links and "[“Reflexive thematic analysis” (p. 1)]" in links, f"a quote with its page is a link ({links})")
        links = p.call("paperLinks", "It says “stress (MOS) were found” (p. 1), plainly.")
        check(links.endswith("(quote:1:stress%20%28MOS%29%20were%20found), plainly."),
              f"…its own parentheses never close the link early ({links})")
        import urllib.parse
        p.call("openLink", "quote:1:" + urllib.parse.quote("Reflexive thematic analysis"))
        check(p.wait(lambda: pr()["flash"] > 0), f"…and opened, its words light where they are ({pr()})")
        p.call("openLink", "quote:1:" + urllib.parse.quote("words this paper never had"))
        check(p.wait(lambda: pr()["missed"] != ""), "…words that are not there are said to be missing")
        p.call("pageKey", KEY_3, CTRL)
        check(p.wait(lambda: not pr()["room"] and pr()["shown"]), f"Ctrl+3 in the paper's room: the day's chat ({pr()})")
        p.call("pageKey", KEY_3, CTRL)
        check(p.wait(lambda: pr()["room"] and pr()["shown"]), f"…and again: the paper's ({pr()})")
        p.call("paperKey", KEY_ESC, 0)
        check(p.wait(lambda: not pr()["shown"] and pd()["shown"]), "Esc on the marks closes the pane, the PDF stays")
        p.call("pdfKey", KEY_ESC, 0)
        check(p.wait(lambda: pr()["picked"] == "" and pd()["shown"]), "…and Esc in the PDF lets go of the mark picked first")
        # The agent's pane as the middle moves (2026-11-22, the student's
        # rule): closed, it stays closed; open, it follows the middle — a
        # paper's chat beside a paper, a note's beside a note, the day's
        # beside a day; one the agent may not be given has the day's; words
        # typed and not sent keep it where it is; going where the middle
        # already is changes nothing in it. Following never takes the keys.
        pn = lambda: json.loads(p.call("pane"))
        make_pdf(course / "Second.pdf", "Commuting and stress, read again.")
        make_pdf(course / "Blank.pdf", "")
        (p.vault / "Personal").mkdir(exist_ok=True)
        make_pdf(p.vault / "Personal" / "Statement.pdf", "Balance carried forward.")
        reading_rel, second_rel = "Studies/Course A/Reading.pdf", "Studies/Course A/Second.pdf"
        p.call("dayType", "")                               # the name left in the box above, which would hold the pane
        p.call("openFile", second_rel, "false")
        check(p.wait(lambda: pd()["label"] == "Second" and pn()["fits"] == "room") and not pn()["open"] and pn()["here"] == "center",
              f"the pane closed, a paper opened: it stays closed ({pn()})")
        p.call("pageKey", KEY_3, CTRL)
        p.wait(lambda: pn()["room"] and pn()["here"] == "right")
        p.call("pageKey", KEY_3, CTRL)                      # in it: the day's chat
        p.wait(lambda: pn()["shown"] and not pn()["room"])
        p.call("pageKey", KEY_2, CTRL)                      # the keys back to the paper
        p.wait(lambda: pn()["here"] == "center")
        p.call("openFile", reading_rel, "false")
        check(p.wait(lambda: pd()["label"] == "Reading" and pn()["paperRoom"] and pn()["about"] == reading_rel and pn()["shown"])
              and pn()["here"] == "center",
              f"open on the day's chat, a paper opened: that paper's chat, the keys left on the paper ({pn()})")
        p.call("openFile", "Studies/Course A/Blank.pdf", "false")
        check(p.wait(lambda: pd()["label"] == "Blank" and pn()["fits"] == "day" and pn()["shown"] and not pn()["room"]),
              f"a PDF with no words: the day's chat beside it, never its own ({pn()})")
        p.call("openFile", second_rel, "false")
        p.wait(lambda: pn()["paperRoom"] and pn()["about"] == second_rel)
        p.call("openFile", "Personal/Statement.pdf", "false")
        check(p.wait(lambda: pd()["label"] == "Statement" and pn()["fits"] == "day" and pn()["shown"] and not pn()["room"]),
              f"…from a paper's chat, a private PDF: the day's ({pn()})")
        p.call("openFile", second_rel, "false")
        check(p.wait(lambda: pn()["paperRoom"] and pn()["about"] == second_rel and pn()["shown"]),
              f"…and a paper again: its chat ({pn()})")
        # Back to the paper already in the middle, Ctrl+[ in the chat's box
        # (seen 2026-11-22: it went to the page's back, opened the same
        # paper again and closed the pane): the pane as it was.
        p.call("pageKey", KEY_3, CTRL)
        p.wait(lambda: pn()["here"] == "right")
        if pr()["list"]:
            p.call("paperKey", KEY_TAB, 0)
        p.wait(lambda: not pr()["list"] and pn()["here"] == "right")
        p.call("pageKey", KEY_2, ALT2)                      # Ctrl+Alt+2: the dashboard, a step
        p.wait(lambda: panes()["center"] == "dash")
        p.call("pageKey", KEY_3, CTRL)
        p.wait(lambda: pn()["here"] == "right")
        steps = pn()["back"]
        check(p.call("dayKey", 0x5b, CTRL) == "true"         # Ctrl+[
              and p.wait(lambda: panes()["center"] == "note" and pn()["back"] == steps - 1)
              and p.wait(lambda: pn()["paperRoom"] and pn()["about"] == second_rel and pn()["shown"] and not pr()["list"], 3),
              f"Ctrl+[ in a paper's chat, back to the same paper: the chat stays open, as it was ({pn()}, {panes()})")
        p.call("pageKey", KEY_3, CTRL)
        p.wait(lambda: pn()["here"] == "right")
        # Words in the box, not sent: nothing switched under the hand.
        p.call("dayType", "half a thought")
        p.call("openFile", reading_rel, "false")
        check(p.wait(lambda: pd()["label"] == "Reading" and pn()["fits"] == "room")
              and p.wait(lambda: pn()["room"] and pn()["about"] == second_rel and not pn()["paperRoom"]
                         and pn()["words"] == "half a thought", 3),
              f"words typed in the paper's chat, another paper opened: the chat stays the first paper's ({pn()})")
        p.call("openFile", second_rel, "false")
        check(p.wait(lambda: pn()["paperRoom"] and pn()["about"] == second_rel and pn()["words"] == "half a thought"),
              f"…back on that paper, it is its room again, the words kept ({pn()})")
        p.call("dayType", "")
        p.call("pageKey", KEY_3, CTRL)                      # the keys to the pane…
        p.wait(lambda: pn()["here"] == "right")
        p.call("pageKey", KEY_3, CTRL)                      # …and in it, the day's chat
        p.wait(lambda: pn()["shown"] and not pn()["room"])
        p.call("dayType", "about the day")
        p.call("openFile", reading_rel, "false")
        check(p.wait(lambda: pd()["label"] == "Reading" and pn()["fits"] == "room")
              and p.wait(lambda: pn()["shown"] and not pn()["room"] and pn()["words"] == "about the day", 3),
              f"…in the day's chat, a paper opened: still the day's ({pn()})")
        p.call("dayType", "")
        # Notes: a note from Files, its own chat; a note marked private and a
        # day, the day's chat. Closing the paper is a move too.
        p.call("openFile", "Studies/Course A/Session 1.md", "false")
        check(p.wait(lambda: pn()["room"] and pn()["about"] == "Studies/Course A/Session 1.md" and pn()["shown"]),
              f"open, a note from Files opened: the note's chat ({pn()})")
        p.call("openFile", "Studies/Course A/Locked.md", "false")
        check(p.wait(lambda: pn()["note"] == "Studies/Course A/Locked.md" and pn()["fits"] == "day" and pn()["shown"] and not pn()["room"]),
              f"…a note marked private: the day's ({pn()})")
        p.call("openFile", reading_rel, "false")
        p.wait(lambda: pn()["paperRoom"] and pn()["about"] == reading_rel)
        p.call("pageKey", KEY_2, CTRL)
        p.wait(lambda: pn()["here"] == "center")
        p.call("pdfKey", KEY_ESC, 0)                        # the paper closed: the note under it
        check(p.wait(lambda: not pd()["shown"] and pn()["fits"] in ("room", "day") and pn()["shown"] and pn()["follows"] is False)
              and (pn()["room"] == (pn()["fits"] == "room")),
              f"the paper closed, the pane open: it follows to the note under it ({pn()})")
        p.call("openDay", TODAY)
        check(p.wait(lambda: p.call("header").startswith(dt.date.today().strftime("%A")) and pn()["shown"] and not pn()["room"]),
              f"…a day: the day's chat ({pn()})")
        p.call("openFile", reading_rel, "false")
        p.wait(lambda: pn()["paperRoom"] and pn()["about"] == reading_rel)
        p.call("pageKey", KEY_BAR, CTRL)                    # closed, as before
        p.wait(lambda: not pn()["open"])
        p.call("pageKey", KEY_2, CTRL)
        p.wait(lambda: pd()["shown"] and pd()["here"] == "center")
        # Read today (plan.md item 15, step 3): the papers marked on the
        # calendar's day, under its deadlines; Enter opens one where it was
        # left. And a task linking a paper: Alt+Enter on its row opens it.
        p.call("pdfKey", KEY_ESC, 0)
        p.wait(lambda: not pd()["shown"])
        rt = lambda: json.loads(p.call("readToday"))
        p.call("keysToSidebar")
        check(p.wait(lambda: rt()["day"] == TODAY_ISO and "Reading · 1 highlight, 1 question" in rt()["rows"]),
              f"the sidebar's day lists the paper read that day, with its marks counted ({rt()})")
        for _ in range(3):
            if rt()["focus"] >= 0:
                break
            p.call("sideKey", 0x01000001, 0)                  # Tab
        check(rt()["focus"] == 0, f"Tab walks into it after the day's deadlines ({rt()})")
        p.call("sideKey", KEY_RETURN, 0)
        check(p.wait(lambda: pd()["shown"] and pd()["label"] == "Reading"), f"Enter opens it ({pd()['label']})")
        p.call("pdfKey", KEY_ESC, 0)
        p.wait(lambda: not pd()["shown"])
        if p.call("sidebarOpen") == "true":
            p.call("sidebar")
        today_note = p.daily / f"{TODAY}.md"
        kept_note = today_note.read_text()
        today_note.write_text(kept_note.rstrip("\n") + "\n- [ ] read [[Reading.pdf]] again\n")
        p.wait(lambda: "read [[Reading.pdf]] again" in p.call("text"))
        p.call("pageKey", KEY_2, CTRL)
        row = lambda: next((n for n, x in enumerate(json.loads(p.call("dashRows")))
                            if x.get("kind") == "task" and "again" in x.get("text", "")), -1)
        check(p.wait(lambda: row() >= 0, 10), "a task linking a paper is on the dashboard")
        p.call("dashFocus", str(row()))
        p.call("dashKey", KEY_RETURN, 0x08000000)              # Alt+Enter
        check(p.wait(lambda: pd()["shown"] and pd()["label"] == "Reading"),
              f"Alt+Enter on its row follows the link: the paper opens ({pd()['label']}, {p.call('hint')!r})")
        p.call("pdfKey", KEY_ESC, 0)
        p.wait(lambda: not pd()["shown"])
        today_note.write_text(kept_note)
        p.wait(lambda: "read [[Reading.pdf]] again" not in p.call("text"))
        if panes()["center"] != "note":
            p.call("pageKey", KEY_2, CTRL)
        p.wait(lambda: panes()["center"] == "note")
        p.call("pdfKey", KEY_ESC, 0)
        check(p.wait(lambda: not pd()["shown"] and pd()["label"] != "Reading" and json.loads(p.call("files"))["filePath"] == ""
                     and "therapy appointment" in p.call("text")),
              f"Esc closes it, back to the note under it ({pd()})")
        # A waiting question in the project's list opens its paper on that
        # mark, and the next one picked moves to its own mark while the
        # paper is still open (2026-11-19: that second pick did nothing).
        from test_read import pdf as lined_pdf
        lined_pdf(course / "Asked.pdf", [["Stress is a reaction to a real threat."] + ["filler line"] * 40
                                         + ["Cycling lanes lower it a great deal."]])
        asked = "Studies/Course A/Asked.pdf"
        for words in ("Stress is a reaction", "Cycling lanes lower it"):
            subprocess.run([str(ROOT / "cli" / "longhand-read"), "mark", "--pdf", asked, "--page", "1", "--text", words,
                            "--kind", "q", "--tag", first_tag], capture_output=True, text=True, env=p.env, check=True)
        side_was = p.call("sidebarOpen")
        p.call("openProject", next(n for n, x in enumerate(json.loads(p.call("projects"))) if x.startswith(first_tag + "|")))
        asks = lambda: [r.split("|", 1)[1] for r in prows() if r.startswith("question|") and asked in r]
        check(p.wait(lambda: len(asks()) == 2), f"the project lists the paper's two waiting questions ({prows()})")
        q1, q2 = asks()
        p.call("projectPick", q1)
        p.call("projectOpenRow")
        check(p.wait(lambda: pd()["shown"] and pd()["label"] == "Asked" and mk()["picked"] == q1.rsplit(":", 1)[1]),
              f"the first opens the paper on its mark ({pd()['label']}, {mk()['picked']!r})")
        p.call("projectPick", q2)
        p.call("projectOpenRow")
        check(p.wait(lambda: mk()["picked"] == q2.rsplit(":", 1)[1] and pd()["label"] == "Asked"),
              f"…and the second, the paper open, moves to its own ({mk()['picked']!r})")
        p.call("projectPick", q1)
        p.call("projectOpenRow")
        check(p.wait(lambda: mk()["picked"] == q1.rsplit(":", 1)[1]), f"…and back to the first ({mk()['picked']!r})")
        p.call("leaveProject")
        if p.call("sidebarOpen") != side_was:
            p.call("sidebar")
        p.call("pdfKey", KEY_ESC, 0)
        p.call("pdfKey", KEY_ESC, 0)
        p.wait(lambda: not pd()["shown"])
        # Acronyms (plan.md item 18): hovered, one says what it stands for;
        # Enter goes to where the paper spells it out, Ctrl+[ comes back; `a`
        # lists them; one never spelled out is asked in the paper's chat.
        from test_read import pdf as lined_pdf
        lined_pdf(course / "Acronyms.pdf", [
            ["We measured heart rate variability (HRV) on bikes."],
            ["Nothing on this page but words."],
            ["HRV fell as the GPU ran.", "Another GPU ran too."]])
        ac = lambda: json.loads(p.call("pdfAcronyms"))
        p.call("setPointer", "off")
        p.call("openFile", "Studies/Course A/Acronyms.pdf", "false")
        check(p.wait(lambda: pd()["settled"] and "HRV=heart rate variability" in ac()["list"] and "GPU=?" in ac()["list"]),
              f"a paper's acronyms are read on opening: spelled out, and never ({ac()})")
        p.call("pdfKey", 0x01000011, 0)                    # End
        p.wait(lambda: ac()["page"] == 2)

        def view_rests():
            # The view where it stays: the same place read three times over.
            seen = [None]
            def still():
                now = pd()["at"]
                rest, seen[0] = now == seen[0], now
                return rest
            return p.wait(lambda: still() and still())

        def rest_on(a):
            # The pointer resting on it, off it first, once the view rests:
            # End, Enter and Ctrl+[ glide for 400 ms, and a word the pointer
            # is put on meanwhile slides from under it, so the page lets go
            # of it (2026-11-24: put there 200 ms after End, the word still
            # 20 to 30 px short of its place, it was let go of 10 times in
            # 12, now and then just after its tip showed). Again if it was
            # let go of all the same.
            for _ in range(6):
                view_rests()
                # Not written on this page (the paper left, its acronyms
                # gone): said by the check, the rest of the run goes on.
                r = next((x["r"] for x in ac()["spots"][2] if x["a"] == a), None)
                if r is None:
                    return False
                p.call("pdfHover", "2", "300", "400")
                p.wait(lambda: ac()["hover"] == "", 2)
                p.call("pdfHover", "2", str(r[0] + r[2] / 2), str(r[1] + r[3] / 2))
                if p.wait(lambda: ac()["hover"] == a and ac()["tip"], 2):
                    return True
            return False
        check(rest_on("HRV"), f"hovered, HRV says what it stands for ({ac()})")
        read_at = pd()["at"]
        same = lambda a: a and a["page"] == read_at["page"] and abs(a["frac"] - read_at["frac"]) < 0.05
        # Enter while it is under the pointer (rested on again if the page
        # let go of it meanwhile: Enter on nothing goes nowhere, and every
        # check after it failed with it, 2026-11-24).
        went, seen = False, []
        for _ in range(3):
            if ac()["hover"] != "HRV" and not rest_on("HRV"):
                continue
            seen.append((ac()["hover"], ac()["tip"]))
            p.call("pdfKey", KEY_RETURN, 0)
            if p.wait(lambda: ac()["page"] == 0 and ac()["back"] and ac()["flash"] == 1 and not ac()["tip"]):
                went = True
                break
        check(went, f"Enter: to page 1, where it is spelled out, lit a moment (before Enter {seen}; {ac()})")
        p.call("pdfKey", KEY_LBRACKET, CTRL)
        check(p.wait(lambda: same(pd()["at"]) and not ac()["back"] and pd()["shown"]),
              f"Ctrl+[: back to where it was read, the PDF still open ({pd()['at']}, read at {read_at})")
        p.call("pdfKey", 0x41, 0)                           # a
        p.call("pdfAcroType", "heart")
        check(p.wait(lambda: ac()["listing"] and ac()["choices"] == ["HRV"]),
              f"a: the paper's acronyms, narrowed by the words they stand for ({ac()})")
        p.call("pdfAcroEnter")
        check(p.wait(lambda: not ac()["listing"] and ac()["page"] == 0 and ac()["back"]), f"…Enter goes to it ({ac()})")
        p.call("pdfKey", KEY_LBRACKET, CTRL)
        check(p.wait(lambda: same(pd()["at"])), f"…and back again ({pd()['at']})")
        check(rest_on("GPU"), f"one never spelled out is hovered too ({ac()})")
        # Enter while it is under the pointer (rested on again if the page
        # let go of it meanwhile; what it was is said if it never asks).
        asked, seen = False, []
        for _ in range(3):
            if ac()["hover"] != "GPU" and not rest_on("GPU"):
                continue
            seen.append((ac()["hover"], ac()["tip"]))
            p.call("pdfKey", KEY_RETURN, 0)
            if p.wait(lambda: pr()["room"] and "“GPU”" in p.call("dayTurns"), 20):
                asked = True
                break
        check(asked, f"…and Enter asks the paper's chat what it stands for, as a guess "
                     f"(before Enter {seen}; {pr()}; {p.call('dayTurns')[:200]})")
        p.call("setPointer", "every")
        p.call("dayKey", KEY_ESC, 0)
        p.wait(lambda: pr()["list"])
        p.call("paperKey", KEY_ESC, 0)
        p.wait(lambda: not pr()["shown"])
        p.call("pdfKey", KEY_ESC, 0)
        p.wait(lambda: not pd()["shown"])
        # It opens again where it was left (PdfPlaces.js, pdfs.json): the
        # last page of four, then nothing kept once back at the top.
        KEY_HOME, KEY_END = 0x01000010, 0x01000011
        make_pdf(course / "Long reading.pdf", "Chapter one.", pages=4)
        places = p.state / "longhand" / "pdfs.json"
        long_rel = "Studies/Course A/Long reading.pdf"
        p.call("openFile", long_rel, "false")
        check(p.wait(lambda: pd()["ready"] and pd()["settled"] and pd()["pages"] == 4 and pd()["resumed"] is None),
              f"a PDF never opened before opens at its top ({pd()})")
        y0 = float(p.call("pdfWheel", "0"))
        check(float(p.call("pdfWheel", "-240")) > y0 + 50, "a mouse wheel scrolls it, its dragging turned off")
        p.call("pdfKey", KEY_HOME, 0)
        # End: as far down as it goes. The last page is shorter than the
        # window, so the top of the view rests in the page before it.
        p.call("pdfKey", KEY_END, 0)
        check(p.wait(lambda: (pd()["at"] or {}).get("page", 0) >= 2), f"End: the foot of it ({pd()})")
        # Where it rests once the glide is over: read while still gliding,
        # it was a place it only passed (the check below failed now and
        # then, 2026-11-22).
        seen_at = [None]
        def at_rest():
            now = pd()["at"]
            rest, seen_at[0] = now == seen_at[0], now
            return rest
        p.wait(lambda: at_rest() and at_rest())
        left = pd()["at"]
        p.call("pdfKey", KEY_ESC, 0)
        check(p.wait(lambda: not pd()["shown"] and places.is_file()
                     and json.loads(places.read_text()).get(long_rel, {}).get("page") == left["page"]),
              f"closing it keeps its place in pdfs.json ({places.read_text() if places.is_file() else 'no file'})")
        p.call("openFile", long_rel, "false")
        check(p.wait(lambda: pd()["settled"] and (pd()["resumed"] or {}).get("page") == left["page"]
                     and (pd()["at"] or {}).get("page") == left["page"]
                     and abs((pd()["at"] or {}).get("frac", -1) - left["frac"]) < 0.05),
              f"opened again, it is back where it was left ({pd()}, left at {left})")
        p.call("pdfKey", KEY_HOME, 0)
        check(p.wait(lambda: (pd()["at"] or {}).get("page") == 0 and (pd()["at"] or {}).get("frac") == 0), f"Home: the top ({pd()})")
        p.call("pdfKey", KEY_ESC, 0)
        check(p.wait(lambda: not pd()["shown"] and places.is_file() and long_rel not in json.loads(places.read_text())),
              "left at its top, nothing is kept for it")
        # A jump lands on its page after the PDF is made larger far down
        # (2026-11-22: a quote on page 14, clicked, went to page 16, the
        # foot saying 14; the fit to the text after opening where it was
        # left did it). Both a page the view holds and one it does not.
        make_pdf(course / "Twenty pages.pdf", "Chapter one.", pages=20)
        p.call("openFile", "Studies/Course A/Twenty pages.pdf", "false")
        check(p.wait(lambda: pd()["ready"] and pd()["settled"] and pd()["pages"] == 20), f"a PDF of twenty pages ({pd()})")
        laid_at = lambda i: float(p.call("pdfLaidAt", i))
        p.call("pdfJump", 16, 100)
        check(p.wait(lambda: abs(laid_at(16) - 100) < 3), f"a jump to page 17 ({laid_at(16)}, {pd()['at']})")
        p.call("pdfPinch", "1.15")
        check(p.wait(lambda: abs(pd()["zoom"] - 1.15) < 0.01 and (pd()["at"] or {}).get("page") == 16),
              f"made larger there, still on page 17 ({pd()})")
        for page_index, y, said in ((15, 300, "the page before"), (13, 200, "two pages back"), (2, 150, "far back"),
                                    (13, 200, "far on again")):
            p.call("pdfJump", page_index, y)
            check(p.wait(lambda: abs(laid_at(page_index) - y) < 3 and (pd()["at"] or {}).get("page") == page_index),
                  f"…a jump to page {page_index + 1} ({said}) lands there, as the foot says "
                  f"({laid_at(page_index)} pt down it, wanted {y}; {pd()['at']})")
        # The view lays every page where the heights before it add up to, at
        # any size (Longhand's own view, 2026-11-22: Qt's guessed, and kept
        # stale places after a rescale far down).
        tops = lambda: json.loads(p.call("pdfTops"))
        check(tops()["worst"] < 0.5 and abs(tops()["height"] - tops()["want"]) < 0.5,
              f"every page is laid where the pages' heights put it ({tops()})")
        p.call("pdfKey", 0x2B, 0)                           # +
        check(p.wait(lambda: abs(pd()["zoom"] - 1.15 * 1.2) < 0.01) and tops()["worst"] < 0.5,
              f"…made larger again, still ({tops()})")
        # A pinch keeps the words under the fingers under them, each step of
        # the way, and nothing moves when they lift (Qt's scaled one page
        # alone, then laid them all out again and centred them a moment
        # later).
        fx, fy = pd()["width"] * 0.4, 260
        seen = json.loads(p.call("pdfPinchAt", "1.3", fx, fy))
        check(all(s["page"] == seen[0]["page"] and abs(s["x"] - seen[0]["x"]) < 0.5 and abs(s["y"] - seen[0]["y"]) < 0.5
                  for s in seen), f"a pinch: what is under the fingers stays under them ({seen[0]} → {seen[1:]})")
        time.sleep(0.6)
        lifted = json.loads(p.call("pdfUnder", fx, fy))
        check(lifted["page"] == seen[0]["page"] and abs(lifted["x"] - seen[0]["x"]) < 0.5 and abs(lifted["y"] - seen[0]["y"]) < 0.5
              and abs(pd()["zoom"] - 1.15 * 1.2 * 1.3) < 0.01,
              f"…and once they lift, nothing moves, the size taken as the zoom ({lifted}, zoom {pd()['zoom']:.3f})")
        seen = json.loads(p.call("pdfPinchAt", str(1 / 1.3), fx, 500))
        check(all(abs(s["y"] - seen[0]["y"]) < 0.5 for s in seen), f"…pinched smaller too ({seen[0]} → {seen[-1]})")
        check(tops()["worst"] < 0.5, f"…every page still where its height puts it ({tops()})")
        p.call("pdfKey", KEY_ESC, 0)
        p.wait(lambda: not pd()["shown"])
        # Ctrl+F (2026-11-17): every place the words are, loosely, listed;
        # Enter goes on from where it is read, Esc leaves the view there
        # and Ctrl+[ goes back. The page said in the foot follows the view.
        from test_read import pdf as lined_pdf
        lined_pdf(course / "Bikes.pdf", [["Stress on bikes", "Riders felt stress at the junc-", "tion near the bridge."],
                                        ["The bridge again: stress rose.", "Nothing else here."],
                                        ["A last stress, at the end.", "Coda."]])
        fd = lambda: json.loads(p.call("pdfFound"))
        p.call("openFile", "Studies/Course A/Bikes.pdf", "false")
        check(p.wait(lambda: pd()["settled"] and pd()["pages"] == 3 and fd()["page"] == 0), f"a paper of three pages, at its first ({fd()})")
        p.call("pdfKey", 0x46, CTRL)                        # Ctrl+F
        check(p.wait(lambda: fd()["finding"] and fd()["focus"]), f"Ctrl+F: the find bar, the keys in it ({fd()})")
        p.call("pdfFind", "stress")
        check(p.wait(lambda: fd()["total"] == 4 and fd()["at"] == 0 and fd()["count"] == "1 of 4"),
              f"typed, every place is found, any case, the first shown ({fd()})")
        for _ in range(2):
            p.call("pdfFindKey", KEY_RETURN, 0)
        check(p.wait(lambda: fd()["at"] == 2 and fd()["page"] == 1), f"Enter, Enter: the third, on page 2, the page said ({fd()})")
        p.call("pdfFindKey", KEY_RETURN, SHIFT)
        check(p.wait(lambda: fd()["at"] == 1), f"Shift+Enter: the one before ({fd()})")
        for _ in range(3):
            p.call("pdfFindKey", KEY_RETURN, 0)
        check(p.wait(lambda: fd()["at"] == 0 and "from the top" in fd()["said"]), f"past the last, from the top again ({fd()})")
        p.call("pdfFind", "junction")
        check(p.wait(lambda: fd()["for"] == "junction" and fd()["hits"] == ["0:junc-tion"]),
              f"a word a line broke with a hyphen is found ({fd()})")
        p.call("pdfFind", "Stress")
        check(p.wait(lambda: fd()["for"] == "Stress" and fd()["total"] == 1 and fd()["cased"] and "capitals count" in fd()["says"]),
              f"a capital typed: the case counts ({fd()})")
        p.call("pdfFind", "zebra")
        check(p.wait(lambda: fd()["for"] == "zebra" and fd()["count"] == "none" and "not in this paper" in fd()["says"]),
              f"nothing found says so ({fd()})")
        p.call("pdfFind", "bridge")
        check(p.wait(lambda: fd()["total"] == 2 and fd()["at"] == 0), f"…typed again, found again ({fd()})")
        p.call("pdfFindKey", KEY_RETURN, 0)
        check(p.wait(lambda: fd()["at"] == 1 and fd()["page"] == 1), f"Enter: the second, on page 2 ({fd()})")
        p.call("pdfFindKey", KEY_ESC, 0)
        check(p.wait(lambda: not fd()["finding"] and fd()["total"] == 0 and fd()["back"] is not None and fd()["page"] == 1),
              f"Esc: the bar goes, the view stays where it was found, the way back kept ({fd()})")
        p.call("pdfKey", KEY_LBRACKET, CTRL)
        check(p.wait(lambda: fd()["page"] == 0 and (fd()["here"] or {}).get("frac", 1) < 0.05 and fd()["back"] is None),
              f"Ctrl+[: back to where the reading was ({fd()})")
        p.call("pdfKey", KEY_END, 0)
        check(p.wait(lambda: fd()["page"] == 2), f"the page said follows the view, not Qt's last jump ({fd()})")
        p.call("pdfKey", 0x01000016, 0)                     # PgUp
        check(p.wait(lambda: fd()["page"] == 1), f"PgUp: the page before the one read ({fd()})")
        p.call("pdfKey", KEY_HOME, 0)
        p.call("pdfKey", KEY_ESC, 0)
        p.wait(lambda: not pd()["shown"])
        # Fitted by its text (plan.md item 15, 2026-11-15): a paper's
        # margins out of view, the text across the column; `0` switches to
        # the whole page and back.
        from test_read import pdf as lined_pdf
        lined_pdf(course / "Paper.pdf", [[f"line {i} of a paper set in the middle of its page" for i in range(30)]] * 2)
        p.call("openFile", "Studies/Course A/Paper.pdf", "false")
        # Its text runs from 72 pt to 294 of 612: about the page's middle
        # (306) the farther side is 234 pt, and 14 are kept beside it.
        want = lambda: (pd()["width"] / 2) / (306 - 72 + 14)
        check(p.wait(lambda: pd()["ready"] and pd()["settled"] and pd()["span"] is not None
                     and abs(pd()["scale"] - want()) < 0.01),
              f"a paper is fitted by its text, about the page's middle ({pd()})")
        fitted = pd()["scale"]
        # Centred as it stands: the view's column measured at this size, not
        # the one before (2026-11-19: the text's page, wider than the
        # column, stood against its left and its right side was cut).
        centred = lambda: (abs(pd()["cw"] - max(pd()["width"], pd()["pageW"])) < 30 and abs(pd()["x"] - pd()["centredX"]) < 2
                           and (pd()["whole"] or pd()["x"] > 20))
        check(p.wait(centred), f"…its page's middle in the column's middle, the text in view ({pd()})")
        p.call("pdfKey", 0x30, 0)                           # 0
        check(p.wait(lambda: pd()["whole"] and pd()["scale"] < fitted * 0.95),
              f"0: the whole page, smaller ({fitted:.2f} → {pd()['scale']:.2f})")
        check(p.wait(centred), f"…centred too ({pd()})")
        p.call("pdfKey", 0x30, 0)
        check(p.wait(lambda: not pd()["whole"] and abs(pd()["scale"] - fitted) < 0.01), "0 again: its text")
        check(p.wait(centred), f"…centred again ({pd()})")
        # A jump glides up or down only (2026-11-19): Qt's own jump slid the
        # page sideways to its left edge after it had been centred, its
        # right side cut off beside the chat.
        p.call("pdfKey", KEY_END, 0)
        seen, until = [], time.time() + 0.9
        while time.time() < until:
            d = pd()
            seen.append((round(d["x"], 1), round(d["centredX"], 1), d["at"]["page"], d["at"]["frac"]))
        check(p.wait(lambda: pd()["at"]["page"] == 1 and pd()["at"]["frac"] < 0.02), f"End: the last page's top ({pd()['at']})")
        check(any(pg == 0 and fr > 0.05 for _, _, pg, fr in seen), f"…glided to, not jumped ({seen[:8]})")
        check(all(abs(x - c) < 2 for x, c, _, _ in seen), f"…the page centred all the way ({seen[:8]})")
        p.call("pdfKey", KEY_HOME, 0)
        p.wait(lambda: pd()["at"]["page"] == 0 and pd()["at"]["frac"] < 0.02)
        # Ctrl and the wheel sizes it, as = and -; a pinch (Qt's own) is
        # taken as the zoom too, so the next fit keeps it.
        p.call("pdfCtrlWheel", "240")
        check(p.wait(lambda: abs(pd()["zoom"] - 1.21) < 0.01 and abs(pd()["scale"] - fitted * 1.21) < 0.02),
              f"Ctrl+wheel up: larger ({pd()['zoom']:.2f}, {pd()['scale']:.2f})")
        p.call("pdfCtrlWheel", "-240")
        check(p.wait(lambda: abs(pd()["zoom"] - 1) < 0.01), f"…and down: back ({pd()['zoom']:.2f})")
        p.call("pdfPinch", "1.5")
        check(p.wait(lambda: abs(pd()["zoom"] - 1.5) < 0.01), f"a pinch: its size taken as the zoom ({pd()['zoom']:.2f})")
        p.call("pdfFit")
        check(p.wait(lambda: abs(pd()["scale"] - fitted * 1.5) < 0.02), f"…kept through a fit ({pd()['scale']:.2f})")
        p.call("pdfKey", 0x30, 0)                           # 0
        check(p.wait(lambda: abs(pd()["zoom"] - 1) < 0.01 and abs(pd()["scale"] - fitted) < 0.01), "…and 0 fits it again")
        # A scan (plan.md item 15, step 5): no words of its own; r reads it
        # into a copy with words, which takes its place; then a drag
        # selects in it and m marks it, as in any paper.
        if all(shutil.which(x) for x in ("magick", "pdftoppm", "tesseract", "qpdf")):
            p.call("pdfKey", KEY_ESC, 0)
            p.wait(lambda: not pd()["shown"])
            lined_pdf(p.tmp / "typed.pdf", [["Reflexive thematic analysis is a method", "for finding patterns of meaning in data."]])
            subprocess.run(["pdftoppm", "-r", "150", "-png", "-singlefile", str(p.tmp / "typed.pdf"), str(p.tmp / "scanpage")], check=True)
            subprocess.run(["magick", str(p.tmp / "scanpage.png"), "-units", "PixelsPerInch", "-density", "150", str(course / "Scan.pdf")], check=True)
            sc = lambda: json.loads(p.call("pdfScan"))
            p.call("openFile", "Studies/Course A/Scan.pdf", "false")
            check(p.wait(lambda: pd()["ready"] and sc()["scanned"] and sc()["ocrable"] and not sc()["text"]),
                  f"a scan opens, said to have no words, r offered ({sc()})")
            p.call("pdfKey", 0x52, 0)                       # r
            check(p.wait(lambda: sc()["ocr"] != "" and sc()["text"] and sc()["progress"] is None, 60),
                  f"r reads it: a copy with words takes its place ({sc()})")
            check(p.wait(lambda: pd()["ready"] and sc()["url"].endswith(".pdf") and "reading/ocr" in sc()["url"]), "…the copy is what is shown")
            p.wait(lambda: mk()["dressed"] >= 1, 10)
            time.sleep(1)
            p.call("pdfDrag", "0", "73", "69", "200", "69")
            check(p.wait(lambda: mk()["selected"] != ""), f"…its words can be selected ({mk()['selected']!r})")
            p.call("pdfKey", 0x4D, 0)                       # m
            check(p.wait(lambda: len(mk()["read"]["marks"]) == 1 and mk()["read"]["marks"][0]["placed"]),
                  f"…and marked ({mk()['read']['marks']})")
            p.wait(lambda: not json.loads(p.call("pdfAsk"))["asking"] or p.call("pdfChooseProject", "") is not None)
            p.call("pdfKey", KEY_ESC, 0)
            p.wait(lambda: not pd()["shown"])
            p.call("openFile", "Studies/Course A/Paper.pdf", "false")
            p.wait(lambda: pd()["ready"] and pd()["label"] == "Paper")
        else:
            print("skip a scan read (magick, pdftoppm, tesseract or qpdf missing)")
        # Dark pages (plan.md item 15, step 4): i, kept for this paper.
        check(not pd()["dark"] and not pd()["darkDrawn"], "a paper opens as printed")
        p.call("pdfKey", 0x49, 0)                           # i
        check(p.wait(lambda: pd()["dark"] and pd()["darkDrawn"]), f"i: its pages in the theme's colours ({pd()})")
        p.call("pdfKey", KEY_ESC, 0)
        p.wait(lambda: not pd()["shown"])
        p.call("openFile", "Studies/Course A/Paper.pdf", "false")
        check(p.wait(lambda: pd()["ready"] and pd()["dark"] and pd()["darkDrawn"]), "…kept: opened again, it is dark")
        p.call("pdfKey", 0x49, 0)
        check(p.wait(lambda: not pd()["dark"] and not pd()["darkDrawn"]), "i again: as printed")
        p.call("pdfKey", KEY_ESC, 0)
        check(p.wait(lambda: not pd()["shown"]), "…and Esc closes it")
        # The read view (step 4): a picture by name, a link followed to its
        # heading and back, a table drawn as one block.
        att = p.vault / "_Attachments"
        att.mkdir(exist_ok=True)
        import base64
        (att / "board.png").write_bytes(base64.b64decode(
            "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAYAAAD0In+KAAAAEUlEQVR4nGP4z8DwHwQZGBgAJ+wE/Fa3oGAAAAAASUVORK5CYII="))
        (course / "Themes.md").write_text("# Themes\n\n## Built\n\nThemes are built, not found.\n")
        (course / "Links.md").write_text("# Links\n\n![[board.png]]\n\nSee [[Themes#Built|how themes are made]].\n\n"
                                         "| a | b |\n|---|---|\n| 1 | 2 |\n")
        p.call("openFile", "Studies/Course A/Links.md", "false")
        check(p.wait(lambda: json.loads(p.call("rowKinds"))[2] == "image" and "table" in json.loads(p.call("rowKinds"))),
              f"a picture's line and a table's lines are drawn as such ({p.call('rowKinds')})")
        img = lambda: json.loads(p.call("imageShown", 2))
        check(p.wait(lambda: (img() or {}).get("src", "").endswith("_Attachments/board.png") and (img() or {}).get("natural") == {"w": 2, "h": 1}),
              f"![[board.png]] is found by name, its size read from the file ({img()})")
        check(img()["width"] == 2, f"…and never drawn larger than it is ({img()})")
        at = p.call("text").index("how themes")
        p.call("cursor", at)
        p.call("pageKey", KEY_RETURN, 0x08000000)          # Alt+Enter
        check(p.wait(lambda: fs()["filePath"] == "Studies/Course A/Themes.md" and p.call("cursorLine") == "2"),
              f"Alt+Enter follows the link, to its heading ({fs()['filePath']}, line {p.call('cursorLine')})")
        p.call("pageKey", 0x01000012, CTRL | 0x08000000)    # Ctrl+Alt+Left
        check(p.wait(lambda: fs()["filePath"] == "Studies/Course A/Links.md" and p.call("cursorAt") == str(at)),
              f"Ctrl+Alt+←: back where the link was, the cursor at it ({fs()['filePath']}, {p.call('cursorAt')})")
        p.call("openFile", "agents/longhand/knowledge/about-you.md", "true")
        check(p.wait(lambda: fs()["readOnly"] and "What the agent keeps." in p.call("text")), "the agent's file opens to read")
        p.call("cursorEnd")
        p.call("type", " typed")
        time.sleep(0.8)
        check((kept / "about-you.md").read_text() == "What the agent keeps.\n" and "typed" not in p.call("text"),
              "…and nothing typed reaches it")
        p.call("pageKey", 0x48, CTRL)                      # Ctrl+H
        check(p.wait(lambda: fs()["dayNote"] and fs()["filePath"] == ""), f"Ctrl+H: home to today ({fs()})")
        check(not nt()["askable"], "today has no \"ask about this note\": the day conversation reads it already")
        # One history (slice 4 of docs/keys-proposal.md): Ctrl+[ and Ctrl+]
        # go back and on through whatever the middle showed: a file, the
        # dashboard, a day.
        KEY_LB, KEY_RB = 0x5b, 0x5d
        p.call("pageKey", KEY_LB, CTRL)
        check(p.wait(lambda: fs()["filePath"] == "agents/longhand/knowledge/about-you.md"),
              f"Ctrl+[: back to the file Ctrl+H left ({fs()['filePath']!r})")
        p.call("pageKey", KEY_RB, CTRL)
        check(p.wait(lambda: fs()["dayNote"] and fs()["filePath"] == ""), f"Ctrl+]: on again, to today ({fs()})")
        p.call("pageKey", KEY_2, CTRL)
        check(p.wait(lambda: panes()["center"] == "dash"), f"Ctrl+2: the dashboard ({panes()})")
        p.call("dashKey", KEY_LB, CTRL)
        check(p.wait(lambda: panes()["center"] == "note" and fs()["dayNote"]), f"Ctrl+[ on the dashboard: back to the note ({panes()})")
        p.call("pageKey", KEY_RB, CTRL)
        check(p.wait(lambda: panes()["center"] == "dash"), f"…Ctrl+]: the dashboard again ({panes()})")
        p.call("dashKey", KEY_ESC, 0)
        p.wait(lambda: panes()["center"] == "note")
        today_label = fs()["label"]
        p.call("pageKey", KEY_LB, ALT)                     # Alt+[: the day before with a note
        check(p.wait(lambda: fs()["label"] != today_label), f"Alt+[: the day before ({fs()['label']!r})")
        p.call("pageKey", KEY_LB, CTRL)
        check(p.wait(lambda: fs()["label"] == today_label and panes()["center"] == "note"),
              f"…Ctrl+[: back to today, not to the dashboard Esc closed first ({fs()['label']!r}, {panes()})")
        p.call("pageKey", KEY_LB, CTRL)
        check(p.wait(lambda: panes()["center"] == "dash"), f"…and Ctrl+[ again: the dashboard, the step before ({panes()})")
        yday_note = p.daily / f"{YDAY}.md"
        yday_note.write_text(yday_note.read_text().rstrip("\n") + "\n\n- [ ] a task from the day before\n")
        p.call("dashKey", KEY_ESC, 0)
        p.wait(lambda: panes()["center"] == "note")
        p.call("pageKey", KEY_2, CTRL)
        def other_row():
            return next((n for n, r in enumerate(json.loads(p.call("dashRows")))
                         if r.get("kind") == "task" and r.get("text") == "a task from the day before"), -1)
        check(p.wait(lambda: panes()["center"] == "dash" and other_row() >= 0), "a task on another day, to go to")
        other = other_row()
        p.call("dashFocus", other)
        p.call("dashKey", KEY_RETURN, 0)
        check(p.wait(lambda: panes()["center"] == "note" and fs()["label"] != today_label), f"Enter: its line, on its day ({fs()['label']!r})")
        p.call("pageKey", KEY_LB, CTRL)
        check(p.wait(lambda: panes()["center"] == "dash"),
              f"…one Ctrl+[: the dashboard, the move made of two (closing it, opening the day) one step ({panes()}, {fs()['label']!r})")
        p.call("dashKey", KEY_ESC, 0)
        p.open_fresh()
        check(fs()["space"] == "time" and not fs()["open"], "a fresh open lands on Time, the sidebar closed")

        # 12w. the agent's pane sized by hand (2026-11-22,
        # docs/explorations/chat-width): Alt+Z flips reading ↔ discussing,
        # Alt+Shift+←/→ nudge the edge, a drag sets it; each split is kept
        # per screen width and per middle (a paper apart from a note); a
        # paper keeps a readable column for the keys, a drag goes under it.
        # Too narrow for both: one at a time, following the keys.
        ALT = 0x08000000
        ps = lambda: json.loads(p.call("paneSize"))
        widths = p.state / "longhand" / "pane-widths.json"
        p.resize(1150, 850)
        p.call("openFile", reading_rel, "false")
        p.wait(lambda: json.loads(p.call("pdf"))["settled"], 10)
        p.call("pageKey", KEY_3, CTRL)
        check(p.wait(lambda: ps()["right"] == "day" and ps()["kind"] == "paper" and not ps()["alone"]),
              f"beside a paper, the agent's pane opens on reading ({ps()})")
        w0, st = ps()["width"], ps()
        check(st["split"] == "reading" and st["sizable"], f"…in the reading split ({st})")
        check(p.call("pageKey", KEY_Z, ALT) == "true" and p.wait(lambda: ps()["split"] == "discussing"), "Alt+Z: discussing")
        st = ps()
        check(st["width"] >= w0 and st["room"] - st["width"] >= min(st["floor"], st["room"] - w0),
              f"…the chat wider, the paper never under its readable floor by a key ({st})")
        wide = st["width"]
        p.call("pageKey", KEY_LEFT, ALT | SHIFT)
        check(ps()["width"] == wide, f"Alt+Shift+← at the paper's floor: no wider ({ps()})")
        p.call("pageKey", KEY_RIGHT, ALT | SHIFT)
        check(p.wait(lambda: ps()["width"] < wide), f"Alt+Shift+→: narrower ({ps()})")
        narrower = ps()["width"]
        check(p.wait(lambda: widths.is_file() and json.loads(widths.read_text())[st["screen"]]["paper"]["discussing"] == narrower),
              f"…kept for this screen and a paper ({widths.read_text() if widths.is_file() else 'no file'})")
        p.call("paneDrag", "300")
        st = ps()
        check(st["room"] - st["width"] < st["floor"] and st["width"] <= st["ceiling"],
              f"a drag goes under the paper's floor, never past what the chat can use ({st})")
        check(p.call("pageKey", KEY_Z, ALT) == "true" and p.wait(lambda: ps()["split"] == "reading" and ps()["width"] == w0),
              f"Alt+Z: back to reading, where it was ({ps()})")
        check(p.call("pageKey", KEY_Z, ALT) == "true" and p.wait(lambda: ps()["width"] == st["width"]),
              f"…and discussing again keeps where the drag left it ({ps()})")
        p.call("pageKey", KEY_Z, ALT)
        # One at a time: too narrow for the paper's floor and the pane's least.
        p.resize(701, 850)
        p.call("openFile", reading_rel, "false")
        p.wait(lambda: json.loads(p.call("pdf"))["settled"], 10)
        p.call("pageKey", KEY_3, CTRL)
        check(p.wait(lambda: ps()["alone"] and ps()["right"] == "day" and not ps()["tucked"]),
              f"a narrow window beside a paper: the chat alone, over it ({ps()})")
        check(p.call("pageKey", KEY_Z, ALT) == "true" and p.wait(lambda: ps()["tucked"] and panes()["here"] == "center"),
              f"Alt+Z: the paper, the chat waiting in its strip ({ps()})")
        check(p.call("pageKey", KEY_Z, ALT) == "true" and p.wait(lambda: not ps()["tucked"] and panes()["here"] == "right"),
              f"…and again: the chat ({ps()})")
        p.call("closePanes")
        p.open_fresh()

        # 12z. hover hints (docs/hints.md): a key puts them away, a modifier
        # alone does not; a click names its key once a day, never a list's
        # Enter, never a key already used.
        KEY_CTRL, KEY_A, KEY_H, KEY_BACKSLASH = 0x01000021, 0x41, 0x48, 0x5c
        p.call("hand")
        p.call("keyPage", KEY_CTRL, CTRL)
        check(p.call("handOn") == "true", "holding Ctrl alone keeps the hover hints")
        p.call("keyPage", KEY_A, 0)
        check(p.call("handOn") == "false", "…a key puts them away until the hand moves the mouse")
        today_key = json.loads(p.call("keysOf", "today"))[0]
        p.call("untaught")      # the suite has pressed Ctrl+H often enough to know it
        p.call("clearHint")
        p.call("mouseDid", "today")
        check(p.call("hint") == "next time: " + today_key, f"a click on today names its key ({p.call('hint')!r})")
        p.call("clearHint")
        p.call("mouseDid", "today")
        check(p.call("hint") == "", "…once a day")
        p.call("mouseDid", "listOpen")
        check(p.call("hint") == "", "a list's Enter is never named")
        for _ in range(4):
            p.call("keyPage", KEY_BACKSLASH, CTRL)
        p.call("mouseDid", "sidebar")
        check(p.call("hint") == "", "a key used three times is not named again")
        KEY_CTRL_ALONE = 0x01000021
        p.call("keyPage", KEY_CTRL_ALONE, CTRL)
        check(p.wait(lambda: p.call("ctrlShown") == "true", 3), "Ctrl held a moment shows its keys")
        check(p.call("ctrlKey", "checkbox") == "L" and p.call("ctrlKey", "pin") == "Alt+P" and p.call("ctrlKey", "dashDone") == "L",
              f"…each the rest of its key after Ctrl ({p.call('ctrlKey', 'pin')!r})")
        check(any(i["words"] == "every key" for i in json.loads(p.call("ctrlStrip"))), "…and the strip names the rest")
        p.call("keyPage", KEY_A, 0)
        check(p.call("ctrlShown") == "false", "…another key puts them away")
        taught = p.state / "longhand" / "taught.json"
        check(p.wait(lambda: json.loads(taught.read_text())["today"]["said"] == TODAY_ISO
                     and json.loads(taught.read_text())["sidebar"]["keys"] >= 3),
              "…kept in the state folder (taught.json)")

        # 12y. export as a PDF (ExportSheet.qml; plan.md item 13): Ctrl+Shift+E
        # in a section lists its blocks in the note's place, a checkbox out;
        # Space, L and the title change what is written; Enter writes it to
        # Settings' folder and opens it where the note was.
        KEY_E, KEY_L, KEY_SPACE, KEY_DOWN, KEY_RETURN, KEY_ESC = 0x45, 0x4c, 0x20, 0x01000015, 0x01000004, 0x01000000
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "# Diary #studio\n- [ ] hand it in\n## What happened\n"
                                             "We met twice.\n\n# Other\nNot this.\n")
        p.wait(lambda: "We met twice." in p.call("text"))
        before = p.call("text")
        p.call("cursor", p.offset_of_line(p.line_of("We met twice.")))

        def ex():
            return json.loads(p.call("exportState"))
        check(p.call("keyPage", KEY_E, CTRL | SHIFT) == "true"
              and p.wait(lambda: ex()["open"] and not ex()["busy"] and len(ex()["rows"]) > 0, 15),
              f"Ctrl+Shift+E opens the export with the section's blocks ({ex()})")
        e = ex()
        check(e["title"] == "Diary" and [r["text"] for r in e["rows"]] == ["- [ ] hand it in", "## What happened", "We met twice."],
              f"…titled by its upmost heading, without the next section ({e['title']!r}, {[r['text'] for r in e['rows']]})")
        check([r["in"] for r in e["rows"]] == [False, True, True] and e["rows"][0]["why"] == "a checkbox" and e["words"] == 3,
              f"…the checkbox out and why, the words counted ({e['words']})")
        check(e["here"] == "center" and json.loads(p.call("pdf"))["shown"] is False, "…in the note's place, with the keys")
        p.call("exportKey", KEY_SPACE, 0)
        check(ex()["rows"][0]["in"] and ex()["words"] == 6, f"Space puts the checkbox in, and its words count ({ex()['words']})")
        p.call("exportKey", KEY_SPACE, 0)
        p.call("exportKey", KEY_DOWN, 0)
        check(ex()["focus"] == 1, "↓ moves to the next block")
        p.call("exportKey", KEY_L, 0)
        check(ex()["look"] == "omarchy", "L: the Omarchy look")
        p.call("exportKey", KEY_L, 0)
        check(ex()["look"] == "minimal", "…and back to minimal")
        p.call("exportTitle", "Diary 1")
        p.call("exportKey", KEY_RETURN, 0)
        out = p.tmp / "Downloads" / "Diary 1.pdf"
        # The PDF itself only where pandoc and xelatex are (agent/export.py
        # looks them up on PATH, as here; tests/test_export.py the same).
        if shutil.which("pandoc", path=p.env["PATH"]) and shutil.which("xelatex", path=p.env["PATH"]):
            check(p.wait(lambda: json.loads(p.call("pdf"))["shown"] and out.is_file(), 60),
                  f"Enter writes the PDF under its title, in Settings' folder ({ex()['error']!r})")
            check(p.wait(lambda: json.loads(p.call("pdf"))["ready"] and json.loads(p.call("pdf"))["label"] == "Diary 1"
                         and not ex()["open"]),
                  f"…and it opens where the note was, the export closed ({p.call('pdf')}, open: {ex()['open']})")
            check(p.call("hint").startswith("written to "), f"…saying where it went ({p.call('hint')!r})")
        else:
            print("skip the PDF itself: pandoc or xelatex is not installed")
            check(p.wait(lambda: "not installed" in ex()["error"], 15) and not out.exists(),
                  f"…without pandoc or xelatex, Enter says so and writes nothing ({ex()['error']!r})")
        p.call("pdfKey", KEY_ESC, 0)
        check(p.wait(lambda: not json.loads(p.call("pdf"))["shown"]) and p.call("text") == before,
              "Esc: back to the note, its words untouched")
        sel_from = p.offset_of_line(p.line_of("- [ ] hand it in"))
        p.call("selectInLine", sel_from + 6, sel_from + 10)
        p.call("keyPage", KEY_E, CTRL | SHIFT)
        check(p.wait(lambda: ex()["open"] and not ex()["busy"] and len(ex()["rows"]) > 0, 15)
              and [r["in"] for r in ex()["rows"]] == [True, False, False]
              and ex()["rows"][1]["why"] == "outside the selection",
              f"a selection inside one line: only its block is in, a checkbox too ({[(r['in'], r['why']) for r in ex()['rows']]})")
        p.call("exportKey", KEY_ESC, 0)
        check(not ex()["open"] and ex()["here"] == "center" and p.call("text") == before, "Esc closes it, back to the note")

        # …and from a deadline's row on the dashboard (slice 3): its section
        # found by its name among its course's, the PDF named after it, the
        # box left open; Esc goes back to the dashboard.
        due = (dt.date.today() + dt.timedelta(days=5)).isoformat()
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "# Diary #studio\nWe met twice.\n\n"
                                             f"- [ ] Diary 2 #studio 📅 {due}\n\n# Other\nNot this.\n")
        p.wait(lambda: "Diary 2" in p.call("text"))
        p.call("pageKey", KEY_2, CTRL)

        def diary_row():
            return next((n for n, r in enumerate(json.loads(p.call("dashRows")))
                         if r.get("kind") == "task" and r.get("text") == "Diary 2"), -1)
        check(p.wait(lambda: panes()["center"] == "dash" and diary_row() >= 0, 10),
              f"the deadline's row on the dashboard ({panes()}; rows: {[r.get('text') for r in json.loads(p.call('dashRows'))][:12]}; "
              f"on disk: {'Diary 2' in p.note()}; trace: {p.call('tasksTrace')[-600:]})")
        p.call("dashFocus", diary_row())
        p.call("dashKey", KEY_E, CTRL | SHIFT)
        check(p.wait(lambda: ex()["open"] and not ex()["busy"] and ex()["from"], 15)
              and ex()["title"] == "Diary 2" and ex()["from"]["heading"] == "Diary" and panes()["center"] == "note",
              f"Ctrl+Shift+E on it: its section, titled after it ({ex()['title']!r}, {ex()['from']})")
        check([r["text"] for r in ex()["rows"]] == ["We met twice.", f"- [ ] Diary 2 #studio 📅 {due}"]
              and [r["in"] for r in ex()["rows"]] == [True, False],
              "…the section's blocks, the deadline's own box out")
        p.call("exportKey", KEY_ESC, 0)
        check(p.wait(lambda: not ex()["open"] and panes()["center"] == "dash"), f"Esc: back to the dashboard ({panes()})")
        check("- [ ] Diary 2" in p.note(), "…and the deadline is still open")
        p.call("dashKey", KEY_ESC, 0)
        p.wait(lambda: panes()["center"] == "note")

        # 12x. the tasks a day is for, written on any day (2026-11-14): a
        # box written yesterday "for today" is counted on today's page.
        iso = dt.date.today().isoformat()
        ahead = (dt.date.today() - dt.timedelta(days=2)).strftime("%Y.%m.%d")
        (p.daily / f"{ahead}.md").write_text(header(ahead) + f"- [ ] written ahead for today 📅 {iso}\n"
                                             f"- [x] already done for today ⏳ {iso}\n")
        p.call("openDay", TODAY)
        p.call("refreshDated")
        day = lambda: json.loads(p.call("dayTasks"))
        check(p.wait(lambda: {"written ahead for today", "already done for today"} <= set(day()["titles"])),
              f"a task written yesterday for today is on today's page ({day()})")
        check(day()["done"] >= 1 and day()["titles"].index("written ahead for today") < day()["titles"].index("already done for today"),
              f"…counted done or not, the open ones first ({day()})")
        was = day()["open"]
        check(p.call("keyPage", 0x54, 0x04000000 | 0x02000000) == "true" and p.wait(lambda: day()["open"] != was),
              "Ctrl+Shift+T unfolds the list, or folds it")
        p.call("keyPage", 0x54, 0x04000000 | 0x02000000)

        # 13. the usage log: written on close, event names only
        p.call("closeAll")
        usage = p.state / "longhand" / "usage.tsv"
        check(p.wait(lambda: "\tclose\t" in usage.read_text()), "closing the page writes its usage log")
        events = {line.split("\t")[1] for line in usage.read_text().splitlines()}
        check({"open", "close", "ctrl-d", "bound", "day", "drop", "rename"} <= events, f"…with what was used ({sorted(events)})")
        check(not any(w in usage.read_text() for w in ("chapter", "obsidian", "one-pager")), "…and none of the note's words")
    finally:
        p.close()
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except PageFrozen as e:
        print(f"FAIL {e}; stopped here, as every check after it would wait too")
        print("1 FAILED" if failures == 0 else f"{failures + 1} FAILED")
        sys.exit(1)
