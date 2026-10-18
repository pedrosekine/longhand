"""The agent's other actions and how far each may go (docs/agent.md,
slice 5): deadlines from the writing, priorities, steps, dropping a stale
box, "looks done"; the checks on each; the person's autonomy per kind —
ask me, do it and tell me, never — and the record that may suggest raising
one. Against plan.py directly, and the CLI against a stub model.

Run: python3 tests/test_actions.py
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
import plan  # noqa: E402

failures = 0
TODAY = dt.date.today()


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


def day(n):
    return (TODAY + dt.timedelta(days=n)).isoformat()


def units() -> None:
    days = [{"date": day(i)} for i in range(14)]
    cands = [{"key": "k1", "title": "read the paper", "project": "intsem", "due": ""}]
    boxes = [
        {"key": "k1", "title": "read the paper", "project": "intsem", "due": "", "when": "", "priority": 0,
         "steps_under_it": 0, "age_days": 2, "quiet": False},
        {"key": "k2", "title": "essay draft", "project": "intsem", "due": "", "when": "", "priority": 0,
         "steps_under_it": 3, "age_days": 1, "quiet": False},
        {"key": "k3", "title": "learn Unreal", "project": "", "due": "", "when": "", "priority": 0,
         "steps_under_it": 0, "age_days": 30, "quiet": True},
        {"key": "k4", "title": "barber", "project": "", "due": "", "when": "", "priority": 0,
         "steps_under_it": 0, "age_days": 3, "quiet": False},
    ]
    deadlines = [{"title": "Initial paper", "due": dt.datetime.now(), "project": "intsem"}]
    ledger = {"next": 1, "items": []}
    reply = {"proposals": [
        {"kind": "deadline", "title": "Hand in the poster", "date": day(20), "project": "#intsem", "why": "the note says so"},
        {"kind": "deadline", "title": "initial paper", "date": day(9), "why": "already in the store"},
        {"kind": "deadline", "title": "Yesterday's thing", "date": day(-1), "why": "past"},
        {"kind": "priority", "key": "k1", "priority": 2, "why": "due soonest"},
        {"kind": "priority", "key": "k4", "priority": 0, "why": "not a level"},
        {"kind": "steps", "key": "k1", "steps": ["skim the abstract", "note three claims", ""], "why": "big"},
        {"kind": "steps", "key": "k2", "steps": ["more"], "why": "it has steps already"},
        {"kind": "drop", "key": "k4", "why": "young, not stale"},
    ], "questions": []}
    props, _ = plan.validate(reply, cands, days, ledger, TODAY, boxes, deadlines, plan.autonomy({}))
    kinds = [(p["kind"], p.get("key") or p.get("title")) for p in props]
    check(kinds == [("deadline", "Hand in the poster"), ("priority", "k1"), ("steps", "k1")],
          f"each kind is checked against what the planner was shown ({kinds})")
    check(props[0]["project"] == "intsem" and props[2]["steps"] == ["skim the abstract", "note three claims"],
          "…a deadline's project without its #, steps without the empty ones")
    check(not any(p.get("auto") for p in props), "every kind starts at ask me: nothing is done on its own")

    reply = {"proposals": [{"kind": "drop", "key": "k3", "why": "quiet for a month"},
                           {"kind": "done", "key": "k1", "why": ""},
                           {"kind": "done", "key": "k4", "why": "Tuesday's note: 'got a haircut'"}]
             + [{"kind": "priority", "key": k, "priority": 1, "why": "x"} for k in ("k1", "k2", "k3", "k4")],
             "questions": []}
    props, _ = plan.validate(reply, cands, days, ledger, TODAY, boxes, deadlines, plan.autonomy({}))
    check([p["kind"] for p in props] == ["drop", "done", "priority", "priority", "priority"],
          f"a quiet box may be proposed for dropping; 'looks done' must say why; five at most ({[p['kind'] for p in props]})")

    # The person's word on each kind.
    level = plan.autonomy({"autonomy": {"priority": "do", "steps": "never", "done": "do", "drop": "sometimes"}})
    check(level["priority"] == "do" and level["steps"] == "never" and level["done"] == "ask" and level["drop"] == "ask",
          "autonomy: as set, a question stays a question, and an unknown word is 'ask'")
    reply = {"proposals": [{"kind": "priority", "key": "k1", "priority": 2, "why": "x"},
                           {"kind": "steps", "key": "k1", "steps": ["a"], "why": "x"}], "questions": []}
    props, _ = plan.validate(reply, cands, days, ledger, TODAY, boxes, deadlines, level)
    check([p["kind"] for p in props] == ["priority"] and props[0]["auto"] and props[0]["was"] == 0,
          "never: not proposed; do it and tell me: marked for the page to do, with what it was")

    # What was refused is not proposed again.
    ledger = {"next": 1, "items": [dict(props[0], id=1, status="undone", at="x")]}
    props, _ = plan.validate(reply, cands, days, ledger, TODAY, boxes, deadlines, plan.autonomy({}))
    check([p["kind"] for p in props] == ["steps"], "a priority the person undid is not proposed again")

    # The record, and when raising is suggested.
    items = [{"id": i, "kind": "do-date", "key": f"k{i}", "status": "accepted", "resolved": f"2026-10-{i + 10:02d}"}
             for i in range(9)] + [{"id": 9, "kind": "do-date", "key": "k9", "status": "declined", "resolved": "2026-10-19"}]
    r = plan.record_of({"items": items}, "do-date")
    check(r["answered"] == 10 and r["accepted"] == 9 and r["suggest"], "9 of the last 10 accepted: raising is suggested")
    items[3]["status"] = "undone"
    check(not plan.record_of({"items": items}, "do-date")["suggest"], "…an undo counts as a no: 8 of 10 is not enough")
    check(not plan.record_of({"items": [dict(x, kind="done") for x in items]}, "done")["suggest"],
          "…and never for a question")


STUB = """#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB_DIR"]
args = sys.argv[1:]
if args[:1] != ["run"]:
    sys.exit(0)
open(os.path.join(d, "payload.md"), "w").write(sys.stdin.read())
reply = open(os.path.join(d, "reply.json")).read()
print(json.dumps({"type": "text", "sessionID": "ses_act", "part": {"type": "text", "text": "```json\\n" + reply + "\\n```"}}))
"""


def end_to_end() -> None:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="actions-test-"))
    vault = tmp / "vault"
    daily = vault / "Daily"
    daily.mkdir(parents=True)
    (daily / f"{day(0)}.md").write_text("# Interdisciplinary Seminar #intsem\n\n- [ ] read the paper\n\n"
                                        "The poster is due on the 20th of next month.\n\n"
                                        "> [!private]\n> my secret worry\n")
    (daily / f"{day(-2)}.md").write_text("Got the haircut at last.\n\n- [ ] barber\n")
    (daily / f"{day(-3)}.md").write_text("---\nagent: false\n---\nA private day.\n")
    cfgdir = tmp / "config"
    (cfgdir / "longhand").mkdir(parents=True)
    cfg = cfgdir / "longhand" / "config.json"
    cfg.write_text(json.dumps({"vault": str(vault), "daily": {"dir": "Daily", "format": "YYYY-MM-DD"},
                               "agentDir": "agents/longhand", "model": "stub/plan"}))
    settings = cfgdir / "longhand" / "settings.json"
    state = tmp / "state"
    bindir = tmp / "bin"
    bindir.mkdir()
    (bindir / "opencode").write_text(STUB)
    (bindir / "opencode").chmod(0o755)
    stub = tmp / "stub"
    stub.mkdir()
    env = dict(os.environ, LONGHAND_CONFIG=str(cfg), XDG_STATE_HOME=str(state), XDG_CONFIG_HOME=str(cfgdir),
               STUB_DIR=str(stub), PATH=f"{bindir}:{os.environ['PATH']}")

    def agent(*args, ok=True):
        r = subprocess.run([sys.executable, str(AGENT), *args], capture_output=True, text=True, env=env)
        if ok:
            assert r.returncode == 0, r.stderr + r.stdout
        return r

    (stub / "reply.json").write_text(json.dumps({"proposals": [], "questions": [], "knowledge": []}))
    agent("plan", "--force")
    payload = (stub / "payload.md").read_text()
    check("# The student's notes, the last seven days" in payload and "The poster is due on the 20th" in payload
          and "Got the haircut at last." in payload, "the planner reads the week's notes")
    check("my secret worry" not in payload and "A private day." not in payload, "…never a private block or a private day")
    data = json.loads(payload.split("```json\n")[1].split("\n```")[0])
    keys = {b["title"]: b["key"] for b in data["open_boxes"]}
    check(set(keys) == {"read the paper", "barber"} and "steps" in data["you_may"] and "file" not in data["you_may"],
          f"…every open box, and the kinds it may propose ({data['you_may']})")

    (stub / "reply.json").write_text(json.dumps({"proposals": [
        {"kind": "deadline", "title": "Poster", "date": day(30), "project": "intsem", "why": "today's note says so"},
        {"kind": "done", "key": keys["barber"], "why": "Thursday's note: 'Got the haircut at last.'"},
        {"kind": "priority", "key": keys["read the paper"], "priority": 2, "why": "the seminar is close"}],
        "questions": [], "knowledge": []}))
    settings.write_text(json.dumps({"autonomy": {"priority": "do"}}))
    out = json.loads(agent("plan", "--force").stdout)
    check(out["proposals"] == 3, f"three kinds proposed in one plan ({out})")
    props = json.loads(agent("proposals").stdout)
    auto = [x for x in props["open"] if x.get("auto")]
    check(len(props["open"]) == 3 and [x["kind"] for x in auto] == ["priority"],
          "…the priority, raised to 'do it and tell me', waits for the page to do it")
    check(agent("proposal", "undo", "--id", str(auto[0]["id"]), ok=False).returncode == 2, "what was not done cannot be undone")
    agent("proposal", "applied", "--id", str(auto[0]["id"]))
    before = {x["kind"]: x["id"] for x in json.loads(agent("proposals").stdout)["open"]}
    agent("plan", "--force")
    again = json.loads(agent("proposals").stdout)
    check({x["kind"]: x["id"] for x in again["open"]} == before,
          "planning again with the same answer keeps the rows on screen as they were (same ids)")
    check([x["kind"] for x in again["told"]] == ["priority"] and not any(x["kind"] == "priority" for x in again["open"]),
          "…and what it already did and told is not proposed again")
    props = json.loads(agent("proposals").stdout)
    check([x["id"] for x in props["told"]] == [auto[0]["id"]] and props["count"] == 3,
          "done by the page, it is told — and counted in the bar until seen")
    agent("proposal", "undo", "--id", str(auto[0]["id"]))
    items = json.loads((state / "longhand" / "proposals.json").read_text())["items"]
    check(next(x for x in items if x["id"] == auto[0]["id"])["status"] == "undone", "one key undoes it, recorded as undone")
    deadline = next(x for x in props["open"] if x["kind"] == "deadline")
    check(agent("proposal", "applied", "--id", str(deadline["id"]), ok=False).returncode == 2,
          "a proposal at 'ask me' cannot be marked as done by the agent")
    agent("proposal", "accept", "--id", str(deadline["id"]))
    kinds = {k["kind"]: k for k in json.loads(agent("autonomy").stdout)["kinds"]}
    check(kinds["priority"]["level"] == "do" and kinds["deadline"]["accepted"] == 1 and kinds["priority"]["answered"] == 1
          and kinds["done"]["ask_only"], "autonomy lists each kind, its level and its record")

    settings.write_text(json.dumps({"autonomy": {"done": "never", "deadline": "never", "priority": "never"}}))
    agent("plan", "--force")
    payload = (stub / "payload.md").read_text()
    data = json.loads(payload.split("```json\n")[1].split("\n```")[0])
    check("done" not in data["you_may"] and "deadline" not in data["you_may"], "a kind set to never is not offered…")
    items = json.loads((state / "longhand" / "proposals.json").read_text())["items"]
    check(sum(1 for x in items if x["kind"] == "deadline") == 1 and sum(1 for x in items if x["kind"] == "priority") == 1,
          "…and not kept when the model proposes it anyway")


def main() -> int:
    units()
    end_to_end()
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
