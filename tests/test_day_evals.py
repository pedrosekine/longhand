"""The day conversation's evals (docs/agent.md, "The day conversation",
slice 5): its rules — said or silent, asking to search or read, proposals
kept or refused by plan.py's checks, a brief's lines; a later message made
into one payload with its day's first message and the turns between; an
answer rated in the pane, and the weekly review pointing at it — against a
stub model, a throwaway vault and state.

Run: python3 tests/test_day_evals.py
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
import evals  # noqa: E402

failures = 0


def check(cond, what):
    global failures
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        failures += 1


DATA = {"fortnight": [{"date": "2026-10-21", "weekday": "Wed", "on": [], "free_hours": 5, "due": [], "planned": 0},
                      {"date": "2026-10-22", "weekday": "Thu", "on": [], "free_hours": 5, "due": [], "planned": 0}],
        "candidates": [{"key": "k1", "title": "email Frauenberger", "project": "respro", "due": "2026-10-27 23:59",
                        "priority": 0}],
        "open_boxes": [{"key": "k1", "title": "email Frauenberger", "project": "respro", "due": "2026-10-27 23:59",
                        "priority": 0, "steps_under_it": 0, "quiet": False, "age_days": 0}],
        "you_may": ["do-date", "priority"]}
PAYLOAD = ("# Trigger\nkind: day\n\n# What you may propose\n\nComputed by local code; trust it.\n\n```json\n"
           + json.dumps(DATA) + "\n```\n\n# The student says\n\nwhen should I write the email?\n")


def units() -> None:
    case = evals.new_case("day", PAYLOAD, "x-day.md")
    check(case["rules"]["brief_lines"] is None and "propose" in case["rules"] and "search" in case["rules"],
          "a day case is made with the day's rules")
    check(evals.new_case("day", "# Brief\n…", "x-brief-2026-10-20.md")["rules"]["brief_lines"] == [3, 6],
          "…a brief's case with its lines")

    case["rules"].update(propose=["do-date:Frauenberger"], no_propose=["priority"], must_match_any=["Thursday"])
    rules, answer = evals.check_day(case, {"reply": "Today, before Thursday's session.", "proposals": [
        {"kind": "do-date", "key": "k1", "date": "2026-10-21", "why": "before the session"}]})
    check(all(r["pass"] for r in rules) and "◇ do-date: email Frauenberger" in answer,
          f"a proposal that survives plan.py's checks passes, and the judge sees its card ({[r for r in rules if not r['pass']]})")
    rules, _ = evals.check_day(case, {"reply": "Thursday.", "proposals": [
        {"kind": "do-date", "key": "k1", "date": "2026-11-30", "why": "later"}]})
    check(not next(r for r in rules if r["check"].startswith("proposes"))["pass"],
          "…one plan.py refuses (after its due date) does not count")
    rules, _ = evals.check_day(case, {"reply": "Thursday.", "proposals": [
        {"kind": "do-date", "key": "k1", "date": "2026-10-22", "why": "x"},
        {"kind": "priority", "key": "k1", "priority": 2, "why": "x"}]})
    check(not next(r for r in rules if r["check"] == "does not propose priority")["pass"], "a proposal the case forbids fails")

    s = evals.new_case("day", PAYLOAD, "x-day.md")
    s["rules"].update(search=True, search_words=["shortlist"], must_match_any=["never checked while it asks"])
    rules, answer = evals.check_day(s, {"reply": "", "search": [{"words": "supervisor shortlist"}]})
    check(all(r["pass"] for r in rules) and answer.startswith("(asks first: search “supervisor shortlist”"),
          "asking to search: the search is checked, the reply's patterns wait for the answer")
    rules, _ = evals.check_day(s, {"reply": "I think it was Neffke."})
    check(not next(r for r in rules if r["check"] == "asks to search")["pass"], "…answering from memory when it should search fails")

    b = evals.new_case("day", "# Brief\n", "x-brief-2026-10-20.md")
    good, _ = evals.check_day(b, {"reply": "- one\n- two\n- three"})
    bad, _ = evals.check_day(b, {"reply": "One paragraph that says everything at once."})
    check(all(r["pass"] for r in good) and not all(r["pass"] for r in bad), "a brief must be 3–6 lines, each `- `")


STUB = """#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB_DIR"]
args = sys.argv[1:]
if args[:1] != ["run"]:
    sys.exit(0)
n = len([f for f in os.listdir(d) if f.startswith("call-")])
stdin = sys.stdin.read()
json.dump({"argv": args, "stdin": stdin}, open(os.path.join(d, f"call-{n}.json"), "w"))
reply = {"reply": "answer " + str(n) + (" about Thursday" if "# The next message" in stdin else ""), "knowledge": [], "read": []}
print(json.dumps({"type": "text", "sessionID": "ses_e", "part": {"type": "text", "text": "```json\\n" + json.dumps(reply) + "\\n```"}}))
"""


def end_to_end(tmp: pathlib.Path) -> None:
    vault = tmp / "vault"
    (vault / "Daily").mkdir(parents=True)
    (vault / "Daily" / f"{dt.date.today().isoformat()}.md").write_text("# Research #respro\n\nThe session is on Thursday.\n")
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

    agent("install")
    agent("day", "--message", "what first?")
    import time
    time.sleep(1.1)                                   # payload files are named by the second
    agent("day", "--message", "and the email?")
    payloads = sorted((tmp / "state" / "longhand" / "payloads").glob("*-day.md"))
    check(len(payloads) == 2, "two messages, two payloads")
    out = agent("eval", "add", str(payloads[1]), "--id", "later").stdout
    case = json.loads((vault / "agents/longhand/evals/cases/later.json").read_text())
    p = case["payload"]
    check(case["job"] == "day" and "later" in out, "a day payload is added as a day case")
    check("# Your knowledge files" in p and "what first?" in p and "# The conversation since (the same session)" in p
          and "Longhand: answer 0" in p and p.rstrip().endswith("Answer with the same JSON contract.")
          and "and the email?" in p.split("# The next message")[1],
          "a later message is joined to its day's first message and the turns between")
    case["rules"]["must_match_any"] = ["Thursday"]
    (vault / "agents/longhand/evals/cases/later.json").write_text(json.dumps(case))
    r = agent("eval", "run", "--case", "later", "--no-judge", ok=False)
    check(r.returncode == 0 and "PASS later (day" in r.stdout, f"the eval runs it on the day agent ({r.stdout[-300:]!r})")
    status = agent("eval", "status").stdout
    check("cases: 0 margin, 0 plan, 1 day" in status and "day " in status, "eval status counts the day's cases")

    turns = json.loads(next((vault / "agents/longhand/daily").glob("*.json")).read_text())["day"]["turns"]
    i = max(n for n, t in enumerate(turns) if t["role"] == "agent")
    agent("rate", "down", "--day", str(i))
    turns = json.loads(next((vault / "agents/longhand/daily").glob("*.json")).read_text())["day"]["turns"]
    check(turns[i]["rating"]["value"] == "down", "an answer in the day's conversation is rated on its turn")
    check(agent("rate", "up", "--day", "0", ok=False).returncode != 0, "…never a student's turn")
    review = agent("review", "--since", dt.date.today().isoformat()).stdout
    rev = next((vault / "agents/longhand/reviews").glob("*.md")).read_text() if (vault / "agents/longhand/reviews").is_dir() else review
    check("## The day's conversations" in rev and "1 not helpful" in rev and f"eval add {payloads[1]} --job day" in rev,
          "the weekly review lists the answer that missed, with the command that makes it a case")


def main() -> int:
    units()
    end_to_end(pathlib.Path(tempfile.mkdtemp(prefix="day-evals-test-")))
    print("PASS" if failures == 0 else f"{failures} FAILED")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
