"""The day conversation, the runner's side (docs/agent.md, "The day
conversation", 2026-10-21): one session a day, the day's context on the
first message and only what is new after, today's other conversations seen
in full, a block pointed at, a private day, and the margin seeing the day's
last turns — against a stub model, a throwaway vault and state.

Run: python3 tests/test_day.py
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
reply = {"reply": f"answer {n}", "knowledge": [], "read": []}
print(json.dumps({"type": "text", "sessionID": "ses_day", "part": {"type": "text", "text": "```json\\n" + json.dumps(reply) + "\\n```"}}))
"""


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="day-test-"))
    vault = tmp / "vault"
    (vault / "Daily").mkdir(parents=True)
    day = dt.date.today().isoformat()
    note = vault / "Daily" / f"{day}.md"
    note.write_text("# Research Proficiency #respro\n\nShortlist: Frauenberger or Neffke.\n\n- [ ] email the supervisor\n")
    q = "Should I buy an e-scooter?"
    qh = blocks.split(q)[0]["hash"]
    daily = vault / "agents/longhand/daily"
    daily.mkdir(parents=True)
    (daily / f"{day}.json").write_text(json.dumps({"blocks": {qh: {
        "state": "reply", "reply": "By when do you need it?", "head": q, "at": f"{day}T09:00:00",
        "chat": [{"role": "student", "text": "before winter", "at": f"{day}T09:05:00"}]}},
        "suggestions": [], "observations": [], "runs": []}))
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
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(tmp / "state"), XDG_CONFIG_HOME=str(cfgdir),
               STUB_DIR=str(stub), PATH=f"{bindir}:{os.environ['PATH']}")

    def agent(*args, ok=True):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        if ok:
            assert r.returncode == 0, r.stderr + r.stdout
        return r

    def calls():
        return [json.loads(f.read_text()) for f in sorted(stub.glob("call-*.json"))]

    def state():
        return json.loads((daily / f"{day}.json").read_text())

    agent("install")
    check((cfgdir / "opencode" / "agent" / "longhand-day.md").exists(), "install writes the day agent's definition")

    agent("day", "--message", "what should I do first today?")
    first = calls()[-1]
    check("--agent" in first["argv"] and first["argv"][first["argv"].index("--agent") + 1] == "longhand-day"
          and "--session" not in first["argv"], "the first message of the day starts the day agent's own session")
    pay = first["stdin"]
    check("Shortlist: Frauenberger or Neffke." in pay and "# Your knowledge files" in pay,
          "…carrying the day's context: the note and the notebook")
    check("# Today's other conversations" in pay and "By when do you need it?" in pay and "student: before winter" in pay,
          "…and today's other conversations, in full")
    check(pay.rstrip().endswith("what should I do first today?"), "…and what the student says")
    d = state()["day"]
    check(d["session"] == "ses_day" and [t["role"] for t in d["turns"]] == ["student", "agent"]
          and d["turns"][1]["text"] == "answer 0", "the conversation is kept in the day's state, with its session")

    # The margin, later: a new turn there, then the day again.
    st = state()
    later = (dt.datetime.now() + dt.timedelta(seconds=5)).isoformat(timespec="seconds")
    st["blocks"][qh]["chat"].append({"role": "student", "text": "or a bike?", "at": later})
    (daily / f"{day}.json").write_text(json.dumps(st))
    box = next(b for b in blocks.split(note.read_text()) if "email the supervisor" in b["text"])
    agent("day", "--message", "and this one?", "--block", box["hash"])
    second = calls()[-1]
    check("--session" in second["argv"] and "ses_day" in second["argv"] and second["stdin"] == "",
          "a later message continues the same session, sending no context again")
    msg = second["argv"][-1]
    check("# Since your last answer, in today's other conversations" in msg and "student: or a bike?" in msg
          and "before winter" not in msg, "…only what is new in the other conversations")
    check("# The block the student points at" in msg and "> - [ ] email the supervisor" in msg,
          "…and the block the student points at")
    check(state()["day"]["turns"][2].get("block") == box["hash"], "the student's turn keeps the block it pointed at")

    # Cross-visibility: the margin sees the day's last turns.
    ctx = agent("context", "--trigger", "question", "--hash", box["hash"]).stdout
    check("# The day conversation, its last turns" in ctx and "Longhand: answer 1" in ctx and "student: and this one?" in ctx,
          "a block's payload carries the day conversation's last turns")

    # A private day still talks, and sees nothing of the note.
    note.write_text("---\nagent: false\n---\nA private worry.\n")
    st = state()
    st["day"] = {"session": "", "turns": []}
    (daily / f"{day}.json").write_text(json.dumps(st))
    agent("day", "--message", "anything due this week?")
    pay = calls()[-1]["stdin"]
    check("A private worry." not in pay and "today's note is marked private" in pay,
          "a private day: the conversation works, sees nothing of the note, and is told so")

    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
