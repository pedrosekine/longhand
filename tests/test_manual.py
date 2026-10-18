"""The agent's manual (agent/manual.md, manual.py): every key it names is a
real action; the keys are the student's own, moved ones included; a block
that asks how to do something carries it whole, any other names it, and
the agent can ask to read or search it.

Run: python3 tests/test_manual.py
"""
import datetime as dt
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent" / "longhand-agent"
sys.path.insert(0, str(ROOT / "agent"))
sys.path.insert(0, str(ROOT / "plugin-page"))
import hyprkeys  # noqa: E402
import manual  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


STUB = """#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB_DIR"]
args = sys.argv[1:]
if args[:1] != ["run"]:
    sys.exit(0)
n = len([f for f in os.listdir(d) if f.startswith("call-")])
json.dump({"argv": args, "stdin": sys.stdin.read()}, open(os.path.join(d, f"call-{n}.json"), "w"))
asks = json.load(open(os.path.join(d, "asks.json")))
reply = {"reply": "Press Ctrl+D on the line." if "--session" in args else "", "proposals": [], "suggestions": [],
         "knowledge": [], "read": [] if "--session" in args else asks}
print(json.dumps({"type": "text", "sessionID": "ses_man", "part": {"type": "text", "text": "```json\\n" + json.dumps(reply) + "\\n```"}}))
"""


def main() -> int:
    js = (ROOT / "plugin-page" / "Shortcuts.js").read_text()
    ids = set(re.findall(r'\{ id: "(\w+)"', js)) | {"sys:" + a[0] for a in hyprkeys.ACTIONS}
    named = set(re.findall(r"\{key:([\w:]+)\}", manual.MANUAL.read_text()))
    check(named and named <= ids, f"every key the manual names is a real action ({sorted(named - ids)} unknown)")

    tmp = pathlib.Path(tempfile.mkdtemp(prefix="manual-test-"))
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    k = manual.keys(cfgdir)
    check(k.get("deadline") == ["Ctrl+D"] and k.get("sys:page"), "the keys, from Shortcuts.js and Hyprland's")
    (cfgdir / "longhand" / "keys.json").write_text(json.dumps({"deadline": ["Ctrl+Shift+D"]}))
    t = manual.text(cfgdir)
    check("`Ctrl+Shift+D`" in t and "{key:" not in t and "<!--" not in t,
          "a key the student moved reads as theirs, and nothing is left unfilled")
    check(manual.render("{key:deadline}", {}) == "(a key: see the keys list, Ctrl+/)", "…without node, it says where the keys are")
    pages = manual.pages(cfgdir)
    check(pages[0].startswith("## The page") and any(p.startswith("## Deadlines") for p in pages), "cut into its sections")

    check(manual.asks_how("how do I reschedule a deadline?") and manual.asks_how("Is there a shortcut for bold?"),
          "a how-to question is recognised")
    check(not manual.asks_how("Should I buy an e-scooter?") and not manual.asks_how("- [ ] read the paper"),
          "…and a question about life, or a box, is not")

    vault = tmp / "vault"
    daily = vault / "Daily"
    daily.mkdir(parents=True)
    note = daily / f"{dt.date.today().isoformat()}.md"
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "model": "stub/margin"}))
    bindir = tmp / "bin"
    bindir.mkdir()
    (bindir / "opencode").write_text(STUB)
    (bindir / "opencode").chmod(0o755)
    stub = tmp / "stub"
    stub.mkdir()
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(tmp / "state"), XDG_CONFIG_HOME=str(cfgdir),
               STUB_DIR=str(stub), PATH=f"{bindir}:{os.environ['PATH']}")

    def agent(*args):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        assert r.returncode == 0, r.stderr + r.stdout
        return r.stdout

    import blocks  # noqa: E402
    note.write_text("How do I reschedule a deadline?\n\n- [ ] read the paper\n")
    bl = blocks.split(note.read_text())
    how = agent("context", "--trigger", "question", "--hash", bl[0]["hash"])
    check("# Longhand's manual — what the page can do" in how and "`Ctrl+Shift+D`" in how,
          "a how-to block carries the manual whole, with the student's keys")
    box = agent("context", "--trigger", "checkbox", "--hash", bl[1]["hash"])
    check("Not carried this time" in box and "## Deadlines" not in box, "any other block only names it")
    check("Longhand's manual" not in agent("context", "--trigger", "open"), "…and the open pass does not")

    (stub / "asks.json").write_text(json.dumps([{"document": "Longhand's manual", "words": "reschedule"}]))
    agent("run", "--trigger", "checkbox", "--hash", bl[1]["hash"])
    calls = sorted(stub.glob("call-*.json"))
    msg = json.loads(calls[-1].read_text())["argv"][-1] if len(calls) == 2 else ""
    check(len(calls) == 2 and "Longhand's manual — passages with “reschedule”" in msg and "`Ctrl+Shift+D`" in msg,
          "asked for, the manual is searched like a document — by section, with the student's keys")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
