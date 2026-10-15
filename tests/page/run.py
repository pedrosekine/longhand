#!/usr/bin/env python3
"""The page's own logic, driven live: bound lines, prompts, catching up with
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
# way `student-agent chat` records them. Enough for the page to settle the
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
        (self.state / "omarchy-student").mkdir(parents=True)
        self.store = self.state / "omarchy-student" / "deadlines.tsv"
        cfg = self.tmp / "config"
        (cfg / "omarchy-student").mkdir(parents=True)
        (cfg / "omarchy").symlink_to(pathlib.Path.home() / ".config" / "omarchy")   # the theme
        self.runner = self.tmp / "runner"
        (cfg / "omarchy-student" / "config.json").write_text(json.dumps({
            "vault": str(self.vault), "daily": {"dir": "Daily", "format": "YYYY.MM.DD"},
            "runner": str(self.runner), "weekStart": "monday"}))
        bindir = self.tmp / "bin"
        bindir.mkdir()
        (bindir / "pomo").symlink_to(ROOT / "cli" / "pomo")
        # Only the local commands run (no model): accept, projects, sections.
        # A model pass is a stub that takes its time, so the page's "this is
        # away" mark can be seen while it is away; `chat` also writes the
        # day's state the way the runner would, so the whole turn can be
        # followed — sent, thinking, answered.
        chatstub = self.tmp / "chatstub.py"
        chatstub.write_text(CHAT_STUB)
        self.runner.write_text(f"""#!/bin/bash
case "$1" in
  accept|projects|sections|next|tasks) exec "{ROOT}/agent/student-agent" "$@" ;;
  run) sleep 2; exit 0 ;;
  chat) sleep 2; exec python3 "{chatstub}" "{self.vault}/agents/student/daily" "$@" ;;
esac
""")
        self.runner.chmod(0o755)
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(cfg), XDG_STATE_HOME=str(self.state),
                        PATH=f"{bindir}:{os.environ['PATH']}")
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
    return f"[[agents/student/daily/{stem}|agent]]\n\n"


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
        check(len(set(heads)) == 4 and heads[0] == want,
              f"…and the new theme's accent leads the heading ramp ({','.join(heads)})")
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

        # 4. Ctrl+D binds a plain line
        p.call("cursor", p.offset_of_line(p.line_of("Plan for the week")))
        p.call("ctrlD")
        time.sleep(0.3)
        p.call("when", "tomorrow")
        check(p.wait(lambda: "Plan for the week. 📅 " in p.note() and "^d2" in p.note()), "Ctrl+D + when binds a plain line")

        # 5. deleting a bound line asks; a typed letter never answers
        p.call("removeLine", p.line_of("^d1"))
        check(p.wait(lambda: json.loads(p.call("ask"))["kind"] == "delete"), "deleting a bound line asks")
        consumed = p.call("typeAtPrompt", "y")
        check(consumed == "false" and p.call("ask") == "null", "typing 'y' does not answer the prompt (it dismisses it and types)")
        time.sleep(0.5)
        check(p.deadline(1)["status"] == "done", "…and the deadline is untouched")
        p.call("removeLine", p.line_of("^d2"))
        p.wait(lambda: json.loads(p.call("ask"))["kind"] == "delete")
        p.call("rightAtPrompt")
        p.call("enterAtPrompt")
        check(p.wait(lambda: p.deadline(2)["status"] == "hidden"), "choosing yes hides it (kept in history), not rm")

        # 6. changes made outside reach the lines when their note opens
        p.pomo("add", "from cli", "friday")
        p.pomo("add", "goes away", "friday")
        (p.daily / f"{YDAY}.md").write_text(header(YDAY) + "- [ ] from cli 📅 2030-01-01 ^d3\n- [ ] goes away 📅 2030-01-01 ^d4\n")
        p.pomo("done", "3")
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
        (p.vault / "agents" / "student" / "daily").mkdir(parents=True, exist_ok=True)
        (p.vault / "agents" / "student" / "daily" / f"{TODAY}.json").write_text(json.dumps({"blocks": {h: {
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
        (p.vault / "agents" / "student" / "daily" / f"{TODAY}.json").write_text(json.dumps({"blocks": {
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
        (p.vault / "agents" / "student" / "daily" / f"{TODAY}.json").write_text(json.dumps({"blocks": {h: {
            "state": "reply", "reply": "Today?", "read": True,
            "proposals": [{"kind": "deadline", "title": "Take a look into the Canvas course and thesis suggestions",
                           "when": f"today ({dt.date.today():%Y-%m-%d})", "project": "respro"}]}}}))
        p.call("cursor", p.offset_of_line(p.line_of("Canvas")) + 8)
        time.sleep(0.4)
        p.call("acceptAt", 0)
        time.sleep(1.5)
        check(len(p.store.read_text().splitlines()) == count, "accepting the agent's proposal for it afterwards adds none either")

        # 11. projects in the sidebar: the tags that exist, a class started
        pd = p.vault / "agents" / "student" / "knowledge" / "projects"
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
        before = len(list((p.state / "omarchy-student" / "payloads").glob("*"))) if (p.state / "omarchy-student" / "payloads").is_dir() else 0
        p.call("cursorEnd")
        p.call("type", " Is this ok?")
        p.call("askNow")
        time.sleep(1)
        after = len(list((p.state / "omarchy-student" / "payloads").glob("*"))) if (p.state / "omarchy-student" / "payloads").is_dir() else 0
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

        before = len(list((p.state / "omarchy-student" / "payloads").glob("*"))) \
            if (p.state / "omarchy-student" / "payloads").is_dir() else 0
        p.call("askNow")
        time.sleep(1)
        after = len(list((p.state / "omarchy-student" / "payloads").glob("*"))) \
            if (p.state / "omarchy-student" / "payloads").is_dir() else 0
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

        # 12. the theme: roles come from the Omarchy palette, and the heading
        # levels are one colour walking home to the text (2026-10-15) — four
        # distinct steps, H1 chromatic and never fainter than 4.5:1, H4 the
        # prose itself.
        pal = p.call("palette")
        heads = pal.split(" h=")[1].split(" ")[0].split(",")
        fg = pal.split(" fg=")[1].split(" ")[0]
        bg = pal.split(" bg=")[1].split(" ")[0]
        check("keys=0" not in pal and len(set(heads)) == 4, f"the page draws in the theme's palette ({pal[:60]}…)")
        check(pal.split(" eh=")[1].split(" ")[0] == ",".join(heads), "…and the editor draws headings with them")
        check(heads[3] == fg, f"a deep heading is simply the text ({heads[3]} vs {fg})")
        rgb = [int(heads[0].lstrip("#")[-6:][i:i + 2], 16) for i in (0, 2, 4)]
        check(max(rgb) - min(rgb) >= 38, f"H1 carries the theme's colour, not a grey ({heads[0]})")
        check(contrast(heads[0], bg) >= 4.4, f"…and reads at 4.5:1 ({contrast(heads[0], bg):.1f}:1)")
        steps = [contrast(h, bg) for h in heads]
        check(steps == sorted(steps) or steps == sorted(steps, reverse=True),
              f"the four steps move one way only ({[round(s, 1) for s in steps]})")

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
              f"…read by the note's own parser, written as a day with no hour ({(p.daily / f'{YDAY}.md').read_text()!r})")
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

        # 13. the usage log: written on close, event names only
        p.call("closeAll")
        usage = p.state / "omarchy-student" / "usage.tsv"
        check(p.wait(lambda: "\tclose\t" in usage.read_text()), "closing the page writes its usage log")
        events = {line.split("\t")[1] for line in usage.read_text().splitlines()}
        check({"open", "close", "ctrl-d", "bound", "day", "prompt"} <= events, f"…with what was used ({sorted(events)})")
        check(not any(w in usage.read_text() for w in ("chapter", "obsidian", "one-pager")), "…and none of the note's words")
    finally:
        p.close()
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
