#!/usr/bin/env python3
"""tools/migrate-to-longhand, offline: an omarchy-student install in a
throwaway $HOME is moved to Longhand's names, every file of it still there
byte for byte, and a second run changes nothing. Your $HOME is never touched.

Run: python3 tests/test_migrate.py
"""
import hashlib
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


def sums(d):
    return {str(p.relative_to(d)): hashlib.sha256(p.read_bytes()).hexdigest() for p in d.rglob("*") if p.is_file()}


home = pathlib.Path(tempfile.mkdtemp(prefix="longhand-migrate-test-"))
cfg, state, vault = home / ".config", home / ".local" / "state", home / "vault"
hypr = cfg / "hypr"

# An install as omarchy-student left it
(cfg / "omarchy-student").mkdir(parents=True)
(cfg / "omarchy-student" / "config.json").write_text(json.dumps({
    "vault": str(vault), "daily": {"dir": "human/Daily", "format": "YYYY-MM-DD", "template": "agents/student/templates/daily"},
    "agentDir": "agents/student", "curriculum": "agents/student/curriculum", "weekStart": "monday"}, indent=2))
(cfg / "omarchy-student" / "keys.json").write_text('{"pomoSkip": ["Ctrl+J"]}\n')
st = state / "omarchy-student"
(st / "payloads").mkdir(parents=True)
for name, text in {"deadlines.tsv": "1\tEssay\t2026-10-20\n", "pomo.log": "focus completed\n", "cost.tsv": "0.01\n",
                   "usage.tsv": "open\n", "state.json": "{}", "payloads/2026-10-16.md": "payload\n"}.items():
    (st / name).write_text(text)
for sub, name, text in [("daily", "2026-10-16.md", "## reply\n"), ("daily", "2026-10-16.json", "{}"),
                        ("templates", "daily.md", "[[agents/student/daily/{{date}}|agent]]\n"),
                        ("knowledge", "profile.md", "profile\n")]:
    (vault / "agents" / "student" / sub).mkdir(parents=True, exist_ok=True)
    (vault / "agents" / "student" / sub / name).write_text(text)
(vault / "human" / "Daily").mkdir(parents=True)
(vault / "human" / "Daily" / "2026-10-16.md").write_text("[[agents/student/daily/2026-10-16|agent]]\n\nmy own words about agents/student\n")
(vault / "human" / "Daily" / "2026-10-15.md").write_text("no link here\n")
plugins = cfg / "omarchy" / "plugins"
for n in ("page", "pomo", "deadline"):
    (plugins / f"student.{n}").mkdir(parents=True)
    (plugins / f"student.{n}" / "manifest.json").write_text(f'{{"id": "student.{n}"}}')
SHELL = '{\n  "bar": {"layout": {"right": [{"id": "student.page"}, {"id": "student.pomo"}, {"id": "omarchy.clock"}]}},\n  "plugins": [{"id": "student.page"}]\n}\n'
(cfg / "omarchy" / "shell.json").write_text(SHELL)
hypr.mkdir(parents=True)
(hypr / "bindings.lua").write_text('o.bind("SUPER + T", "Terminal", "x")\nrequire("default.hypr.require_optional").module("hypr.student")\n')
(hypr / "student.lua").write_text('o.bind("SUPER + ALT + equal", "Page (today\'s note)", "omarchy-shell shell toggle student.page \'{}\'")\n')
(home / ".local" / "bin").mkdir(parents=True)
(home / ".local" / "bin" / "student-agent").symlink_to(ROOT / "agent" / "student-agent")
(cfg / "opencode" / "agent").mkdir(parents=True)
(cfg / "opencode" / "agent" / "student.md").write_text("old agent\n")

before_state, before_cfg = sums(st), sums(cfg / "omarchy-student")
before_vault = sums(vault / "agents" / "student")

bindir = home / "fakebin"
bindir.mkdir()
(bindir / "hyprctl").write_text(f'#!/bin/sh\nexec python3 "{ROOT}/tests/fake_hyprctl.py" "$@"\n')
(bindir / "hyprctl").chmod(0o755)
env = {k: v for k, v in os.environ.items() if not k.startswith("XDG_")}
env.update(HOME=str(home), FAKE_HYPR_DIR=str(hypr), PATH=f"{bindir}:{os.environ['PATH']}")


def run(*args):
    return subprocess.run([sys.executable, str(ROOT / "tools" / "migrate-to-longhand"), *args],
                          capture_output=True, text=True, env=env)


r = run()
check(r.returncode == 0 and "dry run" in r.stdout and (cfg / "omarchy-student").is_dir()
      and not (cfg / "omarchy-student").is_symlink() and sums(st) == before_state,
      "a dry run says what it would do and changes nothing")

r = run("--apply")
check(r.returncode == 0, "--apply runs" + ("" if r.returncode == 0 else ": " + r.stdout + r.stderr))
check(sums(state / "longhand") == before_state, "state: every file in ~/.local/state/longhand, byte for byte")
check((state / "omarchy-student").is_symlink() and (state / "omarchy-student" / "deadlines.tsv").read_text() == "1\tEssay\t2026-10-20\n",
      "…the old path a symlink to it, still read")
new_cfg = json.loads((cfg / "longhand" / "config.json").read_text())
check((cfg / "longhand" / "keys.json").read_text() == '{"pomoSkip": ["Ctrl+J"]}\n' and (cfg / "omarchy-student").is_symlink(),
      "config: keys.json in ~/.config/longhand, the old path a symlink")
check(new_cfg["agentDir"] == "agents/longhand" and new_cfg["curriculum"] == "agents/longhand/curriculum"
      and new_cfg["daily"]["template"] == "agents/longhand/templates/daily" and new_cfg["weekStart"] == "monday",
      "…config.json points at agents/longhand, the rest as it was")
after_vault = sums(vault / "agents" / "longhand")
check(not (vault / "agents" / "student").exists() and set(after_vault) == set(before_vault)
      and all(after_vault[k] == before_vault[k] for k in after_vault if k != "templates/daily.md"),
      "vault: agents/student is agents/longhand, every file in it")
check((vault / "agents" / "longhand" / "templates" / "daily.md").read_text() == "[[agents/longhand/daily/{{date}}|agent]]\n",
      "…the template's link follows")
check((vault / "human" / "Daily" / "2026-10-16.md").read_text()
      == "[[agents/longhand/daily/2026-10-16|agent]]\n\nmy own words about agents/student\n",
      "…a daily note's link follows, the words written in it do not change")
check((vault / "human" / "Daily" / "2026-10-15.md").read_text() == "no link here\n", "…a note without the link untouched")
shell = (cfg / "omarchy" / "shell.json").read_text()
check(shell == SHELL.replace('"student.', '"longhand.'), "shell.json: the ids are longhand.*, nothing else changed")
check(len(list((cfg / "omarchy").glob("shell.json.bak.*"))) == 1, "…backed up beside it first")
check(all((plugins / f"longhand.{n}" / "manifest.json").exists() and not (plugins / f"student.{n}").exists()
          for n in ("page", "pomo", "deadline")), "plugins: longhand.* installed, student.* moved aside")
check(json.loads((plugins / "longhand.page" / "manifest.json").read_text())["id"] == "longhand.page", "…from this repo")
check((hypr / "longhand.lua").exists() and not (hypr / "student.lua").exists()
      and "hypr.longhand" in (hypr / "bindings.lua").read_text(), "hypr: longhand.lua, loaded by bindings.lua")
b = home / ".local" / "bin"
check(os.readlink(b / "longhand-agent") == str(ROOT / "agent" / "longhand-agent") and os.readlink(b / "student-agent") == "longhand-agent",
      "cli: longhand-agent, the old name a symlink to it")
oc = cfg / "opencode" / "agent"
check((oc / "longhand.md").exists() and not (oc / "student.md").exists(), "opencode: longhand.md replaces student.md")
backup = home / "Backups"
kept = list(backup.glob("longhand-rename-*"))
check(len(kept) == 1 and sums(kept[0] / ".local" / "state" / "omarchy-student") == before_state
      and sums(kept[0] / "vault" / "agents" / "student") == before_vault
      and (kept[0] / ".config" / "opencode" / "agent" / "student.md").exists()
      and (kept[0] / ".config" / "hypr" / "student.lua").exists(),
      "a copy of everything moved or replaced is in ~/Backups")

snapshot = {d: sums(d) for d in (state / "longhand", cfg / "longhand", vault, cfg / "omarchy")}
r = run("--apply")
check(r.returncode == 0 and all(sums(d) == s for d, s in snapshot.items() if d != cfg / "omarchy")
      and len(list((cfg / "omarchy").glob("shell.json.bak.*"))) == 1 and "move " not in r.stdout,
      "a second run moves nothing")

shutil.rmtree(home, ignore_errors=True)
print("all ok" if failures == 0 else f"{failures} failed")
sys.exit(1 if failures else 0)
