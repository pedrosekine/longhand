#!/usr/bin/env python3
"""plugin-page/hyprkeys.py, offline: the six Hyprland keys taken over from
bindings.lua, moved, taken from another bind and given back, and a write
Hyprland refuses put back. Runs against a throwaway hypr folder and
tests/fake_hyprctl.py; your Hyprland is never touched.

Run: python3 tests/test_hyprkeys.py
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "plugin-page"))
import hyprkeys  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


# As it is on Pedro's laptop: the ids from before the rename to Longhand.
PEDRO = """-- Keep only your personal keybinding overrides here.
o.bind("SUPER + SHIFT + T", "Todoist", { webapp = "https://app.todoist.com/app/today", focus = true })

-- Pomodoro (omarchy-student v0.1, no conflicts).
o.bind("SUPER + ALT + P", "Pomo toggle", "pomo toggle")
o.bind("SUPER + ALT + N", "Pomo skip", "pomo skip")
o.bind("SUPER + ALT + O", "Pomo popup", "omarchy-shell student.pomo toggle")
o.bind("SUPER + ALT + D", "Deadlines popup", "omarchy-shell student.deadline toggle")
o.bind("SUPER + ALT + equal", "Page (today's note)", "omarchy-shell shell toggle student.page '{}'")
o.bind("SUPER + ALT + backslash", "Page alongside", "omarchy-shell shell summon student.page '{\\"shape\\":\\"alongside\\"}'")
"""

# Another student: the timer on other keys under other names, the rest never bound.
OTHER = """o.bind("SUPER + CTRL + P", "Pomodoro", 'pomo toggle')
-- o.bind("SUPER + CTRL + N", "Pomodoro skip", "pomo skip")
"""


class Hypr:
    def __init__(self, bindings):
        self.tmp = pathlib.Path(tempfile.mkdtemp(prefix="hyprkeys-test-"))
        self.dir = self.tmp / "config" / "hypr"
        self.dir.mkdir(parents=True)
        (self.dir / "bindings.lua").write_text(bindings)
        bindir = self.tmp / "bin"
        bindir.mkdir()
        (bindir / "hyprctl").write_text(f'#!/bin/sh\nexec python3 "{ROOT}/tests/fake_hyprctl.py" "$@"\n')
        (bindir / "hyprctl").chmod(0o755)
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(self.tmp / "config"), FAKE_HYPR_DIR=str(self.dir),
                        PATH=f"{bindir}:{os.environ['PATH']}")

    def run(self, *args):
        r = subprocess.run([sys.executable, str(ROOT / "plugin-page" / "hyprkeys.py"), *args],
                           capture_output=True, text=True, env=self.env)
        return json.loads(r.stdout)

    def keys(self, st=None):
        st = st or self.run("state")
        return {a["id"]: a["keys"] for a in st["actions"]}

    def file(self, name):
        p = self.dir / name
        return p.read_text() if p.exists() else None

    def calls(self):
        return self.file("calls") or ""

    def close(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


# The spellings
check(hyprkeys.from_hypr("SUPER + ALT + equal") == "Alt+Super+=", "SUPER + ALT + equal reads as Alt+Super+=")
check(hyprkeys.from_hypr("SUPER + SHIFT + T") == "Shift+Super+T", "…and SUPER + SHIFT + T as Shift+Super+T")
check(hyprkeys.to_hypr("Alt+Super+\\") == ("SUPER + ALT + backslash", ""), "Alt+Super+\\ writes as SUPER + ALT + backslash")
check(hyprkeys.to_hypr("Ctrl+Alt+Shift+Super+F5")[0] == "SUPER + CTRL + ALT + SHIFT + F5", "…modifiers in Omarchy's order")
check("Super" in hyprkeys.to_hypr("Ctrl+Alt+K")[1], "a key without Super is refused")
check(hyprkeys.to_hypr("Super+?")[0] == "", "a symbol that needs Shift is refused")
check(hyprkeys.to_hypr('Super+"); os.execute("x')[0] == "", "anything else is not a key, and never written")

# Pedro: the six in bindings.lua, taken over once
h = Hypr(PEDRO)
st = h.run("state")
check(not st["owned"] and st["lines"] == 6, "before: the six are the student's own lines in bindings.lua")
check(h.keys(st)["page"] == ["Alt+Super+="] and h.keys(st)["pomoToggle"] == ["Alt+Super+P"], "…read where they are")
check(any(o["does"] == "Full width" for o in st["others"]), "…and Hyprland's other binds are known")
st = h.run("adopt")
b = h.file("bindings.lua")
check(st["owned"] and not st.get("error"), f"adopt: the page keeps them ({st['note']})")
check(b.count("hypr.longhand") == 1 and b.rstrip().endswith(hyprkeys.REQUIRE), "…one line loading longhand.lua, last")
check(sum(1 for l in b.splitlines() if l.startswith("-- o.bind(") and "moved to hypr/longhand.lua" in l) == 6,
      "…the six old lines commented out, saying where they went")
check('o.bind("SUPER + SHIFT + T", "Todoist"' in b and not b.count("-- o.bind(\"SUPER + SHIFT + T\""), "…the student's other lines untouched")
backups = list(h.dir.glob("bindings.lua.bak.*"))
check(len(backups) == 1 and backups[0].read_text() == PEDRO, "…bindings.lua backed up first, as it was")
check(h.keys(st)["page"] == ["Alt+Super+="] and 'o.bind("SUPER + ALT + equal", "Page (today\'s note)"' in h.file("longhand.lua"),
      "…the keys carried over into longhand.lua")
check("reload config-only" in h.calls(), "…and Hyprland reloaded")
st = h.run("adopt")
check(h.file("bindings.lua").count("hypr.longhand") == 1 and len(list(h.dir.glob("bindings.lua.bak.*"))) == 1,
      "adopting twice changes nothing")

# Moving one
st = h.run("set", "pomoToggle", "Alt+Super+K")
check(h.keys(st)["pomoToggle"] == ["Alt+Super+K"] and 'o.bind("SUPER + ALT + K", "Pomo toggle", "pomo toggle")' in h.file("longhand.lua"),
      "set: the timer moves to Super+Alt+K")
st = h.run("set", "pomoToggle", "Alt+Super+N")
check(h.keys(st)["pomoToggle"] == ["Alt+Super+N"] and h.keys(st)["pomoSkip"] == [] and "Pomo skip" in st["note"],
      "a key another of the six has moves here, and says from where")
h.run("set", "pomoSkip", "Alt+Super+J")
st = h.run("set", "pomoToggle", "--add", "Alt+Super+P")
check(h.keys(st)["pomoToggle"] == ["Alt+Super+N", "Alt+Super+P"], "--add puts a second key beside the first")

# Taking a key from Hyprland, and giving it back
st = h.run("set", "deadlines", "Alt+Super+F")
check(st.get("asks", {}).get("does") == "Full width" and h.keys(st)["deadlines"] == ["Alt+Super+D"],
      "a key Hyprland uses is asked about, not taken")
st = h.run("set", "deadlines", "--take", "Alt+Super+F")
ours = h.file("longhand.lua")
check(h.keys(st)["deadlines"] == ["Alt+Super+F"] and 'hl.unbind("SUPER + ALT + F")  -- was: Full width' in ours,
      "--take: unbound in longhand.lua, with what it was")
check(not any(o["does"] == "Full width" for o in st["others"]) and st["taken"] == {"Alt+Super+F": "Full width"},
      "…Full width is gone from Hyprland while the deadlines have it")
st = h.run("set", "deadlines", "Alt+Super+D")
check("hl.unbind" not in h.file("longhand.lua") and any(o["does"] == "Full width" for o in st["others"]),
      "moving off it gives Full width its key back")

# Refused
st = h.run("set", "pomoSkip", "Ctrl+Alt+J")
check("Super" in st.get("error", "") and h.keys(st)["pomoSkip"] == ["Alt+Super+J"], "a key without Super: refused, nothing written")
before = h.file("longhand.lua")
(h.dir / "break").write_text("SUPER + ALT + L")
st = h.run("set", "pomoSkip", "Alt+Super+L")
check("refused" in st.get("error", "") and h.file("longhand.lua") == before, "a write Hyprland refuses is put back")
check(h.calls().count("reload config-only") >= 2, "…and Hyprland reloaded on the old file")
(h.dir / "break").unlink()

# Read back after a hand edit
h.dir.joinpath("longhand.lua").write_text(h.file("longhand.lua").replace('"SUPER + ALT + J"', '"SUPER + ALT + H"'))
check(h.keys()["pomoSkip"] == ["Alt+Super+H"], "a key edited by hand in longhand.lua is read back")
h.close()

# Another student: other keys, other names, some never bound
h = Hypr(OTHER)
st = h.run("state")
check(h.keys(st)["pomoToggle"] == ["Ctrl+Super+P"] and st["lines"] == 1, "another student's own key is found by what it runs")
st = h.run("adopt")
k = h.keys(st)
check(k["pomoToggle"] == ["Ctrl+Super+P"] and k["pomoSkip"] == ["Alt+Super+N"] and k["page"] == ["Alt+Super+="],
      "…kept on adopting, and the ones never bound get their own keys")
check(h.file("bindings.lua").startswith('-- o.bind("SUPER + CTRL + P", "Pomodoro"') and '-- o.bind("SUPER + CTRL + N"' in h.file("bindings.lua"),
      "…their line commented out, a line already commented left as it was")
h.close()

# From before the rename: student.lua and the line loading it, moved once
OLD_OURS = """-- omarchy-student's Hyprland keys: the page, the timer, the deadlines.

-- Keys these took from another bind; the bind comes back once none of
-- the keys below is on it.
hl.unbind("SUPER + ALT + F")  -- was: Full width

o.bind("SUPER + ALT + equal", "Page (today's note)", "omarchy-shell shell toggle student.page '{}'")
o.bind("SUPER + ALT + F", "Deadlines popup", "omarchy-shell student.deadline toggle")
o.bind("SUPER + ALT + K", "Pomo toggle", "pomo toggle")
"""
OLD_BINDINGS = """o.bind("SUPER + SHIFT + T", "Todoist", { webapp = "https://app.todoist.com/app/today", focus = true })
-- o.bind("SUPER + ALT + P", "Pomo toggle", "pomo toggle")  -- moved to hypr/student.lua by the page, 2026-10-16

-- omarchy-student's keys (the page, the timer, the deadlines) live in
-- hypr/student.lua, written by the page's keys sheet (Ctrl+/). Delete this
-- line to drop them; the lines above that it moved stay commented out.
require("default.hypr.require_optional").module("hypr.student")
"""
h = Hypr(OLD_BINDINGS)
(h.dir / "student.lua").write_text(OLD_OURS)
st = h.run("state")
b, ours = h.file("bindings.lua"), h.file("longhand.lua") or ""
check(st["owned"] and h.file("student.lua") is None and "student.lua" in st["note"],
      f"student.lua becomes longhand.lua on the first call ({st['note']})")
check(h.keys(st)["page"] == ["Alt+Super+="] and h.keys(st)["deadlines"] == ["Alt+Super+F"] and h.keys(st)["pomoToggle"] == ["Alt+Super+K"]
      and st["taken"] == {"Alt+Super+F": "Full width"}, "…the same keys, the taken one still taken")
check("omarchy-shell longhand.deadline toggle" in ours and "student." not in ours, "…their commands name longhand.*")
check(b.rstrip().endswith(hyprkeys.REQUIRE) and "hypr.student" not in b and "hypr/longhand.lua" in b
      and 'o.bind("SUPER + SHIFT + T", "Todoist"' in b, "…bindings.lua loads the new file, its other lines untouched")
backups = list(h.dir.glob("bindings.lua.bak.*"))
check(len(backups) == 1 and backups[0].read_text() == OLD_BINDINGS, "…bindings.lua backed up first, as it was")
h.run("state")
check(len(list(h.dir.glob("bindings.lua.bak.*"))) == 1 and h.file("longhand.lua") == ours, "moving twice changes nothing")
h.close()

h = Hypr(OLD_BINDINGS)
(h.dir / "student.lua").write_text(OLD_OURS)
(h.dir / "break").write_text("longhand.page")
st = h.run("state")
check("refused" in st.get("error", "") and h.file("student.lua") == OLD_OURS and h.file("longhand.lua") is None
      and h.file("bindings.lua") == OLD_BINDINGS, "a move Hyprland refuses is put back, both files as they were")
h.close()

# No bindings.lua: nothing to load from, nothing written
h = Hypr("")
(h.dir / "bindings.lua").unlink()
st = h.run("adopt")
check(st.get("error") and h.file("longhand.lua") is None, "no bindings.lua: refused, nothing written")
h.close()

print("all ok" if failures == 0 else f"{failures} failed")
sys.exit(1 if failures else 0)
