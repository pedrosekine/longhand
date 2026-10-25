#!/usr/bin/env python3
"""The page's own logic, driven live: bound lines, cancelling, catching up with
the deadline store, outside edits, going to a line, agent accepts.

Needs a Hyprland session with quickshell and the omarchy shell modules. It
builds a throwaway config, vault and deadline store under /tmp, opens the
page as a window titled "Page scratch" that never takes keyboard focus (a
Hyprland rule for that title only), and talks to it over IPC — no key is
ever pressed. Your notes, store and running shell are not touched.

Run: python3 tests/page/run.py
"""
import datetime as dt
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "agent"))
import blocks  # noqa: E402
import lifespan  # noqa: E402

# What the runner writes when the student talks to a block: both turns, the
# way `longhand-agent chat` records them. Enough for the page to settle the
# message it was holding and draw the answer.
CHAT_STUB = """import json, pathlib, sys

daily, args = pathlib.Path(sys.argv[1]), sys.argv[2:]
h = args[args.index("--hash") + 1]
msg = args[args.index("--message") + 1]
stem = args[args.index("--date") + 1]
path = daily / (stem + ".json")
state = json.loads(path.read_text()) if path.exists() else {"date": stem, "blocks": {}}
rec = state["blocks"].setdefault(h, {"state": "seen"})
rec.setdefault("chat", []).append({"role": "student", "text": msg})
rec["chat"].append({"role": "agent", "text": "stub answer to: " + msg})
rec["state"] = "reply"
rec["read"] = False
rec.setdefault("reply", "")
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(state))
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
    if c["due"] and c["due"][:10] < day:
        day = c["due"][:10]
    reply["proposals"].append({"kind": "do-date", "key": c["key"], "date": day, "why": "Tomorrow is free."})
    reply["questions"].append({"key": "", "question": "Do you work on weekends?", "recommended": "No"})
# A scripted reply (slice 5): its "key_of" names a box by its words.
if os.path.exists(os.path.join(d, "plan-reply.json")) and payload.startswith("# Plan"):
    data = json.loads(re.search(r"```json\\n(.*?)\\n```", payload, re.S).group(1))
    reply = json.load(open(os.path.join(d, "plan-reply.json")))
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
if "--agent" in args and args[args.index("--agent") + 1] == "longhand-day":
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


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


class Page:
    def __init__(self, fake_home=False):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="page-test-"))
        self.shell = self.tmp / "shell"
        self.shell.mkdir()
        for mod in ("Commons", "Ui"):
            (self.shell / mod).symlink_to(f"/usr/share/omarchy/shell/{mod}")
        (self.shell / "page").symlink_to(ROOT / "plugin-page")
        shutil.copy(ROOT / "tests" / "page" / "harness.qml", self.shell / "shell.qml")
        self.vault = self.tmp / "vault"
        self.daily = self.vault / "Daily"
        self.daily.mkdir(parents=True)
        self.state = self.tmp / "state"
        (self.state / "longhand").mkdir(parents=True)
        self.store = self.state / "longhand" / "deadlines.tsv"
        cfg = self.tmp / "config"
        (cfg / "longhand").mkdir(parents=True)
        (cfg / "omarchy").symlink_to(pathlib.Path.home() / ".config" / "omarchy")   # the theme
        self.runner = self.tmp / "runner"
        (cfg / "longhand" / "config.json").write_text(json.dumps({
            "vault": str(self.vault), "daily": {"dir": "Daily", "format": "YYYY.MM.DD"},
            "runner": str(self.runner), "check": str(ROOT / "cli" / "longhand-check"), "weekStart": "monday",
            "inbox": str(self.tmp / "Downloads")}))
        (self.tmp / "Downloads").mkdir()
        bindir = self.tmp / "bin"
        bindir.mkdir()
        (bindir / "pomo").symlink_to(ROOT / "cli" / "pomo")
        # The tick's sound, heard by a stub: each play is logged, never
        # sounded, and Do Not Disturb is off. Until 2026-10-19 the tests
        # silenced the page instead, and so missed that it never played.
        self.played = self.tmp / "played.log"
        (bindir / "pw-play").write_text(f'#!/bin/sh\necho "$@" >> "{self.played}"\n')
        (bindir / "pw-play").chmod(0o755)
        real_shell = shutil.which("omarchy-shell") or "false"
        (bindir / "omarchy-shell").write_text('#!/bin/sh\n[ "$1 $2" = "notifications isDnd" ] && { echo off; exit 0; }\n'
                                              f'exec "{real_shell}" "$@"\n')
        (bindir / "omarchy-shell").chmod(0o755)
        (bindir / "opencode").write_text(PLAN_STUB)
        (bindir / "opencode").chmod(0o755)
        self.stub = self.tmp / "stub"
        self.stub.mkdir()
        # Hyprland, played over a throwaway hypr folder: the keys sheet's
        # writes, reloads and submap never reach the real one.
        self.hypr = cfg / "hypr"
        self.hypr.mkdir()
        (self.hypr / "bindings.lua").write_text(BINDINGS)
        (bindir / "hyprctl").write_text(f'#!/bin/sh\nexec python3 "{ROOT}/tests/fake_hyprctl.py" "$@"\n')
        (bindir / "hyprctl").chmod(0o755)
        # Only the local commands run (no model): accept, projects, sections.
        # A model pass is a stub that takes its time, so the page's "this is
        # away" mark can be seen while it is away; `chat` also writes the
        # day's state the way the runner would, so the whole turn can be
        # followed — sent, thinking, answered.
        chatstub = self.tmp / "chatstub.py"
        chatstub.write_text(CHAT_STUB)
        # Every call is logged with when it started (and, for the fetch, when
        # it ended), so the order of an opening can be checked; with
        # `slow-fetch` present the fetch takes two seconds, as a network does.
        self.calls = self.tmp / "calls.log"
        self.runner.write_text(f"""#!/bin/bash
echo "$(date +%s.%N) start $1 $3" >> "{self.calls}"
if [ "$1" = projects ]; then
  [ -e "{self.stub}/slow-fetch" ] && sleep 2
  "{ROOT}/agent/longhand-agent" "$@"; rc=$?
  echo "$(date +%s.%N) end $1" >> "{self.calls}"
  exit $rc
fi
case "$1" in
  accept|projects|project|sections|next|tasks|box|timetable|plan|proposals|proposal|talk|thread|rate|notebook|autonomy|day|search) exec "{ROOT}/agent/longhand-agent" "$@" ;;
  run) sleep 2; exit 0 ;;
  chat) sleep 2; exec python3 "{chatstub}" "{self.vault}/agents/longhand/daily" "$@" ;;
esac
""")
        self.runner.chmod(0o755)
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(cfg), XDG_STATE_HOME=str(self.state),
                        STUB_DIR=str(self.stub),
                        PATH=f"{bindir}:{os.environ['PATH']}", FAKE_HYPR_DIR=str(self.hypr),
                        FAKE_HYPR_REAL=shutil.which("hyprctl") or "")
        self.env.pop("LONGHAND_SILENT", None)
        if fake_home:
            # A home of its own, holding a copy of the current theme, so a
            # theme switch can be replayed without touching the real one.
            self.home = self.tmp / "home"
            self.theme = self.home / ".local" / "state" / "omarchy" / "current" / "theme"
            self.theme.mkdir(parents=True)
            real = pathlib.Path.home() / ".local" / "state" / "omarchy" / "current" / "theme"
            for name in ("colors.toml", "shell.toml"):
                if (real / name).exists():
                    shutil.copy(real / name, self.theme / name)
            self.env["HOME"] = str(self.home)
        subprocess.run(["hyprctl", "eval", 'hl.window_rule({ match = { title = "^Page scratch$" }, no_initial_focus = true })'],
                       capture_output=True)
        # A known size, whatever else is open on the workspace (tiled into a
        # full one, the window can be a few pixels wide).
        subprocess.run(["hyprctl", "eval", 'hl.window_rule({ match = { title = "^Page scratch$" }, float = true, size = { 701, 850 } })'],
                       capture_output=True)
        self.proc = subprocess.Popen(["quickshell", "-p", str(self.shell)], env=self.env,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.wait(lambda: self.call("state").startswith("{"), 10)

    def call(self, fn, *args):
        r = subprocess.run(["quickshell", "ipc", "-p", str(self.shell), "call", "page", fn, *map(str, args)],
                           capture_output=True, text=True, env=self.env)
        out = r.stdout
        return out[:-1] if out.endswith("\n") else out   # only IPC's own newline: a note may start with one

    def wait(self, cond, timeout=6.0):
        end = time.time() + timeout
        while time.time() < end:
            try:
                if cond():
                    return True
            except (ValueError, KeyError, IndexError, TypeError, json.JSONDecodeError):   # TypeError: not asked yet (null)
                pass
            time.sleep(0.15)
        return False

    def pomo(self, *args):
        return subprocess.run(["pomo", "deadline", *args], capture_output=True, text=True, env=self.env).stdout

    def check(self):
        """The check, as the popup runs it after a change."""
        return subprocess.run([str(ROOT / "cli" / "longhand-check"), "--quiet"], capture_output=True, text=True, env=self.env)

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
        self.call("closeAll")
        self.call("summon", payload)
        self.wait(lambda: json.loads(self.call("state"))["ready"])
        time.sleep(0.5)

    def close(self):
        self.proc.terminate()
        self.proc.wait()
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
    target = next(t for t in ("tokyo-night", "gruvbox", "nord") if (themes / t / "colors.toml").exists())
    want = re.search(r'^accent\s*=\s*"(#[0-9A-Fa-f]{6})"', (themes / target / "colors.toml").read_text(), re.M).group(1).lower()
    p = Page(fake_home=True)
    try:
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "# heading\n")
        p.open_fresh()
        before = p.call("palette")
        nxt = p.theme.parent / "next-theme"
        nxt.mkdir()
        for name in ("colors.toml", "shell.toml"):
            if (themes / target / name).exists():
                shutil.copy(themes / target / name, nxt / name)
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
        check(f"accent={want}" not in before and repainted and took < 1.0, f"a theme switch repaints the page at once ({target})")
        heads = p.call("palette").split(" h=")[1].split(" ")[0].split(",")
        # H1 is the new accent, deepened if that accent sat too near the text:
        # the same colour, never another one.
        check(len(set(heads)) == 4 and delta_e(heads[0], want) < 25,
              f"…and the new theme's accent leads the heading ramp ({','.join(heads)}, {delta_e(heads[0], want):.0f} ΔE off {want})")
    finally:
        p.close()


def main() -> int:
    theme_switch()
    p = Page()
    try:
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
        check(p.call("ask") == "null" and "cancelled" in p.call("hint"), f"…said under the cursor, nothing asked ({p.call('hint')!r})")
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
        p.store.rename(p.store.with_suffix(".away"))
        time.sleep(0.6)
        p.call("openDay", YDAY)
        time.sleep(1.5)
        check("^d3" in p.note(YDAY), "with the store unreadable, opening a note keeps its anchors")
        p.store.with_suffix(".away").rename(p.store)

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
        tmpf.rename(f)
        check(p.wait(lambda: "written by rename" in p.call("text")), "…also when written by rename (atomic save)")

        # 9. the popup's `o`: opening on a deadline's line
        p.open_fresh(json.dumps({"shape": "alongside", "goto": f"[[{YDAY}#^d3]]"}))
        check(p.wait(lambda: "from cli" in p.lines()[int(p.call("cursorLine"))]), "goto opens the note on the deadline's line")

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
        time.sleep(1.5)
        check(len(p.store.read_text().splitlines()) == before + 2, "another item offers it no more; a proposal naming no line adds once")
        check("- [ ] A0 poster\n" in p.note() and "Conference" not in p.note(), "…and that one takes no line")

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
        time.sleep(1)
        check("essay by the 19th of Feb\n" in p.note() and len(p.store.read_text().splitlines()) == count, "…and leaving does not bind it")
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
              "Ctrl+Z: the words are back and the deadline it made is gone")
        p.call("cursor", p.offset_of_line(p.line_of("read ch.7")) + 8)
        p.call("cursor", p.offset_of_line(p.line_of("next item")) + 2)
        time.sleep(1)
        check("read ch.7 by tomorrow\n" in p.note(), "…and it is not bound again")

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
        # The header's "ask" is the visible way in, on the same path as
        # Ctrl+Enter: it reads the sign on the block under the cursor.
        p.call("cursor", p.offset_of_line(p.line_of("Initial paper")) + 10)
        check(p.wait(lambda: p.call("sign") == "checkbox"), f"a box is a sign the header can see ({p.call('sign')})")
        p.call("cursor", 1)
        check(p.wait(lambda: p.call("sign") == ""), "a line with no sign offers nothing")
        p.call("askNow")
        check(p.wait(lambda: p.call("noSign") == "true"), "…and asking anyway says why instead of sending")

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
        p.call("insertTag", 1)
        check(p.wait(lambda: "first point #dtm " in p.call("text")), "Ctrl+Enter puts just the tag at the cursor")

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
        p.call("leaveProject")
        check(p.wait(lambda: json.loads(p.call("sections")) == []), "← goes back to the projects")
        before = p.note()
        p.call("projectEnter", 0, "false", "true")
        check(p.wait(lambda: p.note().rstrip().endswith("# Interdisciplinary Seminar #intsem")),
              "Shift+Enter still starts a class")
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
        before = len(list((p.state / "longhand" / "payloads").glob("*"))) if (p.state / "longhand" / "payloads").is_dir() else 0
        p.call("cursorEnd")
        p.call("type", " Is this ok?")
        p.call("askNow")
        time.sleep(1)
        after = len(list((p.state / "longhand" / "payloads").glob("*"))) if (p.state / "longhand" / "payloads").is_dir() else 0
        check(after == before, f"asking on a private note runs nothing ({before} → {after})")
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
        check(json.loads(p.call("panel"))["project"] is False and p.call("keyPage", KEY_B, CTRL | SHIFT) == "true",
              "Ctrl+Shift+B is taken too")
        check(p.wait(lambda: "**chapter**" in p.call("text")), "…and does not touch the words")

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
        time.sleep(0.3)
        rm = json.loads(p.call("room"))
        after = float(p.call("rowY", b))
        check(after >= before + rm["height"] - 1 and after >= rm["top"] + rm["height"] - 1,
              f"…and the next line moves below the question ({before} → {after}, {rm})")
        p.call("closeWhen")
        check(p.wait(lambda: abs(float(p.call("rowY", b)) - before) < 1), "…and back when it is answered or left")
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "just words\n")
        p.open_fresh()
        p.call("cursor", 3)
        p.call("askNow")
        check(p.wait(lambda: "nothing to ask here" in p.call("status")), f"a passing word is in the status line ({p.call('status')!r})")

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
        p.call("zoom", 1.25)
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
        p.call("dash")
        check(p.call("dashOpen") == "true", "Ctrl+T opens the dashboard")

        def heads():
            return [r["text"] for r in json.loads(p.call("dashRows")) if r["kind"] == "head"]

        def row(title):
            # The list is rebuilt whenever a line changes, so a row's index
            # is only good once it has stopped moving.
            def at():
                rows = json.loads(p.call("dashRows"))
                return next((n for n, r in enumerate(rows) if r.get("text") == title), -1), rows
            i, rows = at()
            for _ in range(20):
                time.sleep(0.3)
                j, rows = at()
                if i == j and j >= 0:
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
        check(p.call("dashKey", KEY_RETURN, CTRL) == "true", "Ctrl+Enter is the act that settles a row")
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
        check(p.wait(lambda: "1 done today" in p.call("dashCount")), f"…counted as done today ({p.call('dashCount')})")
        row("draft the intro")
        p.call("dashKey", 0x4c, CTRL)
        check(p.wait(lambda: "- [ ] draft the intro\n" in (p.daily / f"{YDAY}.md").read_text()),
              "Ctrl+L on a box done today opens it again, the day taken off")
        check(int(p.call("ticksHeard")) == heard + 1, "…with no sound: an untick is not a tick")
        p.call("tickSoundToggle")
        row("draft the intro")
        p.call("dashKey", 0x4c, CTRL)
        check(p.wait(lambda: "- [x] draft the intro" in (p.daily / f"{YDAY}.md").read_text())
              and int(p.call("ticksHeard")) == heard + 1, "with the sound turned off in Settings, a tick is silent")
        p.call("tickSoundToggle")
        row("draft the intro")
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
        row("loose thought")
        p.call("dashType", "p")
        check(p.wait(lambda: "- [ ] loose thought 🔽" in p.call("text")), "…and walks the three levels")
        row("loose thought")
        p.call("dashType", "p")
        check(p.wait(lambda: "- [ ] loose thought\n" in p.call("text")), "…back round to none")

        row("loose thought")
        check(p.call("dashKey", KEY_DELETE, 0) == "true", "Delete drops it")
        gone = f"- [-] loose thought ❌ {dt.date.today().isoformat()}"
        check(p.wait(lambda: gone in p.call("text")), f"…cancelled, with the day it was dropped ({p.call('text')[-45:]!r})")
        check(p.wait(lambda: not any(r.get("text") == "loose thought" for r in json.loads(p.call("dashRows")))),
              "…and it leaves the dashboard, because dropping is an answer")
        check(p.call("dashKey", KEY_Z, CTRL) == "true", "Ctrl+Z takes a drop back")
        check(p.wait(lambda: "- [ ] loose thought\n" in p.call("text")), "…with no mark left on the line")

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

        # A deadline's row shows what its line holds, as a task's does
        # (2026-10-25): the day to work on it, the priority, the estimate;
        # and t and p write them on its line.
        out = p.pomo("add", "the poster", "2030-01-08")
        pid = int(re.search(r"#(\d+)", out).group(1))
        p.call("cursorEnd")
        p.call("insert", f"\n- [ ] the poster [est:: 2h] 🔽 ⏳ 2030-01-03 📅 2030-01-08 ^d{pid}")
        p.call("cursor", 1)
        p.wait(lambda: p.deadline(pid)["link"] != "")
        # Opened afresh, the list is read again with the new line in it.
        if p.call("dashOpen") == "true":
            p.call("dash")
        p.call("dash")
        def poster():
            return next((r for r in json.loads(p.call("dashRows")) if r.get("text") == "the poster"), {})
        check(p.wait(lambda: poster().get("kind") == "deadline" and poster()["mark"] == "▽"
                     and poster()["pills"][0].startswith("do ") and poster()["pills"][-1] == "2h"),
              f"a deadline's row draws its do-date, priority and estimate ({poster()})")
        row("the poster")
        check(p.call("dashType", "p") == "true", "p on a deadline row is taken")
        check(p.wait(lambda: f"- [ ] the poster [est:: 2h] ⏳ 2030-01-03 📅 2030-01-08 ^d{pid}" in p.call("text")),
              f"…and walks its line's priority ({p.call('text')[-80:]!r})")
        row("the poster")
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
        check(p.wait(lambda: "NOT NOW" in heads() and "gone quiet" in row("an old aside").get("where", "")),
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
        check(p.call("pageKey", KEY_J, CTRL) == "true" and p.wait(lambda: p.call("dayShown") == "true"),
              "Ctrl+J opens the day's conversation from the note")
        p.call("daySend", "what comes first today?")
        check(p.wait(lambda: json.loads(p.call("dayTurns"))[-2:] == ["student: what comes first today?",
                                                                    "agent: day: what comes first today?"], timeout=12),
              f"a message to the day is answered, and kept in the day's state ({p.call('dayTurns')})")
        p.call("dayKey", 0x01000000, 0)
        check(p.wait(lambda: p.call("dayShown") == "false"), "Esc closes it")
        note_before = p.note()
        p.call("cursorEnd")
        p.call("type", "\n\nShould I ask the dean about the shortlist")
        p.wait(lambda: "ask the dean" in p.note())
        p.call("cursor", p.offset_of_line(p.line_of("ask the dean")) + 6)
        check(p.call("pageKey", KEY_ENTER, CTRL | SHIFT) == "true" and p.wait(lambda: p.call("dayShown") == "true")
              and "ask the dean" in p.call("dayBlockText"),
              f"Ctrl+Shift+Enter in a block opens the day pointing at it ({p.call('dayBlockText')!r})")
        p.call("daySend", "and this one?")
        check(p.wait(lambda: json.loads(p.call("dayTurns"))[-1] == "agent: day: and this one?", timeout=12)
              and p.call("dayBlockText") == "", "…the block goes with the message, and the box lets go of it")
        st = json.loads((p.vault / "agents" / "longhand" / "daily" / f"{TODAY}.json").read_text())
        check(st["day"]["turns"][-2].get("block", "") != "", "…and the message keeps which block it pointed at")
        p.call("dive")
        check(p.wait(lambda: p.call("dayShown") == "false") and json.loads(p.call("panel"))["margin"],
              "a block's own conversation is a room stepped into from the day")
        p.call("back")
        check(p.wait(lambda: p.call("dayShown") == "true"), "…and leaving it comes back to the day")
        p.call("dayKey", 0x01000000, 0)
        # The note as the sections after this one expect it.
        (p.daily / f"{TODAY}.md").write_text(note_before)
        p.open_fresh()

        # 12c''. what the day may search (slice 2): Settings → Ctrl+F lists the
        # vault's folders, the daily notes' own on; a switch is kept in
        # settings.json; a citation in an answer opens the note at its line.
        KEY_F, KEY_SPACE = 0x46, 0x20
        p.call("settings")
        check(p.call("settingsKey", KEY_F, CTRL) == "true" and p.call("settingsView") == "search",
              "Ctrl+F in settings: what the agent may search")
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
        p.call("searchKey", 0x01000000, 0)
        p.call("settingsKey", 0x01000000, 0)
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
        check(p.call("settingsKey", KEY_BACKSPACE, CTRL | SHIFT) == "true", "Ctrl+Shift+Backspace is taken")
        check(p.wait(lambda: [c["url"] for c in cals()] == [url]), "…and removes the picked calendar, the new one")
        p.call("settingsFocus", 0)
        p.call("settingsKey", KEY_BACKSPACE, CTRL | SHIFT)
        check(p.wait(lambda: cals() == [] and any("No calendar yet" in l for l in json.loads(p.call("settingsLines")))),
              "…and the last one, back to no calendar")
        check(p.call("settingsKey", 0x01000000, 0) == "true" and p.call("settingsOpen") == "false", "Esc goes back")
        uni.shutdown()

        # 12c'. the calendars and the first pass of the day (2026-10-18): what
        # reads the calendars waits for the fetch the same opening started.
        (p.stub / "slow-fetch").write_text("")
        p.call("closeAll")
        p.calls.write_text("")
        (p.state / "longhand" / "plan.json").unlink(missing_ok=True)
        p.open_fresh()
        def order():
            rows = [l.split(" ", 2) for l in p.calls.read_text().splitlines() if l.strip()]
            return [(float(t), what, rest.strip()) for t, what, rest in rows]
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
        KEY_K = 0x4b
        p.call("settings")
        check(p.call("settingsKey", KEY_K, CTRL) == "true" and p.wait(lambda: p.call("settingsView") == "notebook"),
              "Ctrl+K in settings opens what the agent knows")
        check(p.wait(lambda: any(r["text"] == "Lives in Vienna." for r in json.loads(p.call("notebookRows")))),
              "…its notes, line by line")
        rows = json.loads(p.call("notebookRows"))
        check(rows[0]["kind"] == "head" and rows[0]["text"] == "Profile" and rows[int(p.call("notebookPicked"))]["kind"] == "line",
              "…under each file's title, the first line picked")
        p.call("notebookFocus", next(i for i, r in enumerate(rows) if r["text"] == "Lives in Vienna."))
        check(p.call("notebookKey", KEY_BACKSPACE, CTRL | SHIFT) == "true", "Ctrl+Shift+Backspace forgets the picked line")
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
        # left is new, counted in its line; N walks the queue, round again.
        check(all(r["fresh"] for _, r in asks()) and ", 2 new" in p.call("dashCount"),
              f"what arrived since the last visit is new, and counted ({p.call('dashCount')!r}; {p.call('newSince')})")
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
        p.call("dash")
        p.call("dash")
        check(not any(r["fresh"] for _, r in asks()) and "new" not in p.call("dashCount"),
              f"left and opened again: nothing is new ({p.call('dashCount')!r})")
        ledger_file = p.state / "longhand" / "proposals.json"
        notes_before = {f.name: f.read_text() for f in p.daily.glob("*.md")}
        check(all(f.read_text() == notes_before[f.name] for f in p.daily.glob("*.md")), "proposing wrote nothing into a note")
        p.call("dashFocus", i)
        check(p.call("dashKey", KEY_RETURN, CTRL) == "true", "Ctrl+Enter on the proposal accepts it")
        when = prop["date"]
        check(p.wait(lambda: any(f"⏳ {when}" in f.read_text() for f in p.daily.glob("*.md"))),
              f"…and the page writes the do-date on the box's line (⏳ {when})")
        check(p.wait(lambda: any(x["kind"] == "do-date" and x["status"] == "accepted"
                                 for x in json.loads(ledger_file.read_text())["items"])), "…recorded as accepted")
        check(p.wait(lambda: not any(r["kind"] == "proposal" for _, r in asks())), "…and the row goes")
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
        p.call("plan", "true")
        check(p.wait(lambda: any(r["kind"] == "proposal" for _, r in asks()), timeout=15), "a proposal to talk about")
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
        check(json.loads(p.call("talk"))["settled"] == "accepted" and "Good, it is on its line." in json.loads(p.call("talk"))["turns"][-1],
              "…and the margin says how it ended, after the planner's last word")
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
        check(p.call("dashKey", KEY_RETURN, CTRL | SHIFT) == "true", "Ctrl+Shift+Enter on a task's row")
        check(p.wait(lambda: "student: why that day?" in json.loads(p.call("talk"))["turns"]),
              f"…opens the task's conversation beside the dashboard, what was said with the planner in it ({p.call('talk')})")
        check(json.loads(p.call("talk"))["item"] == "", "…nothing pinned to accept: it is the task itself")
        p.call("talkSend", "help me think it through")
        check(p.wait(lambda: "agent: stub answer to: help me think it through" in json.loads(p.call("talk"))["turns"], 10),
              f"…a message there is answered by the margin agent, in the same conversation ({json.loads(p.call('talk'))['turns'][-3:]})")
        p.call("talkKey", KEY_ESC, 0)
        p.call("dash")
        p.call("cursor", p.offset_of_line(next(i for i, l in enumerate(p.lines()) if re.match(r"- \[.\] " + re.escape(talked) + r"( |$)", l))) + 8)
        check(p.wait(lambda: "planner agent: Another day, then." in p.call("noteTurns")
                     and "agent: stub answer to: help me think it through" in p.call("noteTurns")),
              f"the note's margin on the box shows the same one conversation ({p.call('noteTurns')}; chat {p.call('chat')}; line {p.call('cursorLine')})")
        p.call("dash")
        p.call("plan", "true")
        check(p.wait(lambda: any(r["kind"] == "proposal" and r["id"] not in settled for _, r in asks()), timeout=15), "another proposal")
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
        check(p.call("dashKey", KEY_RETURN, CTRL) == "true", "Ctrl+Enter files it")
        filed = p.vault / "projects" / "dtm" / "docs" / f"{TODAY_ISO} DTM handout.pdf"
        check(p.wait(lambda: filed.is_file() and not (inbox / "DTM_handout.pdf").exists()),
              "…moved from the inbox into projects/dtm/docs/")
        check((inbox / "Rechnung_4711.pdf").exists(), "…and nothing else moved")
        p.call("dash")
        side_was = p.call("sidebarOpen")
        check(p.wait(lambda: "dtm|" in "".join(json.loads(p.call("projects")))), "the projects are listed")
        p.call("openProject", next(n for n, x in enumerate(json.loads(p.call("projects"))) if x.startswith("dtm|")))
        check(p.wait(lambda: [d["name"] for d in json.loads(p.call("projectDocs"))] == [f"{TODAY_ISO} DTM handout"]),
              f"the project in the sidebar lists its documents ({p.call('projectDocs')})")
        p.call("moveSectionFocus", -1)
        check(p.call("docFocus") == "0", "↑ from the first section reaches the documents")
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
        check(p.wait(lambda: {r.get("ask") for _, r in acts()} >= {"steps", "deadline", "priority", "project"}, timeout=15),
              f"four kinds arrive as rows ({[(r['kind'], r.get('ask')) for _, r in acts()]}; "
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
        check(p.call("dashKeyOn", "proposal", "deadline", KEY_RETURN, CTRL) == "true", "Ctrl+Enter accepts the deadline")
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
        check(p.call("settingsKey", KEY_M, CTRL) == "true" and p.call("settingsView") == "autonomy", "Ctrl+M in settings: what the agent may do")
        check(p.wait(lambda: "priority=do" in p.call("autonomyKinds") and len(json.loads(p.call("autonomyKinds"))) == 8),
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
        p.call("dayKey", 0x01000000, 0)

        # 12b. the keys sheet: every key the page answers to, listed; one
        # moved through the sheet, kept in keys.json, and working in the note
        KEY_B, KEY_K = 0x42, 0x4b
        keysjson = p.tmp / "config" / "longhand" / "keys.json"

        def keys_of(i):
            return json.loads(p.call("keysOf", i))

        p.call("keys")
        check(p.call("keysOpen") == "true", "the keys sheet opens")
        check(keys_of("bold") == ["Ctrl+B"] and keys_of("dashPriority") == ["p"], "…listing every key, bold on Ctrl+B")
        p.call("keysFind", "bold")
        p.call("keysKey", KEY_RETURN, 0)
        p.call("keysKey", KEY_K, CTRL)
        check(keys_of("bold") == ["Ctrl+K"], "Enter, then a key: bold moves to it")
        check(p.wait(lambda: keysjson.exists() and json.loads(keysjson.read_text()) == {"bold": ["Ctrl+K"]}),
              "…and keys.json keeps only that")
        p.call("keysFind", "italic")
        p.call("keysKey", KEY_RETURN, 0)
        p.call("keysKey", KEY_K, 0)
        check("would be typed" in p.call("keysNote"), f"a letter alone is refused where you write ({p.call('keysNote')})")
        p.call("keysKey", KEY_K, CTRL)
        check("again" in p.call("keysNote") and keys_of("bold") == ["Ctrl+K"], "a key bold has: asked first, not taken")
        p.call("keysKey", KEY_K, CTRL)
        check(keys_of("italic") == ["Ctrl+K"] and keys_of("bold") == [], "…and taken on the second press")
        check(p.call("tip", "italic") == "does   Ctrl+K" and p.call("tip", "bold") == "does   no key (Ctrl+/ gives it one)",
              f"a hover's hint names the moved key, or says there is none ({p.call('tip', 'bold')!r})")
        p.call("keysFind", "bold")
        p.call("keysKey", KEY_DELETE, 0)
        check(keys_of("bold") == ["Ctrl+B"], "Del gives bold its own key back")
        check(p.wait(lambda: json.loads(keysjson.read_text()) == {"italic": ["Ctrl+K"]}), "…and the file follows")
        p.call("keysKey", KEY_ESC, 0)
        p.call("keysKey", KEY_ESC, 0)
        check(p.call("keysOpen") == "false", "Esc clears the search, then closes the sheet")

        # Edited by hand, read again; the moved key works in the note.
        keysjson.write_text(json.dumps({"bold": ["ctrl+k"]}))
        check(p.wait(lambda: keys_of("bold") == ["Ctrl+K"]), "keys.json edited by hand is read again")
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "a word here\n")
        p.open_fresh()
        p.wait(lambda: "a word here" in p.call("text"))
        p.call("cursor", p.call("text").index("word") + 1)
        check(p.call("pageKey", KEY_B, CTRL) == "false", "Ctrl+B is nothing once bold has moved")
        check(p.call("pageKey", KEY_K, CTRL) == "true", "…and Ctrl+K is bold")
        check(p.call("tip", "ask") == "does   Ctrl+Enter" and p.call("tip", "bold") == "does   Ctrl+K", "…and the hints say so")
        check(p.wait(lambda: "a **word** here" in p.call("text")), f"…on the word ({p.call('text')!r})")
        keysjson.write_text("{}\n")
        check(p.wait(lambda: keys_of("bold") == ["Ctrl+B"]), "an empty keys.json is every key its own")

        # 12b. The panes (docs/navigation.md): the bracket keys are the
        # sidebar, the middle and the agent's pane, from any box; a pane's
        # key opens it; in the middle, Ctrl+\ flips the note and the
        # dashboard; Esc closes what it is in. (This window never has the
        # keyboard, so where the keys land is checked in the live page.)
        KEY_BL, KEY_BR, KEY_BS = 0x5b, 0x5d, 0x5c
        def panes():
            return json.loads(p.call("panes"))
        p.call("closePanes")
        check(panes()["panes"] == ["center"] and panes()["center"] == "note", f"the note alone ({panes()})")
        check(p.call("pageKey", KEY_BL, CTRL) == "true" and panes()["panes"] == ["left", "center"], f"Ctrl+[ opens the sidebar ({panes()})")
        check(p.call("pageKey", KEY_BR, CTRL) == "true" and panes()["panes"] == ["left", "center", "right"] and panes()["right"] == "day",
              f"Ctrl+] opens the agent's pane, on the day ({panes()})")
        def against():
            sd = json.loads(p.call("sides"))
            return sd["left"] is not None and sd["right"] is not None \
                and sd["left"] == sd["edge"] and sd["rightEnd"] == sd["width"] - sd["edge"] \
                and sd["x"] >= sd["leftEnd"] + sd["gap"] and sd["x"] + sd["w"] + sd["gap"] <= sd["right"]
        check(p.wait(against, 2), f"both panes stand against the window's edges, the note between them ({p.call('sides')})")
        check(p.call("pageKey", KEY_BS, CTRL) == "true" and panes()["here"] == "center" and panes()["center"] == "note",
              f"Ctrl+\\ from the agent's pane: the keys to the middle, nothing flipped ({panes()})")
        check(p.call("pageKey", KEY_BS, CTRL) == "true" and panes()["center"] == "dash" and panes()["right"] == "day",
              f"…and again in the middle: the dashboard, the day beside it ({panes()})")
        check(p.call("dashKey", KEY_ESC, 0) == "true" and panes()["center"] == "note" and panes()["right"] == "day",
              f"Esc on the dashboard: the note, the day still beside it ({panes()})")
        check(p.call("pageKey", KEY_BR, CTRL) == "true" and panes()["here"] == "right", f"Ctrl+] from the note: the keys to the day ({panes()})")
        check(p.call("dayKey", 0x48, CTRL) == "true" and panes()["here"] == "center" and panes()["center"] == "note"
              and panes()["right"] == "day", f"Ctrl+H from the agent's pane: home, today's note with the keys, the pane left open ({panes()})")
        check(p.call("dayKey", KEY_ESC, 0) == "true" and panes()["panes"] == ["left", "center"],
              f"Esc in the day's conversation closes the pane ({panes()})")
        check(panes()["pointer"] == "every", "the pointer follows every selection unless told otherwise")
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
        check(p.wait(lambda: hk()["owned"]), "…Enter again: the page keeps them")
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
        check(p.wait(lambda: p.call("keysListening") == "false" and last_call().startswith("eval if hl.get_current_submap()")),
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
    sys.exit(main())
