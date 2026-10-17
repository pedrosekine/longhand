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
            "runner": str(self.runner), "check": str(ROOT / "cli" / "longhand-check"), "weekStart": "monday"}))
        bindir = self.tmp / "bin"
        bindir.mkdir()
        (bindir / "pomo").symlink_to(ROOT / "cli" / "pomo")
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
        self.runner.write_text(f"""#!/bin/bash
case "$1" in
  accept|projects|sections|next|tasks) exec "{ROOT}/agent/longhand-agent" "$@" ;;
  run) sleep 2; exit 0 ;;
  chat) sleep 2; exec python3 "{chatstub}" "{self.vault}/agents/longhand/daily" "$@" ;;
esac
""")
        self.runner.chmod(0o755)
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(cfg), XDG_STATE_HOME=str(self.state),
                        PATH=f"{bindir}:{os.environ['PATH']}", FAKE_HYPR_DIR=str(self.hypr),
                        FAKE_HYPR_REAL=shutil.which("hyprctl") or "")
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
                return {"title": f[2], "status": f[3], "project": f[6] if len(f) > 6 else "", "link": f[7] if len(f) > 7 else ""}
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
        p.call("type", "dt")
        check(p.wait(lambda: json.loads(p.call("mention")) == ["dtm"]), f"…narrowing as you type ({p.call('mention')})")
        p.call("mentionPick", 0, "false")
        check(p.wait(lambda: "today in #dtm " in p.call("text")), f"Enter writes its tag where the @ was ({p.call('text')[-30:]!r})")
        check(p.call("mention") == "null", "…and the list is done")
        p.call("enter")
        p.call("type", "@ints")
        check(p.wait(lambda: json.loads(p.call("mention")) == ["intsem"]), "@ at a line's start offers the same")
        p.call("mentionPick", 0, "true")
        check(p.wait(lambda: "# Interdisciplinary Seminar #intsem" in p.call("text")),
              f"Shift+Enter starts the class there ({p.call('text')[-40:]!r})")
        p.call("enter")
        p.call("type", "mail me at pedro@it")
        check(p.call("mention") == "null", "an address is not a call")

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

        row("draft the intro")
        check(p.call("dashKey", KEY_RETURN, CTRL) == "true", "Ctrl+Enter is the act that settles a row")
        check(p.wait(lambda: "- [x] draft the intro" in (p.daily / f"{YDAY}.md").read_text()),
              "…and it ticks the line in the day it was written")

        row("ask about the rubric")
        check(p.call("dashType", "t") == "true", "t asks when")
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

        out = p.pomo("add", "Registered topic and supervisor", "2030-01-06")
        wid = int(re.search(r"#(\d+)", out).group(1))
        check(p.wait(lambda: "NOT IN A NOTE YET" in heads()), f"a deadline no note holds waits in its own band ({heads()})")
        row("Registered topic and supervisor")
        p.call("dashKey", KEY_RETURN, 0)
        check(p.wait(lambda: f"Registered topic and supervisor 📅 2030-01-06 ^d{wid}" in p.call("text")),
              "Enter writes it into today's note")
        check(p.wait(lambda: p.deadline(wid)["link"] != ""), "…and the store knows its line")

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
        check(p.wait(lambda: p.call("keysListening") == "false" and last_call().startswith("eval if hl.get_current_submap()")),
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
        p.call("pageKey", KEY_LBRACKET, CTRL)
        check(p.wait(lambda: "three days ago" in p.call("text")), "Ctrl+[: the day before that has a note, days without one skipped")
        p.call("pageKey", KEY_PGUP, CTRL)
        check(p.wait(lambda: "no note before" in p.call("hint")), f"…and at the first note Ctrl+PgUp says so ({p.call('hint')!r})")
        p.call("pageKey", KEY_RBRACKET, CTRL)
        check(p.wait(lambda: "today's words" in p.call("text")), "Ctrl+]: the next one")
        p.call("pageKey", KEY_LBRACKET, CTRL)
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
