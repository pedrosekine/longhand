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
        # Only `accept` does anything, the way student-agent does it.
        self.runner.write_text(f"""#!/bin/bash
[ "$1" = projects ] && exec "{ROOT}/agent/student-agent" "$@"
[ "$1" = accept ] || exit 0
while [ $# -gt 0 ]; do case "$1" in --hash) H=$2; shift;; --index) I=$2; shift;; --date) D=$2; shift;; esac; shift; done
out=$(pomo deadline add one-pager --project DORO friday) || exit 1
id=$(echo "$out" | grep -o '#[0-9]*' | tr -d '#')
F="{self.vault}/agents/student/daily/$D.json"
python3 -c "import json; s=json.load(open('$F')); s['blocks']['$H']['proposals'][int('$I')]['accepted']={{'id': $id}}; json.dump(s, open('$F','w'))"
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
            except (ValueError, KeyError, IndexError, json.JSONDecodeError):
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
        check(len(set(heads)) == 4, f"…with its own heading colours ({','.join(heads)})")
    finally:
        p.close()


def main() -> int:
    theme_switch()
    p = Page()
    try:
        # 1. a checkbox with a date at its end is asked about, and bound
        (p.daily / f"{TODAY}.md").write_text(header(TODAY) + "Plan for the week.\n")
        p.open_fresh()
        p.call("cursorEnd")
        p.call("insert", "- [ ] chapter 2 draft #thesis due fri 17:00")
        p.call("cursor", 1)
        check(p.wait(lambda: json.loads(p.call("ask"))["kind"] == "deadline"), "leaving a dated checkbox asks")
        p.call("yes")
        check(p.wait(lambda: "#thesis 📅 " in p.note() and p.note().rstrip().endswith("17:00 ^d1")), "the line is bound: 📅 date ^d1")
        d = p.deadline(1)
        check(d and d["project"] == "thesis" and d["link"] == f"[[{TODAY}#^d1]]", f"store has it, with project and link ({d})")

        # 2. ticking the line marks it done; 3. its words rename it
        p.call("tick", p.line_of("chapter 2 draft"))
        check(p.wait(lambda: p.deadline(1)["status"] == "done"), "ticking the line marks the deadline done")
        i = p.line_of("chapter 2 draft")
        p.call("cursor", p.offset_of_line(i) + len("- [x] chapter 2 draft #thesis"))
        p.call("insert", " v2")
        p.call("cursor", 1)
        check(p.wait(lambda: p.deadline(1)["title"] == "chapter 2 draft v2"), "editing the words renames it")

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

        # 12. the theme: roles come from the Omarchy palette, headings apart
        pal = p.call("palette")
        heads = pal.split(" h=")[1].split(" ")[0].split(",")
        check("keys=0" not in pal and len(set(heads)) == 4, f"the page draws in the theme's palette ({pal[:60]}…)")
        check(pal.split(" eh=")[1].split(" ")[0] == ",".join(heads), "…and headings get their own colours")

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
