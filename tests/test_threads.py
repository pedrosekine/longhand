"""A conversation through word edits, the runner's side: the page keeps it on
the block's lines (threads.json); talking to it again tells the model what
the block reads now, and the open pass does not take the reworded block for
a new one.

Run: python3 tests/test_threads.py
"""
import datetime as dt
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
AGENT = ROOT / "agent" / "longhand-agent"
sys.path.insert(0, str(ROOT / "agent"))
import blocks  # noqa: E402
import task  # noqa: E402

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
json.dump({"argv": args}, open(os.path.join(d, f"call-{n}.json"), "w"))
reply = {"reply": "noted", "proposals": [], "suggestions": [], "knowledge": []}
print(json.dumps({"type": "text", "sessionID": "ses_thr", "part": {"type": "text", "text": "```json\\n" + json.dumps(reply) + "\\n```"}}))
"""


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="threads-test-"))
    vault = tmp / "vault"
    (vault / "Daily").mkdir(parents=True)
    day = dt.date.today().isoformat()
    note = vault / "Daily" / f"{day}.md"
    asked = "Should I buy an e-scooter?"
    now = "Should I buy an e-scooter, or a bike for the winter?"
    rec = blocks.split(asked)[0]["hash"]
    (vault / "agents/longhand/daily").mkdir(parents=True)
    (vault / "agents/longhand/daily" / f"{day}.json").write_text(json.dumps({"blocks": {rec: {
        "state": "reply", "reply": "By when?", "read": True, "session": "ses_old", "head": asked,
        "key": blocks.fnv1a(task.identity(asked))}}, "suggestions": [], "observations": [], "runs": []}))
    note.write_text(now + "\n")
    state = tmp / "state"
    (state / "longhand").mkdir(parents=True)
    # What the page keeps: the reworded line's words, and the conversation it carries.
    (state / "longhand" / "threads.json").write_text(json.dumps({day: [{"id": task.identity(now).lstrip(), "rec": rec}]}))
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "model": "stub/m"}))
    bindir = tmp / "bin"
    bindir.mkdir()
    (bindir / "opencode").write_text(STUB)
    (bindir / "opencode").chmod(0o755)
    stub = tmp / "stub"
    stub.mkdir()
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(state), XDG_CONFIG_HOME=str(cfgdir),
               STUB_DIR=str(stub), PATH=f"{bindir}:{os.environ['PATH']}")

    def agent(*args):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        assert r.returncode == 0, r.stderr + r.stdout
        return r.stdout

    out = agent("run", "--trigger", "open")
    check("nothing new" in out and not list(stub.glob("call-*.json")),
          "the open pass does not take a reworded block, still carrying its conversation, for a new one")

    agent("chat", "--hash", rec, "--message", "and in winter?")
    call = json.loads(sorted(stub.glob("call-*.json"))[-1].read_text())["argv"]
    check("--session" in call and "ses_old" in call, "talking to it again carries on the same session")
    check(f"The block now reads:\n\n{now}" in call[-1], "…telling the model what the block reads now")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
